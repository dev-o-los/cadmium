import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:dart_ytmusic_api/types.dart';
import 'package:dart_ytmusic_api/utils/traverse.dart';
import 'package:dart_ytmusic_api/yt_music.dart';
import '../models/song_item.dart';
import '../models/album_item.dart';
import '../models/video_item.dart';
import '../models/hero_card_item.dart';
import '../models/music_category.dart';
import '../models/lyric_line.dart';
import '../models/home_data.dart';
import '../models/user_account.dart';
import '../models/playlist_item.dart';
import '../models/artist_details.dart';
import '../models/artist_item.dart';
import 'artwork_cache_service.dart';
import 'home_cache_service.dart';
import 'lyrics_service.dart';
import 'song_metrics_cache_service.dart';

/// Resolved audio stream data containing direct stream URL, matching User-Agent headers,
/// bitrate, and media format specifications.
class AudioStreamInfo {
  final String url;
  final Map<String, String> headers;
  final int bitrate;
  final String mimeType;
  final int? contentLength;
  final int? durationMs;

  const AudioStreamInfo({
    required this.url,
    required this.headers,
    required this.bitrate,
    required this.mimeType,
    this.contentLength,
    this.durationMs,
  });

  int? get durationSeconds =>
      durationMs != null && durationMs! > 0 ? durationMs! ~/ 1000 : null;
}

/// Resolved video stream data for crisp moving artwork / background video playback.
class VideoStreamInfo {
  final String url;
  final Map<String, String> headers;
  final int width;
  final int height;
  final String qualityLabel;

  const VideoStreamInfo({
    required this.url,
    required this.headers,
    required this.width,
    required this.height,
    required this.qualityLabel,
  });
}

/// Resolved animated artwork data (HD video stream or animated WebP loop).
class AnimatedArtworkData {
  final String url;
  final Map<String, String> headers;
  final bool isVideo;
  final int width;
  final int height;

  const AnimatedArtworkData({
    required this.url,
    this.headers = const {},
    this.isVideo = false,
    this.width = 1280,
    this.height = 720,
  });
}

/// Client configuration for InnerTube player requests, inspired by BitChord's PlayerClient.
class _InnerTubeClientConfig {
  final String clientName;
  final String clientVersion;
  final String userAgent;

  const _InnerTubeClientConfig({
    required this.clientName,
    required this.clientVersion,
    required this.userAgent,
  });
}

/// MusicService uses `dart_ytmusic_api` to:
/// 1. Search tracks and query metadata (`searchSongs`)
/// 2. Gather Home feed information: Trending tracks, Genres, Moods, and Quick picks (`getHomeData`)
/// 3. Extract and resolve robust, unthrottled streaming URLs using multi-client
///    InnerTube rotation (VISIONOS -> ANDROID_VR -> ANDROID -> IOS) with BitChord-style
///    stream validation and header dressing.
class MusicService {
  final YTMusic _ytMusic = YTMusic();
  bool _isInitialized = false;

  // Connected Google / YouTube Music account
  UserAccount? _currentAccount;

  UserAccount? get currentAccount => _currentAccount;

  // In-memory cache for dynamically resolved album cover artwork
  final Map<String, String> _albumArtworkCache = {};

  // In-memory cache for dynamically resolved animated artwork / GIF videos
  final Map<String, String?> _animatedArtworkCache = {};

  // In-memory cache for resolved animated artwork data (URL + headers + isVideo)
  final Map<String, AnimatedArtworkData?> _animatedArtworkDataCache = {};

  // In-memory cache for dynamically resolved HD video streams (720p/1080p MP4)
  final Map<String, VideoStreamInfo?> _videoStreamCache = {};

  // Apple Music-style lyrics provider service (binimum/am-lyrics pipeline)
  final LyricsService _lyricsService = LyricsService();

  /// Sets or updates the connected Google account with YouTube Music authorization.
  void setAuthAccount(UserAccount? account) {
    _currentAccount = account;
    _cachedHomeData = null; // Clear cached feed so next fetch reflects account state

    final cookies = account?.cookies;
    if (cookies != null && cookies.isNotEmpty) {
      for (final raw in cookies.split(';')) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) continue;
        final eqIdx = trimmed.indexOf('=');
        if (eqIdx > 0) {
          final name = trimmed.substring(0, eqIdx).trim();
          final val = trimmed.substring(eqIdx + 1).trim();
          try {
            final cookie = Cookie(name, val);
            _ytMusic.cookieJar.saveFromResponse(
              Uri.parse('https://music.youtube.com/'),
              [cookie],
            );
            _ytMusic.cookieJar.saveFromResponse(
              Uri.parse('https://www.youtube.com/'),
              [cookie],
            );
          } catch (e) {
            debugPrint('Error saving cookie $name: $e');
          }
        }
      }
    }
  }

  /// Extracts SAPISID, __Secure-3PAPISID, or __Secure-1PAPISID from cookie header
  static String? extractSapisid(String cookies) {
    final jar = <String, String>{};
    for (final part in cookies.split(';')) {
      final trimmed = part.trim();
      final eq = trimmed.indexOf('=');
      if (eq > 0) {
        final name = trimmed.substring(0, eq).trim();
        final val = trimmed.substring(eq + 1).trim();
        if (name.isNotEmpty && val.isNotEmpty) {
          jar[name] = val;
        }
      }
    }
    return jar['SAPISID'] ?? jar['__Secure-3PAPISID'] ?? jar['__Secure-1PAPISID'];
  }

  /// Computes SAPISIDHASH authorization header from a SAPISID token
  static String computeSapisidHash(String sapisid, {String origin = 'https://music.youtube.com'}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final payload = '$timestamp $sapisid $origin';
    final digest = sha1.convert(utf8.encode(payload)).toString();
    return 'SAPISIDHASH ${timestamp}_$digest';
  }

  /// Computes SAPISIDHASH authorization header if authenticated with a Google account
  String? getSapisidHash({String origin = 'https://music.youtube.com'}) {
    final sapisid = _currentAccount?.sapisid;
    if (sapisid == null || sapisid.isEmpty) return null;
    return computeSapisidHash(sapisid, origin: origin);
  }

  /// Recursively collects all objects named [targetKey] anywhere inside a JSON structure
  static List<Map<String, dynamic>> _collectRenderers(dynamic root, String targetKey) {
    final results = <Map<String, dynamic>>[];
    void search(dynamic node) {
      if (node is List) {
        for (final item in node) {
          search(item);
        }
      } else if (node is Map<String, dynamic>) {
        for (final entry in node.entries) {
          if (entry.key == targetKey && entry.value is Map<String, dynamic>) {
            results.add(entry.value as Map<String, dynamic>);
          }
          search(entry.value);
        }
      } else if (node is Map) {
        for (final entry in node.entries) {
          if (entry.key == targetKey && entry.value is Map) {
            results.add(Map<String, dynamic>.from(entry.value as Map));
          }
          search(entry.value);
        }
      }
    }
    search(root);
    return results;
  }

  /// Extracts textual representation from YouTube runs, simpleText, or raw string
  static String _extractNodeText(dynamic node) {
    if (node == null) return '';
    if (node is String) return node;
    if (node is Map) {
      if (node['simpleText'] is String) return node['simpleText'] as String;
      if (node['runs'] is List) {
        final buffer = StringBuffer();
        for (final r in node['runs'] as List) {
          if (r is Map && r['text'] != null) {
            buffer.write(r['text']);
          } else if (r is String) {
            buffer.write(r);
          }
        }
        return buffer.toString();
      }
    }
    return '';
  }

  /// Extracts the highest resolution photo from an account renderer
  static String? _extractNodePhoto(Map<String, dynamic> item) {
    final photoObj = item['accountPhoto'] ?? item['thumbnail'];
    if (photoObj is Map) {
      final thumbnails = photoObj['thumbnails'];
      if (thumbnails is List && thumbnails.isNotEmpty) {
        final last = thumbnails.last;
        if (last is Map && last['url'] != null) {
          String url = last['url'].toString();
          if (url.startsWith('//')) url = 'https:$url';
          // Upgrade thumbnail to higher resolution (256x256)
          if (url.contains('=s88') || url.contains('=s64') || url.contains('=s32')) {
            url = url.replaceAll(RegExp(r'=s\d+'), '=s256');
          }
          return url;
        }
      }
    }
    return null;
  }

  /// Parses YouTube Music account menu response to extract verified Google profile info
  static ({String displayName, String email, String? avatarUrl})? parseAccountMenu(dynamic data) {
    if (data == null) return null;

    final activeHeaders = _collectRenderers(data, 'activeAccountHeaderRenderer');
    if (activeHeaders.isNotEmpty) {
      final header = activeHeaders.first;
      final name = _extractNodeText(header['accountName']).trim();
      var email = _extractNodeText(header['email']).trim();
      if (email.isEmpty) {
        email = _extractNodeText(header['channelHandle']).trim();
      }
      final avatar = _extractNodePhoto(header);

      if (name.isNotEmpty || email.isNotEmpty) {
        return (
          displayName: name.isNotEmpty ? name : 'YouTube Music User',
          email: email,
          avatarUrl: avatar,
        );
      }
    }

    final accountItems = _collectRenderers(data, 'accountItem');
    if (accountItems.isNotEmpty) {
      final item = accountItems.first;
      final name = _extractNodeText(item['accountName']).trim();
      var email = _extractNodeText(item['email']).trim();
      if (email.isEmpty) {
        email = _extractNodeText(item['channelHandle']).trim();
      }
      if (email.isEmpty) {
        email = _extractNodeText(item['accountByline']).trim();
      }
      final avatar = _extractNodePhoto(item);

      if (name.isNotEmpty || email.isNotEmpty) {
        return (
          displayName: name.isNotEmpty ? name : 'YouTube Music User',
          email: email,
          avatarUrl: avatar,
        );
      }
    }

    return null;
  }

  /// Connects to YouTube Music InnerTube account_menu endpoint using authentic
  /// session cookies and SAPISIDHASH to retrieve the user's verified profile.
  Future<({String displayName, String email, String? avatarUrl})?> fetchAccountProfile({
    required String cookies,
    String? dataSyncId,
    String? pageId,
    String? authUser,
    String? visitorData,
    String? clientVersion,
  }) async {
    final sapisid = extractSapisid(cookies);
    if (sapisid == null || sapisid.isEmpty) {
      debugPrint('fetchAccountProfile: No SAPISID found in cookies');
      return null;
    }

    final sapisidHash = computeSapisidHash(sapisid);
    final version = clientVersion ?? '1.20240101.01.00';
    final uri = Uri.parse('https://music.youtube.com/youtubei/v1/account/account_menu?prettyPrint=false&hl=en');

    final userContext = <String, dynamic>{
      'lockedSafetyMode': false,
    };
    if (dataSyncId != null && dataSyncId.isNotEmpty) {
      userContext['onBehalfOfUser'] = dataSyncId;
    }

    final body = jsonEncode({
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': version,
          'hl': 'en',
          'gl': 'US',
          if (visitorData != null && visitorData.isNotEmpty) 'visitorData': visitorData,
        },
        'user': userContext,
        'request': {
          'useSsl': true,
        },
      },
    });

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
      );
      request.headers.set('Accept-Language', 'en-US,en;q=0.9');
      request.headers.set('X-Origin', 'https://music.youtube.com');
      request.headers.set('Origin', 'https://music.youtube.com');
      request.headers.set('Referer', 'https://music.youtube.com/');
      request.headers.set('X-YouTube-Client-Name', '67');
      request.headers.set('X-YouTube-Client-Version', version);
      request.headers.set('Cookie', cookies);
      request.headers.set('Authorization', sapisidHash);
      request.headers.set('X-Goog-AuthUser', authUser ?? '0');
      if (pageId != null && pageId.isNotEmpty) {
        request.headers.set('X-Goog-PageId', pageId);
      }
      if (visitorData != null && visitorData.isNotEmpty) {
        request.headers.set('X-Goog-Visitor-Id', visitorData);
      }

      request.write(body);

      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        debugPrint('fetchAccountProfile: InnerTube account_menu returned status ${response.statusCode}');
        await response.drain();
        return null;
      }

      final responseBody = await utf8.decoder.bind(response).join();
      final data = jsonDecode(responseBody);
      return parseAccountMenu(data);
    } catch (e) {
      debugPrint('fetchAccountProfile error: $e');
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  // Cached streams to prevent duplicate Innertube player requests (5 min TTL)
  final Map<String, ({AudioStreamInfo info, DateTime timestamp})> _streamCache = {};

  // Cached artist details to prevent repeated parsing and provide instant loads (15 min TTL)
  final Map<String, ({ArtistDetails details, DateTime timestamp})> _artistDetailsCache = {};

  // Cached home feed data
  HomeData? _cachedHomeData;

  // Client tiers ordered by reliability and lack of PoToken/throttling barriers
  static const List<_InnerTubeClientConfig> _clientTiers = [
    // Tier 1: VISIONOS - Does not require BotGuard/PoToken, provides full AAC streams,
    // and serves unthrottled media without 403 dropoffs.
    _InnerTubeClientConfig(
      clientName: 'VISIONOS',
      clientVersion: '1.02',
      userAgent: 'com.google.visionos.youtube/1.02 (Apple Vision; visionOS 1.0)',
    ),
    // Tier 2: ANDROID_VR - Oculus/Meta Quest client, direct streamingData
    _InnerTubeClientConfig(
      clientName: 'ANDROID_VR',
      clientVersion: '1.65.10',
      userAgent: 'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; Build/SQ3A.220605.009.A1) gzip',
    ),
    // Tier 3: ANDROID - Native YouTube Android client
    _InnerTubeClientConfig(
      clientName: 'ANDROID',
      clientVersion: '20.10.38',
      userAgent: 'com.google.android.youtube/20.10.38 (Linux; U; Android 14; en_US; Pixel 7 Pro) gzip',
    ),
    // Tier 4: IOS - Native iOS client
    _InnerTubeClientConfig(
      clientName: 'IOS',
      clientVersion: '20.10.4',
      userAgent: 'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
    ),
  ];

  static const List<MusicCategory> _defaultMoods = [
    MusicCategory(title: 'Chill', colorValue: 0xFF4A90E2),
    MusicCategory(title: 'Energize', colorValue: 0xFFFF9500),
    MusicCategory(title: 'Feel Good', colorValue: 0xFF34C759),
    MusicCategory(title: 'Focus', colorValue: 0xFF5856D6),
    MusicCategory(title: 'Workout', colorValue: 0xFFFF2D55),
    MusicCategory(title: 'Party', colorValue: 0xFFAF52DE),
    MusicCategory(title: 'Romance', colorValue: 0xFFFF3B30),
    MusicCategory(title: 'Sleep', colorValue: 0xFF1C1C1E),
  ];

  static const List<MusicCategory> _defaultGenres = [
    MusicCategory(title: 'Pop', colorValue: 0xFFFF2D55),
    MusicCategory(title: 'Hip-Hop', colorValue: 0xFFFF9500),
    MusicCategory(title: 'Rock', colorValue: 0xFFE02424),
    MusicCategory(title: 'Bollywood', colorValue: 0xFFFF5722),
    MusicCategory(title: 'Electronic', colorValue: 0xFF00C7BE),
    MusicCategory(title: 'R&B / Soul', colorValue: 0xFFAF52DE),
    MusicCategory(title: 'Indie & Alt', colorValue: 0xFF34C759),
    MusicCategory(title: 'Acoustic', colorValue: 0xFF8E8E93),
  ];

  /// Initializes the YouTube Music API client.
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _ytMusic.initialize();
    _isInitialized = true;
  }

  /// Gathers all information for the home screen matching Apple Music layout:
  /// - Top picks hero cards
  /// - Recents / Listen again (4-row column batches)
  /// - Find Your Mood
  /// - Albums & singles
  /// - Music videos (16:9 widescreen)
  /// - Quick picks (4-row column batches)
  /// - Your daily discover
  /// - Trending songs for you
  Future<HomeData> getHomeData({bool refresh = false}) async {
    if (!refresh) {
      if (_cachedHomeData != null) {
        return _cachedHomeData!;
      }
      final diskCached = await HomeCacheService.instance.loadHomeData();
      if (diskCached != null && !diskCached.isEmpty) {
        _cachedHomeData = diskCached;
        SongMetricsCacheService.instance.precacheTracks(
          [...diskCached.recents.take(3), ...diskCached.quickPicks.take(3)],
          this,
        );
        return diskCached;
      }
    }

    if (!_isInitialized) {
      await initialize();
    }

    // When signed in with a Google YouTube Music account and personalization is enabled,
    // fetch recommendations and mixes specific to that user's account.
    if (_currentAccount != null && _currentAccount!.isPersonalizedEnabled) {
      final personalData = await _fetchPersonalizedHomeData();
      if (personalData != null) {
        _cachedHomeData = personalData;
        await HomeCacheService.instance.saveHomeData(personalData);
        ArtworkCacheService.instance.prefetchArtworks(personalData.recents);
        SongMetricsCacheService.instance.precacheTracks(
          [...personalData.recents.take(3), ...personalData.quickPicks.take(3)],
          this,
        );
        return personalData;
      }
    }

    // Curated & trending fallback queries
    final results = await Future.wait([
      _fetchHeroCards(),
      _fetchRecents(),
      _fetchQuickPicks(),
      _fetchMoodsAndGenres(),
      _fetchAlbumsAndSingles(),
      _fetchMusicVideos(),
      _fetchDailyDiscover(),
      _fetchTrendingTracks(),
    ]);

    final heroCards = results[0] as List<HeroCardItem>;
    final recents = results[1] as List<SongItem>;
    final quickPicks = results[2] as List<SongItem>;
    final categories = results[3] as ({List<MusicCategory> moods, List<MusicCategory> genres});
    final albumsAndSingles = results[4] as List<AlbumItem>;
    final musicVideos = results[5] as List<VideoItem>;
    final dailyDiscover = results[6] as List<SongItem>;
    final trendingSongs = results[7] as List<SongItem>;

    final homeData = HomeData(
      heroCards: heroCards,
      recents: recents,
      quickPicks: quickPicks,
      moods: categories.moods,
      genres: categories.genres,
      albumsAndSingles: albumsAndSingles,
      musicVideos: musicVideos,
      dailyDiscover: dailyDiscover,
      trendingSongs: trendingSongs,
    );

    _cachedHomeData = homeData;
    await HomeCacheService.instance.saveHomeData(homeData);
    ArtworkCacheService.instance.prefetchArtworks(homeData.recents);
    SongMetricsCacheService.instance.precacheTracks(
      [...homeData.recents.take(3), ...homeData.quickPicks.take(3)],
      this,
    );
    return homeData;
  }

  /// Fetches personalized home recommendations from YouTube Music using account authorization.
  Future<HomeData?> _fetchPersonalizedHomeData() async {
    try {
      final sections = await _ytMusic.getHomeSections();
      if (sections.isEmpty) return null;

      final personalizedRecents = <SongItem>[];
      final personalizedQuickPicks = <SongItem>[];
      final personalizedAlbums = <AlbumItem>[];
      final personalizedVideos = <VideoItem>[];
      final personalizedHeroCards = <HeroCardItem>[];

      for (final section in sections) {
        final titleLower = section.title.toLowerCase();

        // 1. Listen again / User's listening history
        if (titleLower.contains('listen again') ||
            titleLower.contains('recent') ||
            titleLower.contains('play it again') ||
            titleLower.contains('history')) {
          personalizedRecents.addAll(_extractSongsFromHomeSection(section));
        }
        // 2. Quick picks / Tailored algorithmic recommendations
        else if (titleLower.contains('quick pick') ||
            titleLower.contains('recommended') ||
            titleLower.contains('start radio') ||
            titleLower.contains('for you') ||
            titleLower.contains('favorites')) {
          personalizedQuickPicks.addAll(_extractSongsFromHomeSection(section));
        }
        // 3. Mixed for you / Personal Supermixes
        else if (titleLower.contains('mixed for you') ||
            titleLower.contains('supermix') ||
            titleLower.contains('mixes') ||
            titleLower.contains('your mix')) {
          final songs = _extractSongsFromHomeSection(section);
          if (songs.isNotEmpty) {
            personalizedHeroCards.add(
              HeroCardItem(
                id: 'hero_personal_${personalizedHeroCards.length}',
                title: section.title.isNotEmpty ? section.title : 'My Supermix',
                subtitle: 'Personalized for ${_currentAccount?.displayName ?? "You"}',
                caption: 'YouTube Music • Personalized Mix',
                imageUrl: songs.first.thumbnailUrl,
                primaryColor: 0xFFFA243C,
                playTrack: songs.first,
              ),
            );
          }
        }
        // 4. Albums & singles
        else if (titleLower.contains('album') ||
            titleLower.contains('single') ||
            titleLower.contains('new release')) {
          personalizedAlbums.addAll(_extractAlbumsFromHomeSection(section));
        }
        // 5. Music videos
        else if (titleLower.contains('video')) {
          personalizedVideos.addAll(_extractVideosFromHomeSection(section));
        }
      }

      // If personalized content was resolved, build personalized HomeData
      if (personalizedRecents.isNotEmpty || personalizedQuickPicks.isNotEmpty) {
        final defaultCategories = await _fetchMoodsAndGenres();
        final fallbackHero = await _fetchHeroCards();
        final fallbackAlbums = personalizedAlbums.isNotEmpty
            ? personalizedAlbums
            : await _fetchAlbumsAndSingles();
        final fallbackVideos = personalizedVideos.isNotEmpty
            ? personalizedVideos
            : await _fetchMusicVideos();

        return HomeData(
          heroCards: personalizedHeroCards.isNotEmpty
              ? [
                  ...personalizedHeroCards,
                  ...fallbackHero.take(
                    (3 - personalizedHeroCards.length).clamp(0, 2),
                  ),
                ]
              : fallbackHero,
          recents: personalizedRecents.isNotEmpty
              ? personalizedRecents
              : await _fetchRecents(),
          quickPicks: personalizedQuickPicks.isNotEmpty
              ? personalizedQuickPicks
              : await _fetchQuickPicks(),
          moods: defaultCategories.moods,
          genres: defaultCategories.genres,
          albumsAndSingles: fallbackAlbums,
          musicVideos: fallbackVideos,
          dailyDiscover: await _fetchDailyDiscover(),
          trendingSongs: await _fetchTrendingTracks(),
        );
      }
    } catch (e) {
      debugPrint('Personalized home sections fetch error: $e, falling back to curated feed');
    }
    return null;
  }

  List<SongItem> _extractSongsFromHomeSection(HomeSection section) {
    final list = <SongItem>[];
    for (final item in section.contents) {
      if (item is SongDetailed && item.videoId.isNotEmpty) {
        String? thumb;
        if (item.thumbnails.isNotEmpty) {
          thumb = SongItem.upgradeThumbnail(item.thumbnails.last.url);
        }
        list.add(
          SongItem(
            id: item.videoId,
            title: item.name.isNotEmpty ? item.name : 'Untitled',
            artist: item.artist.name.isNotEmpty
                ? item.artist.name
                : 'Unknown Artist',
            thumbnailUrl: thumb,
            durationSeconds: item.duration,
            album: item.album?.name,
          ),
        );
      }
    }
    return list;
  }

  List<AlbumItem> _extractAlbumsFromHomeSection(HomeSection section) {
    final list = <AlbumItem>[];
    for (final item in section.contents) {
      if (item is AlbumDetailed && item.albumId.isNotEmpty) {
        String? thumb;
        if (item.thumbnails.isNotEmpty) {
          thumb = SongItem.upgradeThumbnail(item.thumbnails.last.url);
        }
        list.add(
          AlbumItem(
            id: item.albumId,
            title: item.name.isNotEmpty ? item.name : 'Untitled Album',
            artist: item.artist.name.isNotEmpty
                ? item.artist.name
                : 'Unknown Artist',
            thumbnailUrl: thumb,
            type: item.type.isNotEmpty ? item.type : 'Album',
            year: item.year,
          ),
        );
      }
    }
    return list;
  }

  List<VideoItem> _extractVideosFromHomeSection(HomeSection section) {
    final list = <VideoItem>[];
    for (final item in section.contents) {
      if (item is VideoDetailed && item.videoId.isNotEmpty) {
        String? thumb;
        if (item.thumbnails.isNotEmpty) {
          thumb = SongItem.upgradeThumbnail(item.thumbnails.last.url);
        }
        list.add(
          VideoItem(
            id: item.videoId,
            title: item.name.isNotEmpty ? item.name : 'Untitled Video',
            artist: item.artist.name.isNotEmpty
                ? item.artist.name
                : 'Unknown Artist',
            thumbnailUrl: thumb,
            durationSeconds: item.duration,
          ),
        );
      }
    }
    return list;
  }

  Future<List<HeroCardItem>> _fetchHeroCards() async {
    try {
      final aujlaSongs = await searchSongs('Karan Aujla');
      final shubhSongs = await searchSongs('Shubh');
      final weekndSongs = await searchSongs('The Weeknd');

      final aujlaTrack = aujlaSongs.isNotEmpty ? aujlaSongs.first : null;
      final shubhTrack = shubhSongs.isNotEmpty ? shubhSongs.first : null;
      final weekndTrack = weekndSongs.isNotEmpty ? weekndSongs.first : null;

      return [
        HeroCardItem(
          id: 'hero_aujla',
          title: 'AUJLA SZN 1',
          subtitle: 'New from Karan Aujla',
          caption: 'EP • 2026',
          imageUrl: aujlaTrack?.thumbnailUrl ??
              'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=600&auto=format&fit=crop&q=80',
          primaryColor: 0xFF2A2825,
          playTrack: aujlaTrack,
        ),
        HeroCardItem(
          id: 'hero_shubh',
          title: 'Shubh & Similar',
          subtitle: 'Featuring Shubh',
          caption: 'Top Punjabi Wave',
          imageUrl: shubhTrack?.thumbnailUrl,
          primaryColor: 0xFF1D64F2,
          playTrack: shubhTrack,
        ),
        HeroCardItem(
          id: 'hero_weeknd',
          title: 'After Hours & Dawn',
          subtitle: 'Featuring The Weeknd',
          caption: 'Spatial Audio • Hit Mix',
          imageUrl: weekndTrack?.thumbnailUrl,
          primaryColor: 0xFF7928CA,
          playTrack: weekndTrack,
        ),
      ];
    } catch (_) {
      return const [
        HeroCardItem(
          id: 'hero_default_1',
          title: 'AUJLA SZN 1',
          subtitle: 'New from Karan Aujla',
          caption: 'EP • 2026',
          primaryColor: 0xFF2A2825,
        ),
        HeroCardItem(
          id: 'hero_default_2',
          title: 'Shubh & Similar',
          subtitle: 'Featuring Shubh',
          caption: 'Top Punjabi Wave',
          primaryColor: 0xFF1D64F2,
        ),
      ];
    }
  }

  Future<List<SongItem>> _fetchRecents() async {
    try {
      final songs = await searchSongs('Ken Carson SoFaygo Gunna');
      if (songs.isNotEmpty) return songs;
    } catch (_) {}
    return searchSongs('Hip Hop');
  }

  Future<List<AlbumItem>> _fetchAlbumsAndSingles() async {
    try {
      final albums = await searchAlbums('Hits 2026');
      if (albums.isNotEmpty) return albums;
    } catch (_) {}
    return searchAlbums('Trending Albums');
  }

  Future<List<VideoItem>> _fetchMusicVideos() async {
    try {
      final videos = await searchVideos('Official Music Video 2026');
      if (videos.isNotEmpty) return videos;
    } catch (_) {}
    return searchVideos('Official Music Video');
  }

  Future<List<SongItem>> _fetchDailyDiscover() async {
    try {
      final songs = await searchSongs('Daily Discover');
      if (songs.isNotEmpty) return songs;
    } catch (_) {}
    return searchSongs('Top Discover Weekly');
  }

  Future<List<SongItem>> _fetchTrendingTracks() async {
    try {
      final songs = await searchSongs('Trending top hits');
      if (songs.isNotEmpty) return songs;
    } catch (_) {}
    return searchSongs('Top hits');
  }

  Future<List<SongItem>> _fetchQuickPicks() async {
    try {
      final songs = await searchSongs('Billboard Hot 100');
      if (songs.isNotEmpty) return songs;
    } catch (_) {}
    return [];
  }

  Future<List<AlbumItem>> searchAlbums(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    if (!_isInitialized) {
      await initialize();
    }

    try {
      final results = await _ytMusic.searchAlbums(trimmedQuery);
      return results
          .where((a) => a.albumId.isNotEmpty)
          .map((a) {
            String? thumb;
            if (a.thumbnails.isNotEmpty) {
              final raw = a.thumbnails.last.url;
              thumb = SongItem.upgradeThumbnail(raw.startsWith('//') ? 'https:$raw' : raw);
            }
            return AlbumItem(
              id: a.albumId,
              title: a.name.isNotEmpty ? a.name : 'Untitled Album',
              artist: a.artist.name.isNotEmpty ? a.artist.name : 'Unknown Artist',
              thumbnailUrl: thumb,
              type: a.type.isNotEmpty ? a.type : 'Album',
              year: a.year,
            );
          })
          .toList();
    } catch (e) {
      debugPrint('searchAlbums error: $e');
      return [];
    }
  }

  /// Resolves the real cover artwork URL for a specific album by ID, title, or artist.
  /// If the album has no image or if loading failed, this grabs the real image from YouTube Music.
  Future<String?> getAlbumArtwork(String albumId, {String? title, String? artist}) async {
    final cleanId = albumId.trim();
    if (cleanId.isNotEmpty && _albumArtworkCache.containsKey(cleanId)) {
      return _albumArtworkCache[cleanId];
    }

    if (!_isInitialized) {
      await initialize();
    }

    // 1. Try querying the album directly
    if (cleanId.isNotEmpty) {
      try {
        final albumFull = await _ytMusic.getAlbum(cleanId);
        if (albumFull.thumbnails.isNotEmpty) {
          final raw = albumFull.thumbnails.last.url;
          final url = SongItem.upgradeThumbnail(raw.startsWith('//') ? 'https:$raw' : raw);
          if (url != null && url.isNotEmpty) {
            _albumArtworkCache[cleanId] = url;
            return url;
          }
        }
        if (albumFull.songs.isNotEmpty) {
          for (final song in albumFull.songs) {
            if (song.thumbnails.isNotEmpty) {
              final raw = song.thumbnails.last.url;
              final url = SongItem.upgradeThumbnail(raw.startsWith('//') ? 'https:$raw' : raw);
              if (url != null && url.isNotEmpty) {
                _albumArtworkCache[cleanId] = url;
                return url;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('getAlbumArtwork getAlbum error for $cleanId: $e');
      }
    }

    // 2. Try searching YouTube Music for this specific album
    final query = '${title ?? ''} ${artist ?? ''}'.trim();
    if (query.isNotEmpty) {
      try {
        final searchResults = await _ytMusic.searchAlbums(query);
        if (searchResults.isNotEmpty) {
          final first = searchResults.first;
          if (first.thumbnails.isNotEmpty) {
            final raw = first.thumbnails.last.url;
            final url = SongItem.upgradeThumbnail(raw.startsWith('//') ? 'https:$raw' : raw);
            if (url != null && url.isNotEmpty) {
              if (cleanId.isNotEmpty) _albumArtworkCache[cleanId] = url;
              return url;
            }
          }
        }
      } catch (e) {
        debugPrint('getAlbumArtwork searchAlbums error for $query: $e');
      }

      // 3. Fallback search songs for the track artwork
      try {
        final songs = await _ytMusic.searchSongs(query);
        if (songs.isNotEmpty && songs.first.thumbnails.isNotEmpty) {
          final raw = songs.first.thumbnails.last.url;
          final url = SongItem.upgradeThumbnail(raw.startsWith('//') ? 'https:$raw' : raw);
          if (url != null && url.isNotEmpty) {
            if (cleanId.isNotEmpty) _albumArtworkCache[cleanId] = url;
            return url;
          }
        }
      } catch (_) {}
    }

    return null;
  }

  /// Resolves animated looping artwork or crisp HD video stream for the song or its album from YouTube.
  /// 1. Searches YouTube for the official music video / moving visualizer to retrieve its HD stream (1080p/720p).
  /// 2. If video is found, extracts its hardware-accelerated video stream and headers.
  /// 3. If HD video unavailable, checks for moving WebP thumbnail.
  /// 4. Falls back to album search or direct track ID video.
  Future<AnimatedArtworkData?> getAnimatedArtworkData(SongItem song) async {
    // If song already has an animated artwork URL specified, return it
    if (song.animatedArtworkUrl != null && song.animatedArtworkUrl!.isNotEmpty) {
      final isVideo = isVideoMediaUrl(song.animatedArtworkUrl);
      return AnimatedArtworkData(
        url: song.animatedArtworkUrl!,
        isVideo: isVideo,
      );
    }

    final cacheKey = song.id.isNotEmpty ? song.id : '${song.title}_${song.artist}';
    if (_animatedArtworkDataCache.containsKey(cacheKey)) {
      return _animatedArtworkDataCache[cacheKey];
    }

    try {
      // 1. Search YouTube for official music video / moving visualizer first
      final searchResult = await _searchOfficialVideoOrThumbnail('${song.title} ${song.artist}');
      if (searchResult != null) {
        if (searchResult.videoId != null) {
          final officialVideo = await resolveVideoStream(searchResult.videoId!);
          if (officialVideo != null && officialVideo.height >= 480) {
            final data = AnimatedArtworkData(
              url: officialVideo.url,
              headers: officialVideo.headers,
              isVideo: true,
              width: officialVideo.width,
              height: officialVideo.height,
            );
            _animatedArtworkDataCache[cacheKey] = data;
            _animatedArtworkCache[cacheKey] = data.url;
            return data;
          }
        }
        if (searchResult.thumbnailUrl != null) {
          final data = AnimatedArtworkData(
            url: searchResult.thumbnailUrl!,
            isVideo: false,
          );
          _animatedArtworkDataCache[cacheKey] = data;
          _animatedArtworkCache[cacheKey] = data.url;
          return data;
        }
      }

      // 2. Fallback to album search if song belongs to an album
      if (song.album != null && song.album!.isNotEmpty && song.album != song.title) {
        final albumResult = await _searchOfficialVideoOrThumbnail('${song.album} ${song.artist}');
        if (albumResult != null) {
          if (albumResult.videoId != null) {
            final officialVideo = await resolveVideoStream(albumResult.videoId!);
            if (officialVideo != null && officialVideo.height >= 480) {
              final data = AnimatedArtworkData(
                url: officialVideo.url,
                headers: officialVideo.headers,
                isVideo: true,
                width: officialVideo.width,
                height: officialVideo.height,
              );
              _animatedArtworkDataCache[cacheKey] = data;
              _animatedArtworkCache[cacheKey] = data.url;
              return data;
            }
          }
          if (albumResult.thumbnailUrl != null) {
            final data = AnimatedArtworkData(
              url: albumResult.thumbnailUrl!,
              isVideo: false,
            );
            _animatedArtworkDataCache[cacheKey] = data;
            _animatedArtworkCache[cacheKey] = data.url;
            return data;
          }
        }
      }

      // 3. Direct video resolution from track ID as final fallback
      if (song.id.isNotEmpty) {
        final directVideo = await resolveVideoStream(song.id);
        if (directVideo != null && directVideo.height >= 480) {
          final data = AnimatedArtworkData(
            url: directVideo.url,
            headers: directVideo.headers,
            isVideo: true,
            width: directVideo.width,
            height: directVideo.height,
          );
          _animatedArtworkDataCache[cacheKey] = data;
          _animatedArtworkCache[cacheKey] = data.url;
          return data;
        }
      }

      _animatedArtworkDataCache[cacheKey] = null;
      _animatedArtworkCache[cacheKey] = null;
      return null;
    } catch (e) {
      debugPrint('getAnimatedArtworkData error for ${song.title}: $e');
      _animatedArtworkDataCache[cacheKey] = null;
      _animatedArtworkCache[cacheKey] = null;
      return null;
    }
  }

  /// Determines whether the given URL represents a playable video stream.
  static bool isVideoMediaUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final lower = url.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('googlevideo.com') ||
        lower.contains('/videoplayback') ||
        lower.contains('.m3u8');
  }

  /// Resolves an animated looping artwork or crisp HD video stream for the song or its album from YouTube.
  Future<String?> getAnimatedArtwork(SongItem song) async {
    final data = await getAnimatedArtworkData(song);
    return data?.url;
  }

  /// Internal helper to perform a lightweight search for the official video ID and moving thumbnail.
  Future<({String? videoId, String? thumbnailUrl})?> _searchOfficialVideoOrThumbnail(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return null;

    HttpClient? client;
    try {
      final uri = Uri.parse('https://www.youtube.com/youtubei/v1/search?prettyPrint=false');
      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB',
            'clientVersion': '2.20231018.01.00',
            'hl': 'en',
            'gl': 'US',
          }
        },
        'query': cleanQuery,
      });

      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      request.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      );
      request.write(body);

      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) {
        await response.drain();
        return null;
      }

      final responseBody = await utf8.decoder.bind(response).join();
      final data = jsonDecode(responseBody);

      String? matchedVideoId;
      String? matchedThumbnailUrl;

      void walk(dynamic node) {
        if (matchedVideoId != null && matchedThumbnailUrl != null) return;
        if (node is Map) {
          if (node.containsKey('videoRenderer')) {
            final vr = node['videoRenderer'];
            if (vr is Map) {
              matchedVideoId ??= vr['videoId'] as String?;
              final moving = vr['richThumbnail']?['movingThumbnailRenderer'] ?? vr['movingThumbnailRenderer'];
              if (moving is Map && matchedThumbnailUrl == null) {
                final thumbs = moving['movingThumbnailDetails']?['thumbnails'] as List?;
                if (thumbs != null && thumbs.isNotEmpty) {
                  final raw = thumbs.first['url'] as String?;
                  if (raw != null && raw.isNotEmpty) {
                    matchedThumbnailUrl = raw.startsWith('//') ? 'https:$raw' : raw;
                  }
                }
              }
              if (matchedVideoId != null && matchedThumbnailUrl != null) return;
            }
          }
          for (final value in node.values) {
            walk(value);
            if (matchedVideoId != null && matchedThumbnailUrl != null) return;
          }
        } else if (node is List) {
          for (final item in node) {
            walk(item);
            if (matchedVideoId != null && matchedThumbnailUrl != null) return;
          }
        }
      }

      walk(data);
      if (matchedVideoId != null || matchedThumbnailUrl != null) {
        return (videoId: matchedVideoId, thumbnailUrl: matchedThumbnailUrl);
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// Fetches track listings for an album or single.
  /// First queries `_ytMusic.getAlbum(albumId)`. If no tracks are parsed or if it fails,
  /// gracefully falls back to searching songs with [queryFallback].
  Future<List<SongItem>> getAlbumSongs(String albumId, {String? queryFallback}) async {
    final cleanId = albumId.trim();

    if (!_isInitialized) {
      await initialize();
    }

    if (cleanId.isNotEmpty) {
      try {
        final albumFull = await _ytMusic.getAlbum(cleanId);
        if (albumFull.songs.isNotEmpty) {
          final albumThumb = albumFull.thumbnails.isNotEmpty ? albumFull.thumbnails.last.url : null;
          final albumArtist = albumFull.artist.name.isNotEmpty ? albumFull.artist.name : 'Unknown Artist';

          return albumFull.songs
              .where((s) => s.videoId.isNotEmpty)
              .map((s) {
                final artistName = s.artist.name.isNotEmpty ? s.artist.name : albumArtist;
                final rawThumb = s.thumbnails.isNotEmpty ? s.thumbnails.last.url : albumThumb;
                final thumb = SongItem.upgradeThumbnail(rawThumb);
                return SongItem(
                  id: s.videoId,
                  title: s.name.isNotEmpty ? s.name : 'Untitled',
                  artist: artistName,
                  thumbnailUrl: thumb,
                  durationSeconds: s.duration,
                  album: albumFull.name.isNotEmpty ? albumFull.name : null,
                );
              })
              .toList();
        }
      } catch (e) {
        debugPrint('getAlbum error: $e, falling back to queryFallback');
      }
    }

    if (queryFallback != null && queryFallback.trim().isNotEmpty) {
      return searchSongs(queryFallback);
    }

    return [];
  }

  /// Fetches complete album details including upgraded artwork, all track listings,
  /// and total calculated duration for the Album Screen.
  Future<AlbumDetails> getAlbumDetails(
    AlbumItem initialAlbum, {
    String? queryFallback,
  }) async {
    final tracks = await getAlbumSongs(
      initialAlbum.id,
      queryFallback:
          queryFallback ?? '${initialAlbum.title} ${initialAlbum.artist}',
    );

    String? artwork = initialAlbum.thumbnailUrl;
    if (artwork == null || artwork.isEmpty) {
      artwork = await getAlbumArtwork(
        initialAlbum.id,
        title: initialAlbum.title,
        artist: initialAlbum.artist,
      );
    }

    final totalDuration =
        tracks.fold<int>(0, (sum, t) => sum + (t.durationSeconds ?? 0));
    final updatedAlbum = initialAlbum.copyWith(
      thumbnailUrl: artwork,
      trackCount: tracks.length,
      durationMinutes: totalDuration > 0 ? (totalDuration ~/ 60) : null,
    );

    return AlbumDetails(
      album: updatedAlbum,
      tracks: tracks,
      totalDurationSeconds: totalDuration,
    );
  }

  /// Extracts clean playlist ID from URLs (e.g. music.youtube.com/playlist?list=... or youtube.com/playlist?list=...)
  /// or directly returns the raw input if it's already an ID.
  static String extractPlaylistId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.queryParameters.containsKey('list')) {
      return uri.queryParameters['list']!;
    }
    final match = RegExp(r'[?&]list=([^&#]+)').firstMatch(trimmed);
    if (match != null) {
      return match.group(1)!;
    }
    return trimmed;
  }

  /// Fetches playlist metadata (title, author, thumbnail, video count) from YouTube Music.
  Future<PlaylistItem?> fetchYouTubePlaylist(String urlOrId) async {
    final cleanId = extractPlaylistId(urlOrId);
    if (cleanId.isEmpty) return null;

    if (!_isInitialized) {
      await initialize();
    }

    try {
      final playlistFull = await _ytMusic.getPlaylist(cleanId);
      final thumb = playlistFull.thumbnails.isNotEmpty
          ? SongItem.upgradeThumbnail(playlistFull.thumbnails.last.url)
          : null;

      final authorName = playlistFull.artist.name.isNotEmpty
          ? playlistFull.artist.name
          : 'YouTube Music';

      return PlaylistItem(
        id: cleanId,
        title: playlistFull.name.isNotEmpty ? playlistFull.name : 'YouTube Playlist',
        author: authorName,
        thumbnailUrl: thumb,
        trackCount: playlistFull.videoCount > 0 ? playlistFull.videoCount : null,
        isCustom: true,
      );
    } catch (e) {
      debugPrint('fetchYouTubePlaylist error for $cleanId: $e');
      return PlaylistItem(
        id: cleanId,
        title: 'Playlist ($cleanId)',
        author: 'YouTube',
        isCustom: true,
      );
    }
  }

  /// Retrieves track listing for a YouTube playlist.
  Future<List<SongItem>> getPlaylistTracks(String playlistId, {String? queryFallback}) async {
    final cleanId = extractPlaylistId(playlistId);
    if (!_isInitialized) {
      await initialize();
    }

    if (cleanId.isNotEmpty) {
      try {
        final videos = await _ytMusic.getPlaylistVideos(cleanId);
        if (videos.isNotEmpty) {
          return videos
              .where((v) => v.videoId.isNotEmpty)
              .map((v) {
                final thumb = v.thumbnails.isNotEmpty
                    ? SongItem.upgradeThumbnail(v.thumbnails.last.url)
                    : null;
                final artistName =
                    v.artist.name.isNotEmpty ? v.artist.name : 'Unknown Artist';
                return SongItem(
                  id: v.videoId,
                  title: v.name.isNotEmpty ? v.name : 'Untitled',
                  artist: artistName,
                  thumbnailUrl: thumb,
                  durationSeconds: v.duration,
                );
              })
              .toList();
        }
      } catch (e) {
        debugPrint('getPlaylistTracks error for $cleanId: $e');
      }
    }

    if (queryFallback != null && queryFallback.trim().isNotEmpty) {
      return searchSongs(queryFallback);
    }

    return [];
  }

  /// Fetches Liked Music ('LM') from the logged-in YouTube Music user account.
  Future<List<SongItem>> getLikedSongs() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_currentAccount != null) {
      try {
        final videos = await _ytMusic.getPlaylistVideos('LM');
        if (videos.isNotEmpty) {
          return videos
              .where((v) => v.videoId.isNotEmpty)
              .map((v) {
                final thumb = v.thumbnails.isNotEmpty
                    ? SongItem.upgradeThumbnail(v.thumbnails.last.url)
                    : null;
                final artistName =
                    v.artist.name.isNotEmpty ? v.artist.name : 'Unknown Artist';
                return SongItem(
                  id: v.videoId,
                  title: v.name.isNotEmpty ? v.name : 'Untitled',
                  artist: artistName,
                  thumbnailUrl: thumb,
                  durationSeconds: v.duration,
                );
              })
              .toList();
        }
      } catch (e) {
        debugPrint('getLikedSongs LM error: $e, trying VLLM fallback');
        try {
          final videos = await _ytMusic.getPlaylistVideos('VLLM');
          if (videos.isNotEmpty) {
            return videos
                .where((v) => v.videoId.isNotEmpty)
                .map((v) {
                  final thumb = v.thumbnails.isNotEmpty
                      ? SongItem.upgradeThumbnail(v.thumbnails.last.url)
                      : null;
                  final artistName =
                      v.artist.name.isNotEmpty ? v.artist.name : 'Unknown Artist';
                  return SongItem(
                    id: v.videoId,
                    title: v.name.isNotEmpty ? v.name : 'Untitled',
                    artist: artistName,
                    thumbnailUrl: thumb,
                    durationSeconds: v.duration,
                  );
                })
                .toList();
          }
        } catch (_) {}
      }
    }

    return [];
  }

  /// Searches artists on YouTube Music.
  Future<List<ArtistItem>> searchArtists(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    if (!_isInitialized) {
      await initialize();
    }

    try {
      final results = await _ytMusic.searchArtists(trimmed);
      return results
          .where((a) => a.artistId.isNotEmpty)
          .map((a) {
            final thumb = a.thumbnails.isNotEmpty
                ? SongItem.upgradeThumbnail(a.thumbnails.last.url)
                : null;
            return ArtistItem(
              id: a.artistId,
              name: a.name.isNotEmpty ? a.name : 'Unknown Artist',
              thumbnailUrl: thumb,
              subscribers: 'Artist',
            );
          })
          .toList();
    } catch (e) {
      debugPrint('searchArtists error: $e');
      return [];
    }
  }

  /// Fetches top songs for an artist on YouTube Music.
  Future<List<SongItem>> getArtistSongs(String artistId, {String? artistName}) async {
    final cleanId = artistId.trim();
    if (!_isInitialized) {
      await initialize();
    }

    if (cleanId.isNotEmpty) {
      try {
        final songs = await _ytMusic.getArtistSongs(cleanId);
        if (songs.isNotEmpty) {
          return songs
              .where((s) => s.videoId.isNotEmpty)
              .map((s) {
                final thumb = s.thumbnails.isNotEmpty
                    ? SongItem.upgradeThumbnail(s.thumbnails.last.url)
                    : null;
                final name = s.artist.name.isNotEmpty
                    ? s.artist.name
                    : (artistName ?? 'Artist');
                return SongItem(
                  id: s.videoId,
                  title: s.name.isNotEmpty ? s.name : 'Untitled',
                  artist: name,
                  thumbnailUrl: thumb,
                  durationSeconds: s.duration,
                  album: s.album?.name,
                );
              })
              .toList();
        }
      } catch (e) {
        debugPrint('getArtistSongs error for $cleanId: $e');
      }
    }

    if (artistName != null && artistName.isNotEmpty) {
      return searchSongs(artistName);
    }

    return [];
  }

  /// Fetches comprehensive artist details from YouTube Music including bio,
  /// subscriber stats, monthly audience, top songs, albums, singles & EPs,
  /// music videos, featured playlists, artist playlists, and fans might also like.
  Future<ArtistDetails> getArtistDetails(String artistIdOrName, {String? fallbackName}) async {
    final rawQuery = artistIdOrName.trim();
    if (!_isInitialized) {
      await initialize();
    }

    // Check memory cache
    final cached = _artistDetailsCache[rawQuery.toLowerCase()];
    if (cached != null) {
      final age = DateTime.now().difference(cached.timestamp);
      if (age < const Duration(minutes: 15)) {
        return cached.details;
      }
      _artistDetailsCache.remove(rawQuery.toLowerCase());
    }

    String targetId = rawQuery;
    String resolvedName = fallbackName ?? rawQuery;

    // If ID is not a standard channel browseId (UC...), search for the artist channel ID
    if (!targetId.startsWith('UC')) {
      final searchQuery = fallbackName != null && fallbackName.isNotEmpty ? fallbackName : rawQuery;
      final searchResults = await searchArtists(searchQuery);
      if (searchResults.isNotEmpty) {
        targetId = searchResults.first.id;
        resolvedName = searchResults.first.name;
      }
    }

    String? bannerUrl;
    String? thumbnailUrl;
    String? subscribers;
    String? monthlyListeners;
    String? description;
    List<SongItem> topSongs = [];
    List<AlbumItem> albums = [];
    List<AlbumItem> singles = [];
    List<VideoItem> videos = [];
    List<PlaylistItem> featuredOn = [];
    List<PlaylistItem> playlistsByArtist = [];
    List<ArtistItem> similarArtists = [];
    AlbumItem? recentRelease;
    String? moreTracksBrowseId;

    // 1. Direct InnerTube browse request to extract full rich layout matching YouTube Music
    if (targetId.startsWith('UC')) {
      try {
        final data = await _ytMusic.constructRequest('browse', body: {'browseId': targetId});
        final header = data['header']?['musicImmersiveHeaderRenderer'] ??
            data['header']?['musicVisualHeaderRenderer'] ??
            data['header']?['musicHeaderRenderer'];

        if (header != null) {
          final titleText = traverseString(header, ['title', 'runs', 'text']);
          if (titleText != null && titleText.isNotEmpty) {
            resolvedName = titleText;
          }

          // Subscribers
          final subButton = header['subscriptionButton']?['subscribeButtonRenderer'];
          subscribers = traverseString(subButton, ['longSubscriberCountText', 'runs', 'text']) ??
              traverseString(subButton, ['subscriberCountText', 'runs', 'text']) ??
              traverseString(subButton, ['shortSubscriberCountText', 'runs', 'text']);

          // Monthly Audience / Listeners
          monthlyListeners = traverseString(header, ['monthlyListenerCount', 'runs', 'text']);

          // Bio description
          final descRuns = header['description']?['runs'] as List?;
          if (descRuns != null && descRuns.isNotEmpty) {
            description = descRuns.map((r) => r['text'] ?? '').join('').trim();
          }

          // Banner Image
          final thumbs = traverseList(header, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
          if (thumbs.isNotEmpty) {
            final lastUrl = thumbs.last?['url'] as String?;
            if (lastUrl != null && lastUrl.isNotEmpty) {
              bannerUrl = SongItem.upgradeThumbnail(lastUrl);
              thumbnailUrl = bannerUrl;
            }
          }
        }

        // Parse contents sections
        final contents = data['contents']?['singleColumnBrowseResultsRenderer']?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List?;
        if (contents != null) {
          for (final section in contents) {
            // Top songs shelf
            final shelf = section['musicShelfRenderer'];
            if (shelf != null) {
              moreTracksBrowseId ??= traverseString(shelf, ['bottomEndpoint', 'browseEndpoint', 'browseId']) ??
                  traverseString(shelf, ['title', 'runs', 'navigationEndpoint', 'browseEndpoint', 'browseId']);
              final shelfTitle = (traverseString(shelf, ['title', 'runs', 'text']) ?? '').toLowerCase();
              if (shelfTitle.contains('song') || topSongs.isEmpty) {
                final items = shelf['contents'] as List? ?? [];
                for (final it in items) {
                  final item = it['musicResponsiveListItemRenderer'];
                  if (item == null) continue;
                  final vId = item['playlistItemData']?['videoId'] ??
                      traverseString(item, ['navigationEndpoint', 'watchEndpoint', 'videoId']);
                  if (vId == null || (vId as String).isEmpty) continue;

                  final flexCols = item['flexColumns'] as List? ?? [];
                  String title = 'Untitled';
                  String artist = resolvedName;
                  String? album;

                  if (flexCols.isNotEmpty) {
                    title = traverseString(flexCols[0], ['musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 'text']) ?? 'Untitled';
                  }
                  if (flexCols.length > 1) {
                    artist = traverseString(flexCols[1], ['musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 'text']) ?? resolvedName;
                  }
                  if (flexCols.length > 2) {
                    album = traverseString(flexCols[2], ['musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 'text']);
                  }

                  String? thumb;
                  final itemThumbs = traverseList(item, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
                  if (itemThumbs.isNotEmpty) {
                    thumb = SongItem.upgradeThumbnail(itemThumbs.last?['url'] as String? ?? '');
                  }

                  topSongs.add(
                    SongItem(
                      id: vId,
                      title: title,
                      artist: artist,
                      thumbnailUrl: thumb,
                      album: album,
                    ),
                  );
                }
              }
            }

            // Carousels: Albums, Singles, Videos, Featured, Playlists, Similar Artists
            final carousel = section['musicCarouselShelfRenderer'];
            if (carousel != null) {
              final carouselTitle = (traverseString(carousel, ['header', 'musicCarouselShelfBasicHeaderRenderer', 'title', 'runs', 'text']) ?? '').toLowerCase();
              final items = carousel['contents'] as List? ?? [];

              if (carouselTitle.contains('album')) {
                for (final it in items) {
                  final renderer = it['musicTwoRowItemRenderer'];
                  if (renderer == null) continue;
                  final browseId = traverseString(renderer, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
                  if (browseId == null || browseId.isEmpty) continue;
                  final title = traverseString(renderer, ['title', 'runs', 'text']) ?? 'Album';
                  final subtitle = traverseString(renderer, ['subtitle', 'runs', 'text']) ?? '';
                  final yearMatch = RegExp(r'\b(19|20)\d{2}\b').firstMatch(subtitle);
                  final year = yearMatch != null ? int.tryParse(yearMatch.group(0)!) : null;

                  String? thumb;
                  final itemThumbs = traverseList(renderer, ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
                  if (itemThumbs.isNotEmpty) {
                    thumb = SongItem.upgradeThumbnail(itemThumbs.last?['url'] as String? ?? '');
                  }

                  albums.add(
                    AlbumItem(
                      id: browseId,
                      title: title,
                      artist: resolvedName,
                      thumbnailUrl: thumb,
                      year: year,
                      type: 'Album',
                    ),
                  );
                }
              } else if (carouselTitle.contains('single') || carouselTitle.contains('ep')) {
                for (final it in items) {
                  final renderer = it['musicTwoRowItemRenderer'];
                  if (renderer == null) continue;
                  final browseId = traverseString(renderer, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
                  if (browseId == null || browseId.isEmpty) continue;
                  final title = traverseString(renderer, ['title', 'runs', 'text']) ?? 'Single';
                  final subtitle = traverseString(renderer, ['subtitle', 'runs', 'text']) ?? '';
                  final yearMatch = RegExp(r'\b(19|20)\d{2}\b').firstMatch(subtitle);
                  final year = yearMatch != null ? int.tryParse(yearMatch.group(0)!) : null;

                  String? thumb;
                  final itemThumbs = traverseList(renderer, ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
                  if (itemThumbs.isNotEmpty) {
                    thumb = SongItem.upgradeThumbnail(itemThumbs.last?['url'] as String? ?? '');
                  }

                  singles.add(
                    AlbumItem(
                      id: browseId,
                      title: title,
                      artist: resolvedName,
                      thumbnailUrl: thumb,
                      year: year,
                      type: 'Single',
                    ),
                  );
                }
              } else if (carouselTitle.contains('video')) {
                for (final it in items) {
                  final renderer = it['musicTwoRowItemRenderer'];
                  if (renderer == null) continue;
                  final videoId = traverseString(renderer, ['navigationEndpoint', 'watchEndpoint', 'videoId']);
                  if (videoId == null || videoId.isEmpty) continue;
                  final title = traverseString(renderer, ['title', 'runs', 'text']) ?? 'Video';
                  final subtitle = traverseString(renderer, ['subtitle', 'runs', 'text']) ?? '';
                  final views = subtitle.contains('views') ? subtitle : null;

                  String? thumb;
                  final itemThumbs = traverseList(renderer, ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
                  if (itemThumbs.isNotEmpty) {
                    thumb = SongItem.upgradeThumbnail(itemThumbs.last?['url'] as String? ?? '');
                  }

                  videos.add(
                    VideoItem(
                      id: videoId,
                      title: title,
                      artist: resolvedName,
                      thumbnailUrl: thumb,
                      views: views,
                    ),
                  );
                }
              } else if (carouselTitle.contains('featured')) {
                for (final it in items) {
                  final renderer = it['musicTwoRowItemRenderer'];
                  if (renderer == null) continue;
                  final browseId = traverseString(renderer, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
                  if (browseId == null || browseId.isEmpty) continue;
                  final title = traverseString(renderer, ['title', 'runs', 'text']) ?? 'Playlist';

                  String? thumb;
                  final itemThumbs = traverseList(renderer, ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
                  if (itemThumbs.isNotEmpty) {
                    thumb = SongItem.upgradeThumbnail(itemThumbs.last?['url'] as String? ?? '');
                  }

                  featuredOn.add(
                    PlaylistItem(
                      id: browseId,
                      title: title,
                      author: 'YouTube Music',
                      thumbnailUrl: thumb,
                    ),
                  );
                }
              } else if (carouselTitle.contains('playlist')) {
                for (final it in items) {
                  final renderer = it['musicTwoRowItemRenderer'];
                  if (renderer == null) continue;
                  final browseId = traverseString(renderer, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
                  if (browseId == null || browseId.isEmpty) continue;
                  final title = traverseString(renderer, ['title', 'runs', 'text']) ?? 'Playlist';

                  String? thumb;
                  final itemThumbs = traverseList(renderer, ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
                  if (itemThumbs.isNotEmpty) {
                    thumb = SongItem.upgradeThumbnail(itemThumbs.last?['url'] as String? ?? '');
                  }

                  playlistsByArtist.add(
                    PlaylistItem(
                      id: browseId,
                      title: title,
                      author: resolvedName,
                      thumbnailUrl: thumb,
                    ),
                  );
                }
              } else if (carouselTitle.contains('fan') || carouselTitle.contains('similar')) {
                for (final it in items) {
                  final renderer = it['musicTwoRowItemRenderer'];
                  if (renderer == null) continue;
                  final artistBrowseId = traverseString(renderer, ['navigationEndpoint', 'browseEndpoint', 'browseId']);
                  if (artistBrowseId == null || artistBrowseId.isEmpty) continue;
                  final title = traverseString(renderer, ['title', 'runs', 'text']) ?? 'Artist';
                  final subtitle = traverseString(renderer, ['subtitle', 'runs', 'text']) ?? '';

                  String? thumb;
                  final itemThumbs = traverseList(renderer, ['thumbnailRenderer', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
                  if (itemThumbs.isNotEmpty) {
                    thumb = SongItem.upgradeThumbnail(itemThumbs.last?['url'] as String? ?? '');
                  }

                  similarArtists.add(
                    ArtistItem(
                      id: artistBrowseId,
                      name: title,
                      thumbnailUrl: thumb,
                      subscribers: subtitle.isNotEmpty ? subtitle : null,
                    ),
                  );
                }
              }
            }

            // Description shelf (About the artist)
            final descShelf = section['musicDescriptionShelfRenderer'];
            if (descShelf != null) {
              if (description == null || description.isEmpty) {
                final descRuns = descShelf['description']?['runs'] as List?;
                if (descRuns != null && descRuns.isNotEmpty) {
                  description = descRuns.map((r) => r['text'] ?? '').join('').trim();
                }
              }
              subscribers ??= traverseString(descShelf, ['subheader', 'runs', 'text']);
            }
          }
        }
      } catch (e) {
        debugPrint('getArtistDetails raw parse error: $e');
      }
    }

    // 2. High-reliability fallback via _ytMusic.getArtist() if essential lists are empty
    if ((topSongs.isEmpty || albums.isEmpty || singles.isEmpty) && targetId.startsWith('UC')) {
      try {
        final artistFull = await _ytMusic.getArtist(targetId);
        if (topSongs.isEmpty && artistFull.topSongs.isNotEmpty) {
          topSongs = artistFull.topSongs.map((s) => SongItem(
            id: s.videoId,
            title: s.name,
            artist: s.artist.name.isNotEmpty ? s.artist.name : resolvedName,
            thumbnailUrl: s.thumbnails.isNotEmpty ? SongItem.upgradeThumbnail(s.thumbnails.last.url) : null,
            album: s.album?.name,
            durationSeconds: s.duration,
          )).toList();
        }
        if (albums.isEmpty && artistFull.topAlbums.isNotEmpty) {
          albums = artistFull.topAlbums.map((a) => AlbumItem(
            id: a.albumId,
            title: a.name,
            artist: a.artist.name.isNotEmpty ? a.artist.name : resolvedName,
            thumbnailUrl: a.thumbnails.isNotEmpty ? SongItem.upgradeThumbnail(a.thumbnails.last.url) : null,
            year: a.year,
            type: 'Album',
          )).toList();
        }
        if (singles.isEmpty && artistFull.topSingles.isNotEmpty) {
          singles = artistFull.topSingles.map((a) => AlbumItem(
            id: a.albumId,
            title: a.name,
            artist: a.artist.name.isNotEmpty ? a.artist.name : resolvedName,
            thumbnailUrl: a.thumbnails.isNotEmpty ? SongItem.upgradeThumbnail(a.thumbnails.last.url) : null,
            year: a.year,
            type: 'Single',
          )).toList();
        }
        if (videos.isEmpty && artistFull.topVideos.isNotEmpty) {
          videos = artistFull.topVideos.map((v) => VideoItem(
            id: v.videoId,
            title: v.name,
            artist: v.artist.name,
            thumbnailUrl: v.thumbnails.isNotEmpty ? SongItem.upgradeThumbnail(v.thumbnails.last.url) : null,
            durationSeconds: v.duration,
          )).toList();
        }
        if (featuredOn.isEmpty && artistFull.featuredOn.isNotEmpty) {
          featuredOn = artistFull.featuredOn.map((p) => PlaylistItem(
            id: p.playlistId,
            title: p.name,
            author: p.artist.name.isNotEmpty ? p.artist.name : 'YouTube Music',
            thumbnailUrl: p.thumbnails.isNotEmpty ? SongItem.upgradeThumbnail(p.thumbnails.last.url) : null,
          )).toList();
        }
        if (similarArtists.isEmpty && artistFull.similarArtists.isNotEmpty) {
          similarArtists = artistFull.similarArtists.map((a) => ArtistItem(
            id: a.artistId,
            name: a.name,
            thumbnailUrl: a.thumbnails.isNotEmpty ? SongItem.upgradeThumbnail(a.thumbnails.last.url) : null,
          )).toList();
        }
        if (bannerUrl == null && artistFull.thumbnails.isNotEmpty) {
          bannerUrl = SongItem.upgradeThumbnail(artistFull.thumbnails.last.url);
          thumbnailUrl = bannerUrl;
        }
      } catch (e) {
        debugPrint('getArtistDetails fallback error: $e');
      }
    }

    // Ensure at least 12 tracks in advance for top songs
    if (topSongs.length < 12) {
      // 1. Try moreTracksBrowseId if available
      if (moreTracksBrowseId != null && moreTracksBrowseId.isNotEmpty) {
        try {
          final moreData = await _ytMusic.constructRequest('browse', body: {'browseId': moreTracksBrowseId});
          final tabs = moreData['contents']?['singleColumnBrowseResultsRenderer']?['tabs'] as List?;
          List? sections;
          if (tabs != null && tabs.isNotEmpty) {
            final firstTab = tabs.first;
            if (firstTab is Map) {
              sections = firstTab['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List?;
            }
          }
          sections ??= moreData['contents']?['sectionListRenderer']?['contents'] as List?;
          final firstSection = (sections != null && sections.isNotEmpty && sections.first is Map)
              ? sections.first as Map
              : null;
          final playlistShelf = firstSection?['musicPlaylistShelfRenderer'] ?? firstSection?['musicShelfRenderer'];
          final moreContents = playlistShelf?['contents'] as List? ?? [];

          for (final it in moreContents) {
            final item = it['musicResponsiveListItemRenderer'];
            if (item == null) continue;
            final vId = item['playlistItemData']?['videoId'] ??
                traverseString(item, ['navigationEndpoint', 'watchEndpoint', 'videoId']);
            if (vId == null || (vId as String).isEmpty) continue;

            final flexCols = item['flexColumns'] as List? ?? [];
            String title = 'Untitled';
            String artist = resolvedName;
            String? album;

            if (flexCols.isNotEmpty) {
              title = traverseString(flexCols[0], ['musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 'text']) ?? 'Untitled';
            }
            if (flexCols.length > 1) {
              artist = traverseString(flexCols[1], ['musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 'text']) ?? resolvedName;
            }
            if (flexCols.length > 2) {
              album = traverseString(flexCols[2], ['musicResponsiveListItemFlexColumnRenderer', 'text', 'runs', 'text']);
            }

            String? thumb;
            final itemThumbs = traverseList(item, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
            if (itemThumbs.isNotEmpty) {
              thumb = SongItem.upgradeThumbnail(itemThumbs.last?['url'] as String? ?? '');
            }

            final isDuplicate = topSongs.any(
              (s) => s.id == vId || s.title.trim().toLowerCase() == title.trim().toLowerCase(),
            );
            if (!isDuplicate) {
              topSongs.add(
                SongItem(
                  id: vId,
                  title: title,
                  artist: artist,
                  thumbnailUrl: thumb,
                  album: album,
                ),
              );
              if (topSongs.length >= 12) break;
            }
          }
        } catch (e) {
          debugPrint('Error fetching more browse tracks: $e');
        }
      }

      // 2. Query searchSongs as reliable fallback to reach at least 12 tracks
      if (topSongs.length < 12) {
        try {
          final query = resolvedName.isNotEmpty ? resolvedName : (fallbackName ?? '');
          if (query.isNotEmpty) {
            final additionalTracks = await searchSongs(query);
            for (final track in additionalTracks) {
              final isDuplicate = topSongs.any(
                (s) => s.id == track.id || s.title.trim().toLowerCase() == track.title.trim().toLowerCase(),
              );
              if (!isDuplicate) {
                topSongs.add(track);
                if (topSongs.length >= 12) break;
              }
            }
          }
        } catch (e) {
          debugPrint('Error fetching advance top songs: $e');
        }
      }
    }

    // Determine recent release spotlight
    if (singles.isNotEmpty) {
      recentRelease = singles.first;
    } else if (albums.isNotEmpty) {
      recentRelease = albums.first;
    }

    final details = ArtistDetails(
      id: targetId,
      name: resolvedName,
      bannerUrl: bannerUrl,
      thumbnailUrl: thumbnailUrl ?? bannerUrl,
      subscribers: subscribers,
      monthlyListeners: monthlyListeners,
      description: description,
      topSongs: topSongs,
      albums: albums,
      singles: singles,
      videos: videos,
      featuredOn: featuredOn,
      playlistsByArtist: playlistsByArtist,
      similarArtists: similarArtists,
      recentRelease: recentRelease,
    );

    // Cache details
    _artistDetailsCache[rawQuery.toLowerCase()] = (details: details, timestamp: DateTime.now());
    if (targetId.isNotEmpty) {
      _artistDetailsCache[targetId.toLowerCase()] = (details: details, timestamp: DateTime.now());
    }

    return details;
  }

  /// Fetches user's personalized mixes and playlists if logged into YouTube Music.
  Future<List<PlaylistItem>> getPersonalizedMixes() async {
    if (!_isInitialized) {
      await initialize();
    }

    final mixes = <PlaylistItem>[];
    if (_currentAccount != null) {
      try {
        final sections = await _ytMusic.getHomeSections();
        for (final section in sections) {
          final titleLower = section.title.toLowerCase();
          if (titleLower.contains('mixed for you') ||
              titleLower.contains('mix') ||
              titleLower.contains('playlist') ||
              titleLower.contains('radio')) {
            for (final item in section.contents) {
              if (item is PlaylistDetailed && item.playlistId.isNotEmpty) {
                final thumb = item.thumbnails.isNotEmpty
                    ? SongItem.upgradeThumbnail(item.thumbnails.last.url)
                    : null;
                mixes.add(
                  PlaylistItem(
                    id: item.playlistId,
                    title: item.name.isNotEmpty ? item.name : 'Mix',
                    author: item.artist.name.isNotEmpty
                        ? item.artist.name
                        : 'YouTube Music',
                    thumbnailUrl: thumb,
                  ),
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('getPersonalizedMixes error: $e');
      }
    }
    return mixes;
  }

  /// Fetches the user's specific playlists from their YouTube Music account.
  Future<List<PlaylistItem>> getUserPlaylists() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_currentAccount == null) return [];

    final playlists = <PlaylistItem>[];
    final seenIds = <String>{};

    try {
      final sections = await _ytMusic.getHomeSections();
      for (final section in sections) {
        for (final item in section.contents) {
          if (item is PlaylistDetailed && item.playlistId.isNotEmpty) {
            if (!seenIds.contains(item.playlistId)) {
              seenIds.add(item.playlistId);
              String? thumb;
              if (item.thumbnails.isNotEmpty) {
                final raw = item.thumbnails.last.url;
                thumb = SongItem.upgradeThumbnail(raw.startsWith('//') ? 'https:$raw' : raw);
              }
              playlists.add(
                PlaylistItem(
                  id: item.playlistId,
                  title: item.name.isNotEmpty ? item.name : 'Playlist',
                  author: item.artist.name.isNotEmpty
                      ? item.artist.name
                      : 'YouTube Music',
                  thumbnailUrl: thumb,
                  isCustom: false,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('getUserPlaylists error: $e');
    }

    return playlists;
  }

  /// Fetches the user's specific saved albums from their YouTube Music account.
  Future<List<AlbumItem>> getUserAlbums() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_currentAccount == null) return [];

    final albums = <AlbumItem>[];
    final seenIds = <String>{};

    try {
      final sections = await _ytMusic.getHomeSections();
      for (final section in sections) {
        for (final item in section.contents) {
          if (item is AlbumDetailed && item.albumId.isNotEmpty) {
            if (!seenIds.contains(item.albumId)) {
              seenIds.add(item.albumId);
              String? thumb;
              if (item.thumbnails.isNotEmpty) {
                final raw = item.thumbnails.last.url;
                thumb = SongItem.upgradeThumbnail(raw.startsWith('//') ? 'https:$raw' : raw);
              }
              albums.add(
                AlbumItem(
                  id: item.albumId,
                  title: item.name.isNotEmpty ? item.name : 'Album',
                  artist: item.artist.name.isNotEmpty
                      ? item.artist.name
                      : 'Unknown Artist',
                  thumbnailUrl: thumb,
                  type: item.type.isNotEmpty ? item.type : 'Album',
                  year: item.year,
                  isCustom: false,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('getUserAlbums error: $e');
    }

    return albums;
  }

  /// Fetches the user's specific subscribed artists from their YouTube Music account.
  Future<List<ArtistItem>> getUserArtists() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_currentAccount == null) return [];

    final artists = <ArtistItem>[];
    final seenIds = <String>{};

    try {
      final sections = await _ytMusic.getHomeSections();
      for (final section in sections) {
        for (final item in section.contents) {
          if (item is ArtistDetailed && item.artistId.isNotEmpty) {
            if (!seenIds.contains(item.artistId)) {
              seenIds.add(item.artistId);
              String? thumb;
              if (item.thumbnails.isNotEmpty) {
                final raw = item.thumbnails.last.url;
                thumb = SongItem.upgradeThumbnail(raw.startsWith('//') ? 'https:$raw' : raw);
              }
              artists.add(
                ArtistItem(
                  id: item.artistId,
                  name: item.name.isNotEmpty ? item.name : 'Artist',
                  thumbnailUrl: thumb,
                  subscribers: 'Artist',
                  isCustom: false,
                ),
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('getUserArtists error: $e');
    }

    return artists;
  }

  Future<List<VideoItem>> searchVideos(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    if (!_isInitialized) {
      await initialize();
    }

    try {
      final results = await _ytMusic.searchVideos(trimmedQuery);
      return results
          .where((v) => v.videoId.isNotEmpty)
          .map((v) {
            String? thumb;
            if (v.thumbnails.isNotEmpty) {
              thumb = v.thumbnails.last.url;
            }
            return VideoItem(
              id: v.videoId,
              title: v.name.isNotEmpty ? v.name : 'Untitled Video',
              artist: v.artist.name.isNotEmpty ? v.artist.name : 'Unknown Artist',
              thumbnailUrl: thumb,
              durationSeconds: v.duration,
            );
          })
          .toList();
    } catch (e) {
      debugPrint('searchVideos error: $e');
      return [];
    }
  }

  Future<({List<MusicCategory> moods, List<MusicCategory> genres})> _fetchMoodsAndGenres() async {
    try {
      final moodRes = await _ytMusic.constructRequest(
        'browse',
        body: {'browseId': 'FEmusic_moods_and_genres'},
      );

      if (moodRes is! Map) {
        return (moods: _defaultMoods, genres: _defaultGenres);
      }

      final tabs = traverseList(moodRes, ['contents', 'singleColumnBrowseResultsRenderer', 'tabs']);
      final sectionContents = tabs.firstOrNull?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List? ?? [];

      final List<MusicCategory> parsedMoods = [];
      final List<MusicCategory> parsedGenres = [];

      for (final section in sectionContents) {
        final title = traverseString(section, ['gridRenderer', 'header', 'gridHeaderRenderer', 'title', 'runs']) ??
            traverseString(section, ['musicCarouselShelfRenderer', 'header', 'musicCarouselShelfBasicHeaderRenderer', 'title', 'runs']) ??
            '';

        final items = (section['gridRenderer']?['items'] as List?) ??
            (section['musicCarouselShelfRenderer']?['contents'] as List?) ??
            [];

        for (final it in items) {
          final btn = it['musicNavigationButtonRenderer'];
          if (btn == null) continue;
          final textRuns = btn['buttonText']?['runs'] as List? ?? [];
          final text = textRuns.isNotEmpty ? textRuns.first['text'] as String? ?? '' : '';
          final color = (btn['solid']?['leftStripeColor'] as num?)?.toInt();

          if (text.isNotEmpty) {
            final cat = MusicCategory(title: text, colorValue: color);
            if (title.toLowerCase().contains('mood') || title.toLowerCase().contains('moment')) {
              parsedMoods.add(cat);
            } else {
              parsedGenres.add(cat);
            }
          }
        }
      }

      return (
        moods: parsedMoods.isNotEmpty ? parsedMoods : _defaultMoods,
        genres: parsedGenres.isNotEmpty ? parsedGenres : _defaultGenres,
      );
    } catch (_) {
      return (moods: _defaultMoods, genres: _defaultGenres);
    }
  }

  /// Fetches synchronized Apple Music-style lyrics (word-by-word synced where available)
  /// using the binimum/am-lyrics provider chain (lrc.red -> LyricsPlus/BiniLyrics -> LRCLIB -> YTMusic).
  Future<LyricsResult> getLyricsWithMetadata({
    required String videoId,
    required String title,
    required String artist,
    String? album,
    int? durationSeconds,
  }) async {
    return _lyricsService.fetchLyrics(
      title: title,
      artist: artist,
      album: album,
      durationSeconds: durationSeconds,
      ytFallback: () => _fetchYtMusicLyrics(videoId),
    );
  }

  /// Backward-compatible getLyrics method.
  Future<List<LyricLine>> getLyrics(
    String videoId, {
    String? title,
    String? artist,
    String? album,
    int? durationSeconds,
  }) async {
    if (title != null && artist != null) {
      final res = await getLyricsWithMetadata(
        videoId: videoId,
        title: title,
        artist: artist,
        album: album,
        durationSeconds: durationSeconds,
      );
      if (res.lines.isNotEmpty) return res.lines;
    }
    return _fetchYtMusicLyrics(videoId);
  }

  Future<List<LyricLine>> _fetchYtMusicLyrics(String videoId) async {
    final trimmedId = videoId.trim();
    if (trimmedId.isEmpty) return [];

    if (!_isInitialized) {
      await initialize();
    }

    // 1. Try timed lyrics first for synchronized karaoke scrolling
    try {
      final timed = await _ytMusic.getTimedLyrics(trimmedId);
      if (timed != null && timed.timedLyricsData.isNotEmpty) {
        final parsed = timed.timedLyricsData
            .map((item) {
              final line = item.lyricLine?.trim() ?? '';
              return LyricLine(
                text: line,
                startTimeMs: item.cueRange?.startTimeMilliseconds,
                endTimeMs: item.cueRange?.endTimeMilliseconds,
              );
            })
            .where((l) => l.text.isNotEmpty)
            .toList();

        if (parsed.isNotEmpty) return parsed;
      }
    } catch (e) {
      debugPrint('getTimedLyrics fallback: $e');
    }

    // 2. Fallback to plain text lyrics
    try {
      final plain = await _ytMusic.getLyrics(trimmedId);
      if (plain != null && plain.trim().isNotEmpty) {
        return plain
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .map((l) => LyricLine(text: l))
            .toList();
      }
    } catch (e) {
      debugPrint('getLyrics error: $e');
    }

    return [];
  }

  /// Searches for songs by query string.
  Future<List<SongItem>> searchSongs(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return [];
    }

    if (!_isInitialized) {
      await initialize();
    }

    final results = await _ytMusic.searchSongs(trimmedQuery);

    return results
        .where((song) => song.videoId.isNotEmpty)
        .map((song) {
          final artistName = song.artist.name.isNotEmpty
              ? song.artist.name
              : 'Unknown Artist';

          String? thumbUrl;
          if (song.thumbnails.isNotEmpty) {
            thumbUrl = song.thumbnails.last.url;
          }

          return SongItem(
            id: song.videoId,
            title: song.name.isNotEmpty ? song.name : 'Untitled Track',
            artist: artistName,
            album: song.album?.name,
            thumbnailUrl: SongItem.upgradeThumbnail(thumbUrl),
            durationSeconds: song.duration,
          );
        })
        .toList();
  }

  /// Resolves the audio stream info (URL, matching headers, bitrate, mimeType)
  /// using client fallback rotation and stream probing.
  Future<AudioStreamInfo> resolveAudioStream(String videoId) async {
    final trimmedId = videoId.trim();
    if (trimmedId.isEmpty) {
      throw ArgumentError('Video ID cannot be empty');
    }

    // Check memory cache with smart URL expiry check
    final cached = _streamCache[trimmedId];
    if (cached != null) {
      bool isCacheValid = false;
      final expireMatch = RegExp(r'[?&]expire=(\d+)').firstMatch(cached.info.url);
      if (expireMatch != null) {
        final expireSec = int.tryParse(expireMatch.group(1) ?? '');
        if (expireSec != null) {
          final expireDate = DateTime.fromMillisecondsSinceEpoch(expireSec * 1000);
          if (DateTime.now().isBefore(expireDate.subtract(const Duration(minutes: 15)))) {
            isCacheValid = true;
          }
        }
      } else {
        final age = DateTime.now().difference(cached.timestamp);
        if (age < const Duration(hours: 3)) {
          isCacheValid = true;
        }
      }

      if (isCacheValid) {
        if (cached.info.durationSeconds != null && cached.info.durationSeconds! > 0) {
          unawaited(SongMetricsCacheService.instance.setDuration(trimmedId, cached.info.durationSeconds!));
        }
        return cached.info;
      }
      _streamCache.remove(trimmedId);
    }

    if (!_isInitialized) {
      await initialize();
    }

    Object? lastError;

    // Try each client tier in order until a verified stream is obtained
    for (final client in _clientTiers) {
      try {
        final streamInfo = await _extractWithClient(trimmedId, client);
        if (streamInfo != null) {
          // Probe stream URL with bounded range (0-1024) to ensure HTTP 206 / 200 before returning
          final isViable = await _probeStreamUrl(streamInfo.url, streamInfo.headers);
          if (isViable) {
            _streamCache[trimmedId] = (info: streamInfo, timestamp: DateTime.now());
            if (streamInfo.durationSeconds != null && streamInfo.durationSeconds! > 0) {
              unawaited(SongMetricsCacheService.instance.setDuration(trimmedId, streamInfo.durationSeconds!));
            }
            return streamInfo;
          }
        }
      } catch (e) {
        lastError = e;
        // Continue to fallback client
      }
    }

    if (lastError != null) {
      throw Exception('Failed to resolve stream for track $trimmedId: $lastError');
    }
    throw Exception('No playable audio stream could be verified for track $trimmedId');
  }

  /// Resolves a crisp high-definition video stream (HLS .m3u8 or progressive MP4) for [videoId].
  /// Used for Apple Music / Spotify Canvas-style moving background video in the player screen.
  Future<VideoStreamInfo?> resolveVideoStream(String videoId) async {
    final trimmedId = videoId.trim();
    if (trimmedId.isEmpty) return null;

    final cached = _videoStreamCache[trimmedId];
    if (cached != null) {
      return cached;
    }

    if (!_isInitialized) {
      await initialize();
    }

    for (final client in _clientTiers) {
      try {
        final data = await _ytMusic.constructRequest(
          "player",
          body: {"videoId": trimmedId},
          options: ClientRequestOptions(
            clientName: client.clientName,
            clientVersion: client.clientVersion,
          ),
        );

        if (data is! Map) continue;

        final streamingData = data['streamingData'] as Map<String, dynamic>?;
        if (streamingData == null) continue;

        // 1. Prefer HLS Master Manifest (.m3u8) - natively decoded by AVPlayer (iOS/macOS)
        // and ExoPlayer (Android), adaptive up to 1080p/720p, zero fragmented container errors!
        final hlsUrl = streamingData['hlsManifestUrl'] as String?;
        if (hlsUrl != null && hlsUrl.isNotEmpty) {
          final info = VideoStreamInfo(
            url: hlsUrl,
            headers: {
              'User-Agent': client.userAgent,
            },
            width: 1920,
            height: 1080,
            qualityLabel: '1080p',
          );
          _videoStreamCache[trimmedId] = info;
          return info;
        }

        // 2. Next check combined progressive MP4 formats (has full standard moov container atom)
        final progressiveFormats = (streamingData['formats'] as List<dynamic>? ?? [])
            .where((f) {
              final mime = f['mimeType'] as String? ?? '';
              return mime.startsWith('video/mp4') && f.containsKey('url');
            }).toList();

        if (progressiveFormats.isNotEmpty) {
          progressiveFormats.sort((a, b) {
            final aHeight = (a['height'] as num?)?.toInt() ?? 0;
            final bHeight = (b['height'] as num?)?.toInt() ?? 0;
            return bHeight.compareTo(aHeight);
          });
          final selected = progressiveFormats.first;
          final videoUrl = selected['url'] as String?;
          if (videoUrl != null && videoUrl.isNotEmpty) {
            final w = (selected['width'] as num?)?.toInt() ?? 640;
            final h = (selected['height'] as num?)?.toInt() ?? 360;
            final q = selected['qualityLabel'] as String? ?? '${h}p';
            final info = VideoStreamInfo(
              url: videoUrl,
              headers: {
                'User-Agent': client.userAgent,
              },
              width: w,
              height: h,
              qualityLabel: q,
            );
            _videoStreamCache[trimmedId] = info;
            return info;
          }
        }

        // 3. Fallback to adaptiveFormats MP4
        final adaptiveFormats = streamingData['adaptiveFormats'] as List<dynamic>? ?? [];
        final videoFormats = adaptiveFormats.where((f) {
          final mime = f['mimeType'] as String? ?? '';
          return mime.startsWith('video/mp4') && f.containsKey('url');
        }).toList();

        if (videoFormats.isEmpty) continue;

        videoFormats.sort((a, b) {
          final bHeight = (b['height'] as num?)?.toInt() ?? 0;
          final aHeight = (a['height'] as num?)?.toInt() ?? 0;
          return bHeight.compareTo(aHeight);
        });

        final selectedFormat = videoFormats.firstWhere(
          (f) {
            final h = (f['height'] as num?)?.toInt() ?? 0;
            return h >= 720 && h <= 1080;
          },
          orElse: () => videoFormats.first,
        );

        final videoUrl = selectedFormat['url'] as String?;
        if (videoUrl == null || videoUrl.isEmpty) continue;

        final width = (selectedFormat['width'] as num?)?.toInt() ?? 1280;
        final height = (selectedFormat['height'] as num?)?.toInt() ?? 720;
        final qualityLabel = selectedFormat['qualityLabel'] as String? ?? '${height}p';

        final info = VideoStreamInfo(
          url: videoUrl,
          headers: {
            'User-Agent': client.userAgent,
          },
          width: width,
          height: height,
          qualityLabel: qualityLabel,
        );

        _videoStreamCache[trimmedId] = info;
        return info;
      } catch (_) {
        // Continue to fallback client
      }
    }

    _videoStreamCache[trimmedId] = null;
    return null;
  }

  /// Backwards-compatible convenience method that returns just the direct stream URL.
  Future<String> getAudioStreamUrl(String videoId) async {
    final info = await resolveAudioStream(videoId);
    return info.url;
  }

  /// Queries the InnerTube player endpoint with the given client profile.
  Future<AudioStreamInfo?> _extractWithClient(
    String videoId,
    _InnerTubeClientConfig clientConfig,
  ) async {
    final data = await _ytMusic.constructRequest(
      "player",
      body: {"videoId": videoId},
      options: ClientRequestOptions(
        clientName: clientConfig.clientName,
        clientVersion: clientConfig.clientVersion,
      ),
    );

    if (data is! Map) return null;

    final playabilityStatus = data['playabilityStatus'] as Map<String, dynamic>?;
    if (playabilityStatus != null && playabilityStatus['status'] != 'OK') {
      return null;
    }

    final streamingData = data['streamingData'] as Map<String, dynamic>?;
    if (streamingData == null) return null;

    final adaptiveFormats = streamingData['adaptiveFormats'] as List<dynamic>? ?? [];

    // Filter available audio formats with direct playable URLs
    final audioFormats = adaptiveFormats.where((f) {
      final mime = f['mimeType'] as String? ?? '';
      return mime.startsWith('audio/') && f.containsKey('url');
    }).toList();

    if (audioFormats.isEmpty) return null;

    // Sort by bitrate descending
    audioFormats.sort((a, b) {
      final bBitrate = (b['bitrate'] as num?)?.toInt() ?? 0;
      final aBitrate = (a['bitrate'] as num?)?.toInt() ?? 0;
      return bBitrate.compareTo(aBitrate);
    });

    // Prefer AAC (audio/mp4) for 100% universal hardware decoding across Android & Apple platforms
    final selectedFormat = audioFormats.firstWhere(
      (f) => (f['mimeType'] as String? ?? '').contains('audio/mp4'),
      orElse: () => audioFormats.first,
    );

    final streamUrl = selectedFormat['url'] as String?;
    if (streamUrl == null || streamUrl.isEmpty) return null;

    final bitrate = (selectedFormat['bitrate'] as num?)?.toInt() ?? 128000;
    final mimeType = selectedFormat['mimeType'] as String? ?? 'audio/mp4';
    final contentLength = int.tryParse(selectedFormat['contentLength'] as String? ?? '');

    int? durationMs;
    final videoDetails = data['videoDetails'] as Map<String, dynamic>?;
    if (videoDetails != null && videoDetails['lengthSeconds'] != null) {
      final lenSec = int.tryParse(videoDetails['lengthSeconds'].toString());
      if (lenSec != null && lenSec > 0) {
        durationMs = lenSec * 1000;
      }
    }
    if (durationMs == null && selectedFormat['approxDurationMs'] != null) {
      durationMs = int.tryParse(selectedFormat['approxDurationMs'].toString());
    }

    return AudioStreamInfo(
      url: streamUrl,
      headers: {
        'User-Agent': clientConfig.userAgent,
      },
      bitrate: bitrate,
      mimeType: mimeType,
      contentLength: contentLength,
      durationMs: durationMs,
    );
  }

  /// BitChord-style probe to verify that the stream URL actually serves bytes
  /// with the designated headers before handing it to the player.
  Future<bool> _probeStreamUrl(String streamUrl, Map<String, String> headers) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(Uri.parse(streamUrl));
      headers.forEach((k, v) => request.headers.set(k, v));
      request.headers.set('Range', 'bytes=0-1024');

      final response = await request.close().timeout(const Duration(seconds: 4));
      final isSuccess = response.statusCode == 206 || response.statusCode == 200;
      await response.drain();
      return isSuccess;
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  void dispose() {
    _streamCache.clear();
    _videoStreamCache.clear();
    _artistDetailsCache.clear();
    _animatedArtworkCache.clear();
    _animatedArtworkDataCache.clear();
    _lyricsService.dispose();
    _cachedHomeData = null;
  }
}

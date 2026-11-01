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
import '../models/artist_item.dart';

/// Resolved audio stream data containing direct stream URL, matching User-Agent headers,
/// bitrate, and media format specifications.
class AudioStreamInfo {
  final String url;
  final Map<String, String> headers;
  final int bitrate;
  final String mimeType;
  final int? contentLength;

  const AudioStreamInfo({
    required this.url,
    required this.headers,
    required this.bitrate,
    required this.mimeType,
    this.contentLength,
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

  /// Computes SAPISIDHASH authorization header if authenticated with a Google account
  String? getSapisidHash() {
    final sapisid = _currentAccount?.sapisid;
    if (sapisid == null || sapisid.isEmpty) return null;
    final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final payload = '$timestamp $sapisid https://music.youtube.com';
    final digest = sha1.convert(utf8.encode(payload)).toString();
    return 'SAPISIDHASH ${timestamp}_$digest';
  }

  // Cached streams to prevent duplicate Innertube player requests (5 min TTL)
  final Map<String, ({AudioStreamInfo info, DateTime timestamp})> _streamCache = {};

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
    if (!refresh && _cachedHomeData != null) {
      return _cachedHomeData!;
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
          thumb = item.thumbnails.last.url;
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
          thumb = item.thumbnails.last.url;
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
          thumb = item.thumbnails.last.url;
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
                final thumb = s.thumbnails.isNotEmpty ? s.thumbnails.last.url : albumThumb;
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

  /// Fetches synchronized timed lyrics (or fallback plain lyrics) for a song.
  Future<List<LyricLine>> getLyrics(String videoId) async {
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
            thumbnailUrl: SongItem.upgradeThumbnail(thumbUrl, size: 800),
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

    // Check memory cache
    final cached = _streamCache[trimmedId];
    if (cached != null) {
      final age = DateTime.now().difference(cached.timestamp);
      if (age < const Duration(minutes: 5)) {
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

    return AudioStreamInfo(
      url: streamUrl,
      headers: {
        'User-Agent': clientConfig.userAgent,
      },
      bitrate: bitrate,
      mimeType: mimeType,
      contentLength: contentLength,
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
    _cachedHomeData = null;
  }
}

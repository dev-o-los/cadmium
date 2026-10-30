import 'dart:async';
import 'dart:io';
import 'package:dart_ytmusic_api/types.dart';
import 'package:dart_ytmusic_api/utils/traverse.dart';
import 'package:dart_ytmusic_api/yt_music.dart';
import '../models/song_item.dart';
import '../models/music_category.dart';
import '../models/home_data.dart';

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

  /// Gathers all information for the home screen:
  /// - Trending songs
  /// - Quick picks / popular tracks
  /// - Moods and moments
  /// - Diverse music genres
  Future<HomeData> getHomeData({bool refresh = false}) async {
    if (!refresh && _cachedHomeData != null) {
      return _cachedHomeData!;
    }

    if (!_isInitialized) {
      await initialize();
    }

    // Run parallel queries for maximum responsiveness
    final results = await Future.wait([
      _fetchTrendingTracks(),
      _fetchQuickPicks(),
      _fetchMoodsAndGenres(),
    ]);

    final trendingTracks = results[0] as List<SongItem>;
    final quickPicks = results[1] as List<SongItem>;
    final categories = results[2] as ({List<MusicCategory> moods, List<MusicCategory> genres});

    final homeData = HomeData(
      trendingTracks: trendingTracks,
      quickPicks: quickPicks,
      moods: categories.moods,
      genres: categories.genres,
    );

    _cachedHomeData = homeData;
    return homeData;
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
            thumbnailUrl: thumbUrl,
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

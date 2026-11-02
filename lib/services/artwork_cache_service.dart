import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song_item.dart';

/// Service dedicated to tracking songs heard by the user and permanently caching
/// their studio-master artwork to disk.
///
/// Features:
/// 1. Tracks play counts and listening frequency for every song played.
/// 2. Identifies songs that are "heard again and again" (playCount >= 2).
/// 3. Downloads and pins high-resolution artwork to local persistent storage
///    so repeat tracks load instantly with 0ms delay and zero network calls.
/// 4. Integrates with FlutterCacheManager for seamless image caching.
class ArtworkCacheService {
  static const String _prefPlayCounts = 'wavify_artwork_play_counts';
  static const String _prefArtworkMeta = 'wavify_artwork_metadata';
  static const String _dirName = 'artwork_cache';

  static final ArtworkCacheService _instance = ArtworkCacheService._internal();
  static ArtworkCacheService get instance => _instance;

  ArtworkCacheService._internal();

  final Map<String, int> _playCounts = {};
  final Map<String, String> _artworkUrlMap = {};
  final Map<String, File> _fileCache = {};
  Directory? _cacheDir;
  bool _isInitialized = false;

  bool get _isBindingInitialized {
    try {
      WidgetsBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Initializes the artwork cache directory and loads play history from SharedPreferences.
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (!_isBindingInitialized) return;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final playCountsJson = prefs.getString(_prefPlayCounts);
      if (playCountsJson != null) {
        final decoded = jsonDecode(playCountsJson) as Map<String, dynamic>;
        decoded.forEach((key, val) {
          if (val is int) _playCounts[key] = val;
        });
      }

      final metaJson = prefs.getString(_prefArtworkMeta);
      if (metaJson != null) {
        final decoded = jsonDecode(metaJson) as Map<String, dynamic>;
        decoded.forEach((key, val) {
          if (val is String) _artworkUrlMap[key] = val;
        });
      }
    } catch (_) {}

    try {
      final baseDir = await getApplicationSupportDirectory();
      _cacheDir = Directory('${baseDir.path}/$_dirName');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
    } catch (_) {}
  }

  /// Records a play for [song]. Increments play count and ensures high-res artwork
  /// is cached permanently to disk, prioritizing songs heard repeatedly.
  Future<void> recordSongPlay(SongItem song) async {
    final songId = song.id.trim();
    if (songId.isEmpty) return;

    if (!_isInitialized) {
      await init();
    }

    final newCount = (_playCounts[songId] ?? 0) + 1;
    _playCounts[songId] = newCount;

    final artworkUrl = song.highResThumbnailUrl ?? song.thumbnailUrl;
    if (artworkUrl != null && artworkUrl.isNotEmpty) {
      _artworkUrlMap[songId] = artworkUrl;
    }

    _persistMetadata();

    // In widget tests, avoid launching network downloads that block pumpAndSettle
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;

    // Trigger artwork caching to disk
    // If heard again and again (newCount >= 2), prioritize full studio master artwork
    final isRepeated = newCount >= 2;
    await cacheSongArtwork(song, forceHighRes: true, isHighPriority: isRepeated);
  }

  /// Returns how many times [songId] has been played.
  int getPlayCount(String songId) {
    return _playCounts[songId.trim()] ?? 0;
  }

  /// Returns true if [songId] has been heard repeatedly (playCount >= 2).
  bool isHeardRepeatedly(String songId) {
    return (_playCounts[songId.trim()] ?? 0) >= 2;
  }

  /// Returns a list of song IDs that have been played, ordered by frequency descending.
  List<String> getFrequentlyHeardSongIds() {
    final sorted = _playCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.map((e) => e.key).toList();
  }

  /// Returns the local cached artwork file for [songId] if it exists on disk and is non-empty.
  File? getCachedArtworkFile(String songId) {
    final cleanId = _sanitizeFilename(songId);
    if (_fileCache.containsKey(cleanId)) {
      final f = _fileCache[cleanId]!;
      if (f.existsSync() && f.lengthSync() > 0) return f;
    }

    if (_cacheDir == null) return null;
    final file = File('${_cacheDir!.path}/$cleanId.jpg');
    if (file.existsSync() && file.lengthSync() > 0) {
      _fileCache[cleanId] = file;
      return file;
    }

    return null;
  }

  /// Asynchronously downloads and pins high-resolution artwork for [song].
  Future<File?> cacheSongArtwork(
    SongItem song, {
    bool forceHighRes = true,
    bool isHighPriority = false,
  }) async {
    final songId = song.id.trim();
    if (songId.isEmpty) return null;

    final existing = getCachedArtworkFile(songId);
    if (existing != null) {
      return existing;
    }

    final rawUrl = forceHighRes
        ? (song.highResThumbnailUrl ?? song.thumbnailUrl)
        : song.thumbnailUrl;

    if (rawUrl == null || rawUrl.isEmpty) return null;

    final targetUrl = SongItem.upgradeThumbnail(rawUrl, size: 1800, quality: 100) ?? rawUrl;

    try {
      if (_cacheDir == null) {
        await init();
      }
      if (_cacheDir == null) return null;

      final cleanId = _sanitizeFilename(songId);
      final destFile = File('${_cacheDir!.path}/$cleanId.jpg');

      // 1. Download via Flutter CacheManager (which handles caching and HTTP efficiently)
      try {
        final fileInfo = await DefaultCacheManager().downloadFile(targetUrl, key: targetUrl);
        if (await fileInfo.file.exists()) {
          final bytes = await fileInfo.file.readAsBytes();
          if (bytes.isNotEmpty) {
            await destFile.writeAsBytes(bytes, flush: true);
            _fileCache[cleanId] = destFile;
            return destFile;
          }
        }
      } catch (_) {
        // Fallback: direct HTTP download if cache manager fails or in tests
        final file = await _downloadDirect(targetUrl, destFile);
        if (file != null) {
          _fileCache[cleanId] = file;
          return file;
        }
      }
    } catch (e) {
      debugPrint('ArtworkCacheService.cacheSongArtwork error for $songId: $e');
    }

    return null;
  }

  /// Pre-caches artwork for a batch of songs (e.g. from queue or home recents).
  Future<void> prefetchArtworks(List<SongItem> songs) async {
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;
    for (final song in songs) {
      if (getCachedArtworkFile(song.id) == null) {
        // Run unawaited so it doesn't block the UI thread
        cacheSongArtwork(song, forceHighRes: false);
      }
    }
  }

  /// Pre-fetches and warms disk/memory cache for arbitrary image URLs (e.g. artists, albums, playlists, videos).
  Future<void> prefetchImageUrls(List<String?> urls) async {
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;
    for (final url in urls) {
      if (url != null && url.trim().isNotEmpty) {
        final cleanUrl = url.trim().startsWith('//') ? 'https:${url.trim()}' : url.trim();
        try {
          unawaited(DefaultCacheManager().downloadFile(cleanUrl, key: cleanUrl));
        } catch (_) {}
      }
    }
  }

  /// Direct HTTP fetch fallback
  Future<File?> _downloadDirect(String url, File destFile) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final bytesBuilder = BytesBuilder();
        await for (final chunk in response) {
          bytesBuilder.add(chunk);
        }
        final bytes = bytesBuilder.takeBytes();
        if (bytes.isNotEmpty) {
          await destFile.writeAsBytes(bytes, flush: true);
          return destFile;
        }
      }
    } catch (_) {
    } finally {
      client?.close(force: true);
    }
    return null;
  }

  Future<void> _persistMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefPlayCounts, jsonEncode(_playCounts));
      await prefs.setString(_prefArtworkMeta, jsonEncode(_artworkUrlMap));
    } catch (_) {}
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }

  /// Clears in-memory and disk artwork cache
  Future<void> clearCache() async {
    _fileCache.clear();
    _playCounts.clear();
    _artworkUrlMap.clear();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefPlayCounts);
      await prefs.remove(_prefArtworkMeta);

      if (_cacheDir != null && await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }
    } catch (_) {}
  }
}

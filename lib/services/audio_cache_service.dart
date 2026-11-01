// ignore_for_file: experimental_member_use

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

/// Service dedicated to audio caching for the music player.
///
/// Features:
/// 1. Caches streaming audio to disk so that songs heard again and again
///    play directly from local storage with 0ms buffering and zero network load.
/// 2. Integrates with [LockCachingAudioSource] to stream and cache simultaneously.
/// 3. Automatically falls back to [AudioSource.file] if already cached,
///    or [AudioSource.uri] if streaming without local caching.
class AudioCacheService {
  static const String _dirName = 'audio_cache';

  static final AudioCacheService _instance = AudioCacheService._internal();
  static AudioCacheService get instance => _instance;

  AudioCacheService._internal();

  Directory? _cacheDir;
  bool _isInitialized = false;

  /// Initializes the audio cache directory.
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      final baseDir = await getApplicationSupportDirectory();
      _cacheDir = Directory('${baseDir.path}/$_dirName');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
    } catch (e) {
      debugPrint('AudioCacheService.init directory error (expected in tests): $e');
    }
  }

  /// Returns the local cached audio file for [songId] if it exists and has content (> 10KB).
  File? getCachedAudioFile(String songId) {
    if (_cacheDir == null) return null;
    final cleanId = _sanitizeFilename(songId);

    // Check possible audio extensions
    for (final ext in ['m4a', 'mp4', 'mp3']) {
      final file = File('${_cacheDir!.path}/$cleanId.$ext');
      if (file.existsSync() && file.lengthSync() > 10240) {
        return file;
      }
    }
    return null;
  }

  /// Returns true if [songId] is already cached on disk.
  bool isSongCached(String songId) {
    return getCachedAudioFile(songId) != null;
  }

  /// Creates the optimal [AudioSource] for [songId]:
  /// 1. If already cached on disk -> returns [AudioSource.file] for instant 0ms playback!
  /// 2. Otherwise -> returns [LockCachingAudioSource] to play and cache simultaneously,
  ///    falling back to standard [AudioSource.uri] if local caching proxy is unavailable.
  Future<AudioSource> createAudioSource(
    String songId,
    String streamUrl,
    Map<String, String> headers,
  ) async {
    if (!_isInitialized) {
      await init();
    }

    // 1. Instant local playback if file exists
    final cachedFile = getCachedAudioFile(songId);
    if (cachedFile != null) {
      debugPrint('AudioCacheService: Playing $songId from local disk cache (${cachedFile.path})');
      return AudioSource.file(cachedFile.path, tag: songId);
    }

    final targetFile = _getTargetCacheFile(songId);

    // 2. Stream and cache concurrently via LockCachingAudioSource
    if (targetFile != null) {
      try {
        return LockCachingAudioSource(
          Uri.parse(streamUrl),
          headers: headers.isNotEmpty ? headers : null,
          cacheFile: targetFile,
          tag: songId,
        );
      } catch (e) {
        debugPrint('AudioCacheService LockCachingAudioSource fallback: $e');
      }
    }

    // 3. Fallback to standard Uri source
    return AudioSource.uri(
      Uri.parse(streamUrl),
      headers: headers.isNotEmpty ? headers : null,
      tag: songId,
    );
  }

  /// Downloads audio stream in background so future plays are instant and offline-ready.
  Future<void> cacheAudioInBackground(
    String songId,
    String streamUrl,
    Map<String, String> headers,
  ) async {
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;
    if (isSongCached(songId)) return;

    final targetFile = _getTargetCacheFile(songId);
    if (targetFile == null) return;

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
      final request = await client.getUrl(Uri.parse(streamUrl));
      headers.forEach((k, v) => request.headers.set(k, v));

      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode == 200 || response.statusCode == 206) {
        final sink = targetFile.openWrite();
        await response.pipe(sink);
        await sink.flush();
        await sink.close();
      }
    } catch (_) {
      // Background cache failure is non-fatal
      if (targetFile.existsSync()) {
        try {
          targetFile.deleteSync();
        } catch (_) {}
      }
    } finally {
      client?.close(force: true);
    }
  }

  File? _getTargetCacheFile(String songId) {
    if (_cacheDir == null) return null;
    final cleanId = _sanitizeFilename(songId);
    return File('${_cacheDir!.path}/$cleanId.m4a');
  }

  String _sanitizeFilename(String name) {
    return name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }

  /// Clears audio cache
  Future<void> clearCache() async {
    try {
      if (_cacheDir != null && await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }
    } catch (_) {}
  }
}

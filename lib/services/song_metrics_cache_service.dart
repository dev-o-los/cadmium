import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song_item.dart';
import 'artwork_cache_service.dart';
import 'music_service.dart';

/// Persistent metrics and timestamp cache service for songs.
/// Caches track durations and timestamps so that slider end points, scrubbing ranges,
/// and lyrics sync markers are immediately available (0ms) when a song is opened.
class SongMetricsCacheService {
  static const String _prefKeyDurations = 'wavify_cached_song_durations';

  static final SongMetricsCacheService _instance = SongMetricsCacheService._internal();
  static SongMetricsCacheService get instance => _instance;

  SongMetricsCacheService._internal();

  final Map<String, int> _durationCache = {};
  bool _isInitialized = false;

  bool get _isBindingInitialized {
    try {
      WidgetsBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Initializes the duration cache from SharedPreferences.
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (!_isBindingInitialized) return;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefKeyDurations);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          if (value is int && value > 0) {
            _durationCache[key] = value;
          }
        });
      }
    } catch (_) {}
  }

  /// Gets the cached duration for [songId] if known.
  Duration? getDuration(String songId) {
    final cleanId = songId.trim();
    final seconds = _durationCache[cleanId];
    if (seconds != null && seconds > 0) {
      return Duration(seconds: seconds);
    }
    return null;
  }

  /// Sets and persists the duration in seconds for [songId].
  Future<void> setDuration(String songId, int durationSeconds) async {
    final cleanId = songId.trim();
    if (cleanId.isEmpty || durationSeconds <= 0) return;

    if (_durationCache[cleanId] == durationSeconds) return;
    _durationCache[cleanId] = durationSeconds;

    if (!_isBindingInitialized) return;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyDurations, jsonEncode(_durationCache));
    } catch (_) {}
  }

  /// Warms up and caches metrics (durations, high-res artwork, and stream info)
  /// for priority tracks (e.g. first 3 tracks of an album or recent feed)
  /// so that when clicked by the user, playback starts instantly with full metrics.
  void precacheTracks(List<SongItem> tracks, MusicService musicService) {
    if (tracks.isEmpty) return;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;

    // Run in background without awaiting so it doesn't block UI
    Future.microtask(() async {
      for (final track in tracks) {
        final cleanId = track.id.trim();
        if (cleanId.isEmpty) continue;

        // 1. Cache duration if known on track model
        if (track.durationSeconds != null && track.durationSeconds! > 0) {
          setDuration(cleanId, track.durationSeconds!);
        }

        // 2. Pre-cache high-resolution artwork
        ArtworkCacheService.instance.cacheSongArtwork(track, forceHighRes: true);

        // 3. Pre-resolve stream info in background if not already cached
        try {
          final streamInfo = await musicService.resolveAudioStream(cleanId);
          if (streamInfo.durationSeconds != null && streamInfo.durationSeconds! > 0) {
            setDuration(cleanId, streamInfo.durationSeconds!);
          }
        } catch (_) {}
      }
    });
  }

  /// Clears in-memory and persistent duration metrics.
  Future<void> clear() async {
    _durationCache.clear();
    if (!_isBindingInitialized) return;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKeyDurations);
    } catch (_) {}
  }
}


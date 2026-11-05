import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song_item.dart';

/// Persistent cache service for audio playback history and the last played song.
/// Ensures that when the user launches the app, the floating player above the bottom
/// navigation bar instantly displays the last heard track with artwork and metadata.
class PlayerHistoryCacheService {
  static const String _prefKeyLastSong = 'aurum_last_played_song';
  static const String _prefKeyHistory = 'aurum_playback_history';
  static const String _prefKeyQueue = 'aurum_last_queue';
  static const String _prefKeyPositionMs = 'aurum_last_position_ms';

  static final PlayerHistoryCacheService _instance =
      PlayerHistoryCacheService._internal();
  static PlayerHistoryCacheService get instance => _instance;

  PlayerHistoryCacheService._internal();

  SongItem? _lastPlayedSong;
  List<SongItem> _recentlyPlayed = [];
  List<SongItem> _lastQueue = [];
  int _lastPositionMs = 0;
  bool _isInitialized = false;

  SongItem? get lastPlayedSong => _lastPlayedSong;
  List<SongItem> get recentlyPlayed => List.unmodifiable(_recentlyPlayed);
  List<SongItem> get lastQueue => List.unmodifiable(_lastQueue);
  int get lastPositionMs => _lastPositionMs;

  bool get _isBindingInitialized {
    try {
      WidgetsBinding.instance;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Initializes and preloads playback history and the last active song from disk.
  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (!_isBindingInitialized) return;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Last played song
      final lastSongJson = prefs.getString(_prefKeyLastSong);
      if (lastSongJson != null && lastSongJson.isNotEmpty) {
        final decoded = jsonDecode(lastSongJson) as Map<String, dynamic>;
        _lastPlayedSong = SongItem.fromJson(decoded);
      }

      // 2. Playback history (recently played)
      final historyJson = prefs.getString(_prefKeyHistory);
      if (historyJson != null && historyJson.isNotEmpty) {
        final list = jsonDecode(historyJson) as List<dynamic>;
        _recentlyPlayed = list
            .map((e) => SongItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // 3. Queue
      final queueJson = prefs.getString(_prefKeyQueue);
      if (queueJson != null && queueJson.isNotEmpty) {
        final list = jsonDecode(queueJson) as List<dynamic>;
        _lastQueue = list
            .map((e) => SongItem.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // 4. Last position
      _lastPositionMs = prefs.getInt(_prefKeyPositionMs) ?? 0;
    } catch (e) {
      debugPrint('PlayerHistoryCacheService init error: $e');
    }
  }

  /// Saves the active song, updated history list, and queue to persistent storage.
  Future<void> saveLastPlayedSong(
    SongItem song, {
    List<SongItem>? history,
    List<SongItem>? queue,
    int? positionMs,
  }) async {
    _lastPlayedSong = song;

    if (history != null) {
      _recentlyPlayed = List.from(history);
    } else {
      // Automatically keep history updated with the new song at the top
      _recentlyPlayed.removeWhere((s) => s.id == song.id);
      _recentlyPlayed.insert(0, song);
      if (_recentlyPlayed.length > 50) {
        _recentlyPlayed.removeLast();
      }
    }

    if (queue != null) {
      _lastQueue = List.from(queue);
    }

    if (positionMs != null) {
      _lastPositionMs = positionMs;
    }

    if (!_isBindingInitialized) return;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyLastSong, jsonEncode(song.toJson()));
      await prefs.setString(
        _prefKeyHistory,
        jsonEncode(_recentlyPlayed.map((s) => s.toJson()).toList()),
      );
      if (queue != null) {
        await prefs.setString(
          _prefKeyQueue,
          jsonEncode(_lastQueue.map((s) => s.toJson()).toList()),
        );
      }
      if (positionMs != null) {
        await prefs.setInt(_prefKeyPositionMs, positionMs);
      }
    } catch (e) {
      debugPrint('PlayerHistoryCacheService save error: $e');
    }
  }

  /// Updates and persists the last playback position.
  Future<void> savePosition(int positionMs) async {
    _lastPositionMs = positionMs;
    if (!_isBindingInitialized) return;
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefKeyPositionMs, positionMs);
    } catch (_) {}
  }
}


import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/song_item.dart';

/// StateNotifier that persists and manages the user's favorite tracks locally on device.
class FavoritesNotifier extends StateNotifier<List<SongItem>> {
  static const _storageKey = 'wavify_favorite_songs_v1';

  FavoritesNotifier() : super(const []) {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_storageKey);
      if (list != null && list.isNotEmpty) {
        final loaded = list
            .map((item) {
              try {
                return SongItem.fromJson(jsonDecode(item) as Map<String, dynamic>);
              } catch (_) {
                return null;
              }
            })
            .whereType<SongItem>()
            .toList();
        state = loaded;
      }
    } catch (e) {
      debugPrint('Error loading local favorites: $e');
    }
  }

  bool isFavorite(String songId) {
    return state.any((song) => song.id == songId);
  }

  Future<bool> toggleFavorite(SongItem song) async {
    final exists = isFavorite(song.id);
    List<SongItem> updated;
    if (exists) {
      updated = state.where((s) => s.id != song.id).toList();
    } else {
      updated = [song, ...state];
    }
    state = updated;

    try {
      final prefs = await SharedPreferences.getInstance();
      final list = updated.map((s) => jsonEncode(s.toJson())).toList();
      await prefs.setStringList(_storageKey, list);
    } catch (e) {
      debugPrint('Error saving local favorites: $e');
    }

    return !exists;
  }

  Future<void> removeFavorite(String songId) async {
    final updated = state.where((s) => s.id != songId).toList();
    state = updated;

    try {
      final prefs = await SharedPreferences.getInstance();
      final list = updated.map((s) => jsonEncode(s.toJson())).toList();
      await prefs.setStringList(_storageKey, list);
    } catch (e) {
      debugPrint('Error removing local favorite: $e');
    }
  }
}

/// Global Riverpod provider for locally stored favorite songs.
final favoritesProvider = StateNotifierProvider<FavoritesNotifier, List<SongItem>>((ref) {
  return FavoritesNotifier();
});


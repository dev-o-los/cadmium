import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/album_item.dart';
import '../models/artist_item.dart';
import '../models/playlist_item.dart';
import '../models/song_item.dart';
import '../services/music_service.dart';
import 'auth_provider.dart';
import 'music_service_provider.dart';

// ============================================================================
// SAVED PLAYLISTS NOTIFIER
// ============================================================================

class SavedPlaylistsNotifier extends StateNotifier<List<PlaylistItem>> {
  static const _storageKey = 'wavify_saved_playlists_v1';

  SavedPlaylistsNotifier() : super(const []) {
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_storageKey);
      if (list != null && list.isNotEmpty) {
        final loaded = list
            .map((item) {
              try {
                return PlaylistItem.fromJson(
                    jsonDecode(item) as Map<String, dynamic>);
              } catch (_) {
                return null;
              }
            })
            .whereType<PlaylistItem>()
            .toList();
        state = loaded;
      } else {
        // Default initial curated playlists to get the user started
        state = const [
          PlaylistItem(
            id: 'RDCLAK5uy_kmPRjFGNQStVPkuDY27sopV4JyQuqJEe0',
            title: "Today's Hits",
            author: 'YouTube Music',
            thumbnailUrl:
                'https://lh3.googleusercontent.com/tYt6t70r1T0o67-tG8xG3tE4z0Q-2E0x1_f1=w800-h800-l90-rj',
            trackCount: 50,
          ),
          PlaylistItem(
            id: 'RDCLAK5uy_kLWShQgtRacM0nqzLTB3-AQaeS6eLactI',
            title: 'Chill Lo-Fi Vibes',
            author: 'YouTube Music',
            thumbnailUrl:
                'https://lh3.googleusercontent.com/9n7N4Wz2vQ_W48P0Z0x1_f1=w800-h800-l90-rj',
            trackCount: 45,
          ),
        ];
      }
    } catch (e) {
      debugPrint('Error loading saved playlists: $e');
    }
  }

  bool isPlaylistSaved(String playlistId) {
    return state.any((p) => p.id == playlistId);
  }

  Future<void> addPlaylist(PlaylistItem playlist) async {
    if (isPlaylistSaved(playlist.id)) return;
    final updated = [playlist, ...state];
    state = updated;
    await _persist(updated);
  }

  Future<void> removePlaylist(String playlistId) async {
    final updated = state.where((p) => p.id != playlistId).toList();
    state = updated;
    await _persist(updated);
  }

  Future<void> _persist(List<PlaylistItem> playlists) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = playlists.map((p) => jsonEncode(p.toJson())).toList();
      await prefs.setStringList(_storageKey, list);
    } catch (e) {
      debugPrint('Error persisting playlists: $e');
    }
  }
}

final savedPlaylistsProvider =
    StateNotifierProvider<SavedPlaylistsNotifier, List<PlaylistItem>>((ref) {
  return SavedPlaylistsNotifier();
});

// ============================================================================
// SAVED ALBUMS NOTIFIER
// ============================================================================

class SavedAlbumsNotifier extends StateNotifier<List<AlbumItem>> {
  static const _storageKey = 'wavify_saved_albums_v1';

  SavedAlbumsNotifier() : super(const []) {
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_storageKey);
      if (list != null && list.isNotEmpty) {
        final loaded = list
            .map((item) {
              try {
                return AlbumItem.fromJson(
                    jsonDecode(item) as Map<String, dynamic>);
              } catch (_) {
                return null;
              }
            })
            .whereType<AlbumItem>()
            .toList();
        state = loaded;
      } else {
        // Initial popular albums
        state = const [
          AlbumItem(
            id: 'MPREb_kYVnBwDqgB9',
            title: 'Starboy',
            artist: 'The Weeknd',
            type: 'Album',
            year: 2016,
            thumbnailUrl:
                'https://lh3.googleusercontent.com/s6_19N3N1z=w800-h800-l90-rj',
          ),
          AlbumItem(
            id: 'MPREb_V75Wk7DqM2a',
            title: 'After Hours',
            artist: 'The Weeknd',
            type: 'Album',
            year: 2020,
            thumbnailUrl:
                'https://lh3.googleusercontent.com/s4_90Q2N1z=w800-h800-l90-rj',
          ),
        ];
      }
    } catch (e) {
      debugPrint('Error loading saved albums: $e');
    }
  }

  bool isAlbumSaved(String albumId) {
    return state.any((a) => a.id == albumId);
  }

  Future<bool> toggleAlbum(AlbumItem album) async {
    final exists = isAlbumSaved(album.id);
    List<AlbumItem> updated;
    if (exists) {
      updated = state.where((a) => a.id != album.id).toList();
    } else {
      updated = [album, ...state];
    }
    state = updated;
    await _persist(updated);
    return !exists;
  }

  Future<void> removeAlbum(String albumId) async {
    final updated = state.where((a) => a.id != albumId).toList();
    state = updated;
    await _persist(updated);
  }

  Future<void> _persist(List<AlbumItem> albums) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = albums.map((a) => jsonEncode(a.toJson())).toList();
      await prefs.setStringList(_storageKey, list);
    } catch (e) {
      debugPrint('Error persisting albums: $e');
    }
  }
}

final savedAlbumsProvider =
    StateNotifierProvider<SavedAlbumsNotifier, List<AlbumItem>>((ref) {
  return SavedAlbumsNotifier();
});

// ============================================================================
// SAVED ARTISTS NOTIFIER
// ============================================================================

class SavedArtistsNotifier extends StateNotifier<List<ArtistItem>> {
  static const _storageKey = 'wavify_saved_artists_v1';

  SavedArtistsNotifier() : super(const []) {
    _loadArtists();
  }

  Future<void> _loadArtists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_storageKey);
      if (list != null && list.isNotEmpty) {
        final loaded = list
            .map((item) {
              try {
                return ArtistItem.fromJson(
                    jsonDecode(item) as Map<String, dynamic>);
              } catch (_) {
                return null;
              }
            })
            .whereType<ArtistItem>()
            .toList();
        state = loaded;
      } else {
        // Initial popular artists
        state = const [
          ArtistItem(
            id: 'UC0WP5P-ufpRfjbNrmOWwLBQ',
            name: 'The Weeknd',
            subscribers: '34M subscribers',
            thumbnailUrl:
                'https://lh3.googleusercontent.com/artist_weeknd=w800-h800-l90-rj',
          ),
          ArtistItem(
            id: 'UCqECaJ8Gagnn7YCbPEzWH6g',
            name: 'Taylor Swift',
            subscribers: '58M subscribers',
            thumbnailUrl:
                'https://lh3.googleusercontent.com/artist_taylor=w800-h800-l90-rj',
          ),
        ];
      }
    } catch (e) {
      debugPrint('Error loading saved artists: $e');
    }
  }

  bool isArtistSaved(String artistId) {
    return state.any((a) => a.id == artistId);
  }

  Future<bool> toggleArtist(ArtistItem artist) async {
    final exists = isArtistSaved(artist.id);
    List<ArtistItem> updated;
    if (exists) {
      updated = state.where((a) => a.id != artist.id).toList();
    } else {
      updated = [artist, ...state];
    }
    state = updated;
    await _persist(updated);
    return !exists;
  }

  Future<void> removeArtist(String artistId) async {
    final updated = state.where((a) => a.id != artistId).toList();
    state = updated;
    await _persist(updated);
  }

  Future<void> _persist(List<ArtistItem> artists) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = artists.map((a) => jsonEncode(a.toJson())).toList();
      await prefs.setStringList(_storageKey, list);
    } catch (e) {
      debugPrint('Error persisting artists: $e');
    }
  }
}

final savedArtistsProvider =
    StateNotifierProvider<SavedArtistsNotifier, List<ArtistItem>>((ref) {
  return SavedArtistsNotifier();
});

// ============================================================================
// YOUTUBE MUSIC LIKED SONGS & MIXES
// ============================================================================

class YouTubeLikedSongsNotifier extends StateNotifier<AsyncValue<List<SongItem>>> {
  final MusicService _musicService;
  final Ref _ref;

  YouTubeLikedSongsNotifier(this._musicService, this._ref)
      : super(const AsyncValue.data([])) {
    _init();
  }

  void _init() {
    _ref.listen(authProvider, (previous, next) {
      if (next != null) {
        fetchLikedSongs();
      } else {
        state = const AsyncValue.data([]);
      }
    });

    final current = _ref.read(authProvider);
    if (current != null) {
      fetchLikedSongs();
    }
  }

  Future<void> fetchLikedSongs() async {
    state = const AsyncValue.loading();
    try {
      final songs = await _musicService.getLikedSongs();
      state = AsyncValue.data(songs);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

final youtubeLikedSongsProvider = StateNotifierProvider<
    YouTubeLikedSongsNotifier, AsyncValue<List<SongItem>>>((ref) {
  final musicService = ref.watch(musicServiceProvider);
  return YouTubeLikedSongsNotifier(musicService, ref);
});


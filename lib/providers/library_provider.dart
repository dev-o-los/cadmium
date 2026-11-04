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

const _defaultCuratedPlaylists = [
  PlaylistItem(
    id: 'RDCLAK5uy_kmPRjFGNQStVPkuDY27sopV4JyQuqJEe0',
    title: "Today's Hits",
    author: 'YouTube Music',
    thumbnailUrl:
        'https://yt3.googleusercontent.com/CxEICEsjmiUDkCuUGmI0RKJ9mvuGDfSqi2rpNwokFXLBj4AcjoAByJu4nZr-I5BrL160Rw-kOxE=s800',
    trackCount: 50,
  ),
  PlaylistItem(
    id: 'RDCLAK5uy_kLWShQgtRacM0nqzLTB3-AQaeS6eLactI',
    title: 'Chill Lo-Fi Vibes',
    author: 'YouTube Music',
    thumbnailUrl:
        'https://yt3.googleusercontent.com/9n7N4Wz2vQ_W48P0Z0x1_f1=s800',
    trackCount: 45,
  ),
];

const _defaultCuratedAlbums = [
  AlbumItem(
    id: 'MPREb_FWIMEPTHFsY',
    title: 'Starboy',
    artist: 'The Weeknd',
    type: 'Album',
    year: 2016,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/dcxXIIlest09vnvKznWM9VWQXu1EL7lKxBzXGzwgmVjmMNBm1dEWT_0qn1xrEZYyKF_qRE1TLq8P_JY_mQ=w800-h800-l90-rj',
  ),
  AlbumItem(
    id: 'MPREb_V75Wk7DqM2a',
    title: 'After Hours',
    artist: 'The Weeknd',
    type: 'Album',
    year: 2020,
    thumbnailUrl:
        'https://yt3.googleusercontent.com/JDKz3Anlyo49xBhFcFx13QD_Tk4-kqdiYTo15gtkL93nE8biWyZ7o0BPyW6RnXVxcXaJ5DgU5nJ_0NjJ=w800-h800-l90-rj',
  ),
];

const _defaultCuratedArtists = [
  ArtistItem(
    id: 'UC0WP5P-ufpRfjbNrmOWwLBQ',
    name: 'The Weeknd',
    subscribers: '34M subscribers',
    thumbnailUrl:
        'https://lh3.googleusercontent.com/U-SAmNOu4TynE818gLCfKsuHZ0U5YNEtO9mrjSI9WCCKERs98LzrCal5kajBBTQNwdcisoB2Bn-pHp4=w800-h800-p-l90-rj',
  ),
  ArtistItem(
    id: 'UCqECaJ8Gagnn7YCbPEzWH6g',
    name: 'Taylor Swift',
    subscribers: '58M subscribers',
    thumbnailUrl:
        'https://yt3.googleusercontent.com/DU6Kpr5TYKcW6QHvMnsJau5_8QSuix8LCLtf5UEaziZZdXw8SxvcxJ9YWmVIQuzhg2R-MVHYgjdGCQ=w800-h800-p-l90-rj',
  ),
];

// ============================================================================
// SAVED PLAYLISTS NOTIFIER (Local persistence)
// ============================================================================

class SavedPlaylistsNotifier extends StateNotifier<List<PlaylistItem>> {
  static const _storageKey = 'wavify_saved_playlists_v1';

  SavedPlaylistsNotifier() : super(_defaultCuratedPlaylists) {
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

  void updatePlaylistThumbnail(String playlistId, String thumbnailUrl) {
    state = [
      for (final p in state)
        if (p.id == playlistId)
          PlaylistItem(
            id: p.id,
            title: p.title,
            author: p.author,
            thumbnailUrl: thumbnailUrl,
            trackCount: p.trackCount,
            isCustom: p.isCustom,
          )
        else
          p,
    ];
    _persist(state);
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
// SAVED ALBUMS NOTIFIER (Local persistence)
// ============================================================================

class SavedAlbumsNotifier extends StateNotifier<List<AlbumItem>> {
  static const _storageKey = 'wavify_saved_albums_v1';

  SavedAlbumsNotifier() : super(_defaultCuratedAlbums) {
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
      updated = [album.copyWith(isCustom: true), ...state];
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

  void updateAlbumThumbnail(String albumId, String thumbnailUrl) {
    state = [
      for (final album in state)
        if (album.id == albumId)
          album.copyWith(thumbnailUrl: thumbnailUrl)
        else
          album,
    ];
    _persist(state);
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
// SAVED ARTISTS NOTIFIER (Local persistence)
// ============================================================================

class SavedArtistsNotifier extends StateNotifier<List<ArtistItem>> {
  static const _storageKey = 'wavify_saved_artists_v1';

  SavedArtistsNotifier() : super(_defaultCuratedArtists) {
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
      updated = [artist.copyWith(isCustom: true), ...state];
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

  void updateArtistThumbnail(String artistId, String thumbnailUrl) {
    state = [
      for (final a in state)
        if (a.id == artistId)
          a.copyWith(thumbnailUrl: thumbnailUrl)
        else
          a,
    ];
    _persist(state);
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
// YOUTUBE MUSIC LIKED SONGS NOTIFIER
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

  void addLikedSong(SongItem song) {
    final current = state.value ?? [];
    if (!current.any((s) => s.id == song.id)) {
      state = AsyncValue.data([song, ...current]);
    }
  }

  void removeLikedSong(String songId) {
    final current = state.value ?? [];
    state = AsyncValue.data(current.where((s) => s.id != songId).toList());
  }

  void setLikedSongs(List<SongItem> songs) {
    state = AsyncValue.data(songs);
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

// ============================================================================
// USER-SPECIFIC LIBRARY PROVIDERS
// When logged in: returns ONLY the user's specific account items & custom favorites.
// When logged out: returns the local starter/curated collection.
// ============================================================================

/// Resolves playlists for the Library tab:
/// - Logged out: Local saved & starter playlists.
/// - Logged in: ONLY the user's own YouTube Music account playlists and custom saved playlists.
final userPlaylistsProvider = FutureProvider<List<PlaylistItem>>((ref) async {
  final account = ref.watch(authProvider);
  final localSaved = ref.watch(savedPlaylistsProvider);

  if (account == null) {
    return localSaved;
  }

  final musicService = ref.watch(musicServiceProvider);
  final ytPlaylists = await musicService.getUserPlaylists();
  final customUserPlaylists = localSaved.where((p) => p.isCustom).toList();
  final ytLikes = ref.watch(youtubeLikedSongsProvider).value ?? [];

  final seen = <String>{};
  final result = <PlaylistItem>[];

  // Feature user's Liked Music playlist prominently
  seen.add('LM');
  result.add(
    PlaylistItem(
      id: 'LM',
      title: 'Liked Music',
      author: 'YouTube Music',
      thumbnailUrl: ytLikes.isNotEmpty ? ytLikes.first.thumbnailUrl : null,
      trackCount: ytLikes.length,
      isCustom: false,
    ),
  );

  for (final p in [...customUserPlaylists, ...ytPlaylists]) {
    if (!seen.contains(p.id)) {
      seen.add(p.id);
      result.add(p);
    }
  }

  return result;
});

/// Resolves albums for the Library tab:
/// - Logged out: Local saved & starter albums.
/// - Logged in: ONLY the user's own YouTube Music account albums, custom saved albums,
///   and their full collection of Liked Music presented as an album.
final userAlbumsProvider = FutureProvider<List<AlbumItem>>((ref) async {
  final account = ref.watch(authProvider);
  final localSaved = ref.watch(savedAlbumsProvider);

  if (account == null) {
    return localSaved;
  }

  final musicService = ref.watch(musicServiceProvider);
  final ytAlbums = await musicService.getUserAlbums();
  final customUserAlbums = localSaved.where((a) => a.isCustom).toList();
  final ytLikes = ref.watch(youtubeLikedSongsProvider).value ?? [];

  final seen = <String>{'LM'};
  final result = <AlbumItem>[];

  // Feature the full album of Liked Music
  if (ytLikes.isNotEmpty) {
    result.add(
      AlbumItem(
        id: 'LM',
        title: 'Liked Music',
        artist: 'YouTube Music',
        thumbnailUrl: ytLikes.first.thumbnailUrl,
        type: 'Auto Playlist',
        year: DateTime.now().year,
        isCustom: false,
      ),
    );
  }

  for (final a in [...customUserAlbums, ...ytAlbums]) {
    if (!seen.contains(a.id)) {
      seen.add(a.id);
      result.add(a);
    }
  }

  return result;
});

/// Resolves artists for the Library tab:
/// - Logged out: Local saved & starter artists.
/// - Logged in: ONLY the user's own YouTube Music account artists and custom saved artists.
final userArtistsProvider = FutureProvider<List<ArtistItem>>((ref) async {
  final account = ref.watch(authProvider);
  final localSaved = ref.watch(savedArtistsProvider);

  if (account == null) {
    return localSaved;
  }

  final musicService = ref.watch(musicServiceProvider);
  final ytArtists = await musicService.getUserArtists();
  final customUserArtists = localSaved.where((a) => a.isCustom).toList();

  final seen = <String>{};
  final result = <ArtistItem>[];

  for (final a in [...customUserArtists, ...ytArtists]) {
    if (!seen.contains(a.id)) {
      seen.add(a.id);
      result.add(a);
    }
  }

  return result;
});

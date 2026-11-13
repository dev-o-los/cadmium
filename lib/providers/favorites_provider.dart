import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/song_item.dart';
import '../models/user_account.dart';
import 'auth_provider.dart';
import 'library_provider.dart';
import 'music_service_provider.dart';

/// StateNotifier that manages the user's liked tracks directly synced with
/// their YouTube Music account, without relying on local SharedPreferences.
class FavoritesNotifier extends StateNotifier<List<SongItem>> {
  final Ref? _ref;

  FavoritesNotifier([this._ref]) : super(const []) {
    _init();
  }

  void _init() {
    if (_ref == null) return;

    // Automatically sync favorites whenever youtubeLikedSongsProvider updates
    _ref.listen<AsyncValue<List<SongItem>>>(youtubeLikedSongsProvider, (previous, next) {
      next.whenData((songs) {
        state = songs;
      });
    });

    // Clear favorites when signed out
    _ref.listen<UserAccount?>(authProvider, (previous, next) {
      if (next == null) {
        state = const [];
      }
    });

    // Initial value if already loaded
    final initialLikes = _ref.read(youtubeLikedSongsProvider).valueOrNull;
    if (initialLikes != null && initialLikes.isNotEmpty) {
      state = initialLikes;
    }
  }

  bool isFavorite(String songId) {
    return state.any((song) => song.id == songId);
  }

  Future<bool> toggleFavorite(SongItem song) async {
    final exists = isFavorite(song.id);
    final musicService = _ref?.read(musicServiceProvider);
    final account = _ref?.read(authProvider);

    if (exists) {
      // Optimistically remove from state
      state = state.where((s) => s.id != song.id).toList();
      _ref?.read(youtubeLikedSongsProvider.notifier).removeLikedSong(song.id);

      if (account != null && musicService != null) {
        musicService.unlikeSong(song.id);
      }
      return false;
    } else {
      // Optimistically add to state
      state = [song, ...state];
      _ref?.read(youtubeLikedSongsProvider.notifier).addLikedSong(song);

      if (account != null && musicService != null) {
        musicService.likeSong(song.id);
      }
      return true;
    }
  }

  Future<void> removeFavorite(String songId) async {
    state = state.where((s) => s.id != songId).toList();
    _ref?.read(youtubeLikedSongsProvider.notifier).removeLikedSong(songId);

    final musicService = _ref?.read(musicServiceProvider);
    final account = _ref?.read(authProvider);
    if (account != null && musicService != null) {
      musicService.unlikeSong(songId);
    }
  }
}

/// Global Riverpod provider for user's favorite tracks.
final favoritesProvider = StateNotifierProvider<FavoritesNotifier, List<SongItem>>((ref) {
  return FavoritesNotifier(ref);
});

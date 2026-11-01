import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/album_item.dart';
import '../models/artist_item.dart';
import '../models/hero_card_item.dart';
import '../models/playlist_item.dart';
import '../models/song_item.dart';
import '../providers/music_service_provider.dart';
import '../providers/player_provider.dart';
import '../screens/album_screen.dart';
import '../screens/artist_screen.dart';
import '../screens/player_screen.dart';

/// Shows a floating dark Apple Music-style snackbar with the provided message.
void showWavifySnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: AppColors.appleDarkSurfaceHigh,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

/// Opens the full-screen modal [PlayerScreen] extending behind the status bar.
void openPlayerScreen(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    builder: (context) => const PlayerScreen(),
  );
}

/// Opens the dedicated full-page [AlbumScreen] with ambient artwork blur, metadata, and tracklist.
void openAlbumScreen(BuildContext context, AlbumItem album) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => AlbumScreen(album: album),
    ),
  );
}

/// Opens the dedicated full-page [ArtistScreen] with ambient hero banner, top songs,
/// albums, singles, videos, playlists, similar artists, and Apple-styled biography stats.
void openArtistScreen(
  BuildContext context, {
  String? artistId,
  String? artistName,
  String? thumbnailUrl,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => ArtistScreen(
        artistId: artistId,
        artistName: artistName,
        initialThumbnailUrl: thumbnailUrl,
      ),
    ),
  );
}

/// Plays a song using [playerProvider] and optionally opens the player modal.
void playSong(
  BuildContext context,
  WidgetRef ref,
  SongItem song, {
  List<SongItem>? contextQueue,
  bool autoOpenPlayer = false,
  bool forceReload = false,
}) {
  ref.read(playerProvider.notifier).playSong(
        song,
        contextQueue: contextQueue,
        forceReload: forceReload,
      );
  if (autoOpenPlayer) {
    openPlayerScreen(context);
  }
}

/// Directly opens the player screen with instant optimistic feedback, then resolves
/// and plays the album tracks from YouTube Music.
Future<void> playAlbumOrSingle(
  BuildContext context,
  WidgetRef ref,
  AlbumItem album,
) async {
  openPlayerScreen(context);

  final placeholder = SongItem(
    id: 'album_${album.id}',
    title: album.title,
    artist: album.artist,
    thumbnailUrl: album.thumbnailUrl,
    album: album.title,
  );
  ref.read(playerProvider.notifier).prepareSong(placeholder);

  try {
    final musicService = ref.read(musicServiceProvider);
    final tracks = await musicService.getAlbumSongs(
      album.id,
      queryFallback: '${album.title} ${album.artist}',
    );

    if (tracks.isNotEmpty) {
      final firstTrack = tracks.first;
      final queue = tracks.length > 1 ? tracks.sublist(1) : <SongItem>[];
      ref.read(playerProvider.notifier).playSong(
            firstTrack,
            contextQueue: queue,
            forceReload: true,
          );
    } else {
      if (context.mounted) {
        showWavifySnackBar(context, 'No playable tracks found for "${album.title}"');
      }
    }
  } catch (e) {
    if (context.mounted) {
      showWavifySnackBar(context, 'Unable to load "${album.title}": $e');
    }
  }
}

/// Directly opens the player screen and plays the hero item's tracks.
Future<void> playHero(
  BuildContext context,
  WidgetRef ref,
  HeroCardItem hero,
) async {
  openPlayerScreen(context);

  final placeholder = SongItem(
    id: 'hero_${hero.id}',
    title: hero.title,
    artist: hero.subtitle.isNotEmpty ? hero.subtitle : hero.caption,
    thumbnailUrl: hero.imageUrl,
  );
  ref.read(playerProvider.notifier).prepareSong(placeholder);

  try {
    final musicService = ref.read(musicServiceProvider);
    final tracks = await musicService.searchSongs(hero.title);

    if (tracks.isNotEmpty) {
      final firstTrack = tracks.first;
      final queue = tracks.length > 1 ? tracks.sublist(1) : <SongItem>[];
      ref.read(playerProvider.notifier).playSong(
            firstTrack,
            contextQueue: queue,
            forceReload: true,
          );
    } else {
      if (context.mounted) {
        showWavifySnackBar(context, 'No tracks found for "${hero.title}"');
      }
    }
  } catch (e) {
    if (context.mounted) {
      showWavifySnackBar(context, 'Unable to play "${hero.title}": $e');
    }
  }
}

/// Directly opens the player screen and streams the playlist tracks.
Future<void> playPlaylist(
  BuildContext context,
  WidgetRef ref,
  PlaylistItem playlist,
) async {
  openPlayerScreen(context);

  final placeholder = SongItem(
    id: 'playlist_${playlist.id}',
    title: playlist.title,
    artist: playlist.author,
    thumbnailUrl: playlist.thumbnailUrl,
    album: playlist.title,
  );
  ref.read(playerProvider.notifier).prepareSong(placeholder);

  try {
    final musicService = ref.read(musicServiceProvider);
    final tracks = await musicService.getPlaylistTracks(
      playlist.id,
      queryFallback: '${playlist.title} ${playlist.author}',
    );

    if (tracks.isNotEmpty) {
      final firstTrack = tracks.first;
      final queue = tracks.length > 1 ? tracks.sublist(1) : <SongItem>[];
      ref.read(playerProvider.notifier).playSong(
            firstTrack,
            contextQueue: queue,
            forceReload: true,
          );
    } else {
      if (context.mounted) {
        showWavifySnackBar(context, 'No playable tracks found for "${playlist.title}"');
      }
    }
  } catch (e) {
    if (context.mounted) {
      showWavifySnackBar(context, 'Unable to load "${playlist.title}": $e');
    }
  }
}

/// Directly opens the player screen and streams the artist's popular tracks.
Future<void> playArtist(
  BuildContext context,
  WidgetRef ref,
  ArtistItem artist,
) async {
  openPlayerScreen(context);

  final placeholder = SongItem(
    id: 'artist_${artist.id}',
    title: artist.name,
    artist: 'Artist',
    thumbnailUrl: artist.thumbnailUrl,
  );
  ref.read(playerProvider.notifier).prepareSong(placeholder);

  try {
    final musicService = ref.read(musicServiceProvider);
    final tracks = await musicService.getArtistSongs(
      artist.id,
      artistName: artist.name,
    );

    if (tracks.isNotEmpty) {
      final firstTrack = tracks.first;
      final queue = tracks.length > 1 ? tracks.sublist(1) : <SongItem>[];
      ref.read(playerProvider.notifier).playSong(
            firstTrack,
            contextQueue: queue,
            forceReload: true,
          );
    } else {
      if (context.mounted) {
        showWavifySnackBar(context, 'No playable tracks found for "${artist.name}"');
      }
    }
  } catch (e) {
    if (context.mounted) {
      showWavifySnackBar(context, 'Unable to load "${artist.name}": $e');
    }
  }
}


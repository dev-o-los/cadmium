import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/song_item.dart';
import '../providers/favorites_provider.dart';
import '../utils/playback_utils.dart';

/// Shows the standard Apple Music 3-dots action sheet for a [SongItem].
void showTrackOptionsModal(
  BuildContext context,
  WidgetRef ref,
  SongItem song,
) {
  final isFav = ref.read(favoritesProvider.notifier).isFavorite(song.id);

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (modalContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: song.thumbnailUrl != null
                      ? Image.network(
                          song.thumbnailUrl!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _fallbackSquare(),
                        )
                      : _fallbackSquare(),
                ),
                title: Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                subtitle: GestureDetector(
                  onTap: () {
                    Navigator.pop(modalContext);
                    openArtistScreen(context, artistName: song.artist);
                  },
                  child: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.appleSecondaryText,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
              const Divider(color: Color(0xFF2C2C2E)),
              ListTile(
                leading: const Icon(
                  CupertinoIcons.person_crop_circle,
                  color: Colors.white,
                ),
                title: Text(
                  'View Artist: ${song.artist}',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(modalContext);
                  openArtistScreen(context, artistName: song.artist);
                },
              ),
              ListTile(
                leading: const Icon(
                  CupertinoIcons.text_badge_plus,
                  color: Colors.white,
                ),
                title: const Text(
                  'Play Next',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(modalContext);
                  showWavifySnackBar(context, 'Added "${song.title}" to play next');
                },
              ),
              ListTile(
                leading: const Icon(
                  CupertinoIcons.list_bullet_indent,
                  color: Colors.white,
                ),
                title: const Text(
                  'Add to Queue',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(modalContext);
                  showWavifySnackBar(context, 'Added "${song.title}" to queue');
                },
              ),
              ListTile(
                leading: Icon(
                  isFav ? CupertinoIcons.star_fill : CupertinoIcons.star,
                  color: isFav ? AppColors.appleRed : Colors.white,
                ),
                title: Text(
                  isFav ? 'Remove from Favorites' : 'Add to Favorites',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(modalContext);
                  ref.read(favoritesProvider.notifier).toggleFavorite(song);
                  showWavifySnackBar(
                    context,
                    isFav
                        ? 'Removed "${song.title}" from favorites'
                        : 'Saved "${song.title}" to favorites',
                  );
                },
              ),
              ListTile(
                leading: const Icon(CupertinoIcons.share, color: Colors.white),
                title: const Text(
                  'Share Song',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(modalContext);
                  showWavifySnackBar(context, 'Sharing link for "${song.title}"');
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _fallbackSquare() {
  return Container(
    width: 50,
    height: 50,
    color: AppColors.appleDarkSurfaceHigh,
    child: const Icon(
      CupertinoIcons.music_note,
      color: Colors.white30,
      size: 24,
    ),
  );
}


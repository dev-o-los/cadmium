import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/song_item.dart';
import '../providers/favorites_provider.dart';
import '../providers/player_provider.dart';
import '../services/lyrics_service.dart';
import '../utils/playback_utils.dart';
import 'apple_pressable.dart';
import 'wavify_cached_image.dart';

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
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (modalContext) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: song.thumbnailUrl != null
                      ? WavifyCachedImage(
                          imageUrl: song.thumbnailUrl!,
                          songId: song.id,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorWidget: _fallbackSquare(),
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
              // Sleek Apple-style Lyrics Provider switcher
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Consumer(
                  builder: (context, ref, _) {
                    final selectedProvider = ref.watch(playerProvider.select((s) => s.selectedLyricsProvider));
                    final isLoadingLyrics = ref.watch(playerProvider.select((s) => s.isLoadingLyrics));

                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(CupertinoIcons.quote_bubble, color: Colors.white, size: 20),
                            SizedBox(width: 14),
                            Text(
                              'Lyrics Provider',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.14),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildModalProviderSegment(
                                ref: ref,
                                type: LyricsProviderType.lrcRed,
                                label: 'lrc.red',
                                icon: CupertinoIcons.sparkles,
                                isSelected: selectedProvider == LyricsProviderType.lrcRed,
                                isLoading: isLoadingLyrics && selectedProvider == LyricsProviderType.lrcRed,
                              ),
                              const SizedBox(width: 2),
                              _buildModalProviderSegment(
                                ref: ref,
                                type: LyricsProviderType.youTube,
                                label: 'YouTube',
                                icon: CupertinoIcons.play_rectangle,
                                isSelected: selectedProvider == LyricsProviderType.youTube,
                                isLoading: isLoadingLyrics && selectedProvider == LyricsProviderType.youTube,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
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

Widget _buildModalProviderSegment({
  required WidgetRef ref,
  required LyricsProviderType type,
  required String label,
  required IconData icon,
  required bool isSelected,
  bool isLoading = false,
}) {
  return ApplePressable(
    onTap: () {
      if (!isSelected) {
        ref.read(playerProvider.notifier).setLyricsProvider(type);
      }
    },
    pressedScale: 0.95,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isSelected ? Colors.white : Colors.white60,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              letterSpacing: -0.2,
            ),
          ),
          if (isSelected && isLoading) ...[
            const SizedBox(width: 5),
            const CupertinoActivityIndicator(
              radius: 5,
              color: Colors.white,
            ),
          ],
        ],
      ),
    ),
  );
}


import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/song_item.dart';
import '../providers/favorites_provider.dart';
import '../providers/player_provider.dart';
import '../services/lyrics_service.dart';
import '../utils/playback_utils.dart';
import 'apple_glass_bottom_sheet.dart';
import 'apple_pressable.dart';
import 'wavify_cached_image.dart';

/// Shows the authentic Apple Music-style 3-dots action sheet for a [SongItem],
/// rendered with Liquid Glass frosted backdrop, grouped cards, and pure white typography.
void showTrackOptionsModal(
  BuildContext context,
  WidgetRef ref,
  SongItem song,
) {
  final isFav = ref.read(favoritesProvider.notifier).isFavorite(song.id);

  showAppleGlassBottomSheet(
    context: context,
    builder: (modalContext) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Track Header Card (Artwork + Title + Artist)
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: song.thumbnailUrl != null
                    ? WavifyCachedImage(
                        imageUrl: song.highResThumbnailUrl ?? song.thumbnailUrl!,
                        songId: song.id,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        errorWidget: _fallbackSquare(),
                      )
                    : _fallbackSquare(),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16.5,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(modalContext);
                        openArtistScreen(context, artistName: song.artist);
                      },
                      child: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Group 1: Sleek Apple-style Lyrics Provider switcher
          AppleSheetGroup(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            children: [
              Consumer(
                builder: (context, ref, _) {
                  final selectedProvider = ref.watch(playerProvider.select((s) => s.selectedLyricsProvider));
                  final isLoadingLyrics = ref.watch(playerProvider.select((s) => s.isLoadingLyrics));

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(CupertinoIcons.quote_bubble, color: Colors.white, size: 20),
                          SizedBox(width: 12),
                          Text(
                            'Lyrics Provider',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
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
                            const SizedBox(width: 3),
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
            ],
          ),
          const SizedBox(height: 10),

          // Group 2: Navigation & Queue Actions
          AppleSheetGroup(
            children: [
              AppleSheetActionTile(
                leading: const Icon(CupertinoIcons.person_crop_circle, color: Colors.white, size: 22),
                title: 'View Artist: ${song.artist}',
                onTap: () {
                  Navigator.pop(modalContext);
                  openArtistScreen(context, artistName: song.artist);
                },
              ),
              const AppleSheetDivider(),
              AppleSheetActionTile(
                leading: const Icon(CupertinoIcons.text_badge_plus, color: Colors.white, size: 22),
                title: 'Play Next',
                onTap: () {
                  Navigator.pop(modalContext);
                  showWavifySnackBar(context, 'Added "${song.title}" to play next');
                },
              ),
              const AppleSheetDivider(),
              AppleSheetActionTile(
                leading: const Icon(CupertinoIcons.list_bullet_indent, color: Colors.white, size: 22),
                title: 'Add to Queue',
                onTap: () {
                  Navigator.pop(modalContext);
                  showWavifySnackBar(context, 'Added "${song.title}" to queue');
                },
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Group 3: Favorites & Sharing
          AppleSheetGroup(
            children: [
              AppleSheetActionTile(
                leading: Icon(
                  isFav ? CupertinoIcons.star_fill : CupertinoIcons.star,
                  color: isFav ? AppColors.appleRed : Colors.white,
                  size: 22,
                ),
                title: isFav ? 'Remove from Favorites' : 'Add to Favorites',
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
              const AppleSheetDivider(),
              AppleSheetActionTile(
                leading: const Icon(CupertinoIcons.share, color: Colors.white, size: 22),
                title: 'Share Song',
                onTap: () {
                  Navigator.pop(modalContext);
                  showWavifySnackBar(context, 'Sharing link for "${song.title}"');
                },
              ),
            ],
          ),
        ],
      );
    },
  );
}

Widget _fallbackSquare() {
  return Container(
    width: 52,
    height: 52,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: const Icon(
      CupertinoIcons.music_note,
      color: Colors.white70,
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
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? Colors.white.withValues(alpha: 0.28) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
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
            color: Colors.white,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
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

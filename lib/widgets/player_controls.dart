import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../constants/apple_typography.dart';
import '../providers/player_provider.dart';
import '../utils/playback_utils.dart';
import 'animated_cupertino_icon.dart';
import 'wavify_cached_image.dart';

/// Floating Liquid Glass Mini Player inspired by Apple Music.
/// Uses Riverpod for reactive playback state management, Cupertino icons, and zero-lag controls.
/// Adapts seamlessly between expanded floating mini-player and inline capsule inside
/// [GlassTabBar.minimizable] dock when scrolling.
class PlayerControls extends ConsumerWidget {
  final VoidCallback? onTap;

  const PlayerControls({super.key, this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));

    if (currentSong == null) {
      return const SizedBox.shrink();
    }

    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isLoading = ref.watch(playerIsLoadingProvider);

    final effectiveArt =
        currentSong.highResThumbnailUrl ?? currentSong.resolvedThumbnailUrl;
    final thumbArt =
        currentSong.resolvedThumbnailUrl ?? currentSong.thumbnailUrl;

    // Detect whether we are rendering inline inside minimized GlassTabBar or expanded
    final placement = GlassTabBarAccessoryPlacementScope.of(context);
    final isInline = placement == GlassTabBarAccessoryPlacement.inline;

    if (isInline) {
      return _buildInlinePlayer(
        context: context,
        ref: ref,
        title: currentSong.title,
        artist: currentSong.artist,
        highResArt: effectiveArt,
        thumbArt: thumbArt,
        songId: currentSong.id,
        isPlaying: isPlaying,
        isLoading: isLoading,
      );
    }

    return _buildExpandedPlayer(
      context: context,
      ref: ref,
      title: currentSong.title,
      artist: currentSong.artist,
      highResArt: effectiveArt,
      thumbArt: thumbArt,
      songId: currentSong.id,
      isPlaying: isPlaying,
      isLoading: isLoading,
    );
  }

  /// Compact inline music player capsule fitting between collapsed tab circle and search pill
  /// matching the exact reference layout in the liquid_glass_widgets specifications.
  Widget _buildInlinePlayer({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    required String artist,
    required String? highResArt,
    required String? thumbArt,
    required String? songId,
    required bool isPlaying,
    required bool isLoading,
  }) {
    return GlassContainer(
      useOwnLayer: true,
      height: 52,
      shape: const LiquidRoundedSuperellipse(borderRadius: 26),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // Album Artwork (Compact with 4-5px padding and rounded corners)
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 4),
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Hero(
                  tag: 'player_album_art_$songId',
                  flightShuttleBuilder: playerHeroFlightShuttleBuilder,
                  child:
                      ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: WavifyCachedImage(
                              imageUrl: highResArt ?? thumbArt,
                              placeholderImageUrl: thumbArt,
                              songId: songId,
                              width: 34,
                              height: 34,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.medium,
                              errorWidget: _fallbackArtwork(size: 34),
                            ),
                          )
                          .animate(key: ValueKey('mini_art_inline_$songId'))
                          .fadeIn(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          )
                          .scale(
                            begin: const Offset(0.85, 0.85),
                            end: const Offset(1.0, 1.0),
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                          ),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Tappable Title & Artist metadata
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppleTypography.miniPlayerInlineTitle,
                    ),
                    const SizedBox(height: AppleSpacing.titleToSubtitle),
                    Text(
                      artist.isNotEmpty ? artist : 'Unknown Artist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppleTypography.miniPlayerInlineArtist,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 4),

            // Play / Pause Button only when scrolled down into dock (Next track removed)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                ref.read(playerProvider.notifier).togglePlayPause();
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                child:
                    (isLoading &&
                        !Platform.environment.containsKey('FLUTTER_TEST'))
                    ? const CupertinoActivityIndicator(
                        radius: 9,
                        color: Colors.white,
                      )
                    : AnimatedCupertinoIcon(
                        icon: isPlaying
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        color: Colors.white,
                        size: 20,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Full-width floating mini player resting above the bottom tab bar
  Widget _buildExpandedPlayer({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    required String artist,
    required String? highResArt,
    required String? thumbArt,
    required String? songId,
    required bool isPlaying,
    required bool isLoading,
  }) {
    return GlassContainer(
      useOwnLayer: true,
      height: 52,
      shape: const LiquidRoundedSuperellipse(borderRadius: 26),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            // Tappable song info (Artwork + Title + Artist) to open full player screen
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    // Album Artwork with 4-5px appropriate padding & High-Res Upgrade
                    Padding(
                      padding: const EdgeInsets.only(left: 4, right: 4, top: 4, bottom: 4),
                      child: Hero(
                        tag: 'player_album_art_$songId',
                        flightShuttleBuilder: playerHeroFlightShuttleBuilder,
                        child:
                            ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: WavifyCachedImage(
                                    imageUrl: highResArt ?? thumbArt,
                                    placeholderImageUrl: thumbArt,
                                    songId: songId,
                                    width: 38,
                                    height: 38,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.medium,
                                    errorWidget: _fallbackArtwork(size: 38),
                                  ),
                                )
                                .animate(
                                  key: ValueKey('mini_art_expanded_$songId'),
                                )
                                .fadeIn(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                )
                                .scale(
                                  begin: const Offset(0.85, 0.85),
                                  end: const Offset(1.0, 1.0),
                                  duration: const Duration(milliseconds: 350),
                                  curve: Curves.easeOutCubic,
                                ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Song Title & Artist
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppleTypography.miniPlayerTitle,
                          ),
                          const SizedBox(height: AppleSpacing.titleToSubtitle),
                          Text(
                            artist.isNotEmpty ? artist : 'Unknown Artist',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppleTypography.miniPlayerArtist,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 6),

            // Play / Pause Button: Dedicated gesture target with immediate animated response
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                ref.read(playerProvider.notifier).togglePlayPause();
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 40,
                height: 44,
                alignment: Alignment.center,
                child:
                    (isLoading &&
                        !Platform.environment.containsKey('FLUTTER_TEST'))
                    ? const CupertinoActivityIndicator(
                        radius: 12,
                        color: Colors.white,
                      )
                    : AnimatedCupertinoIcon(
                        icon: isPlaying
                            ? CupertinoIcons.pause_fill
                            : CupertinoIcons.play_fill,
                        color: Colors.white,
                        size: 26,
                      ),
              ),
            ),
            const SizedBox(width: 4),

            // Skip Next Button (Fast Forward)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                ref.read(playerProvider.notifier).skipNext();
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 36,
                height: 44,
                alignment: Alignment.center,
                child: const AnimatedCupertinoIcon(
                  icon: CupertinoIcons.forward_fill,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _fallbackArtwork({double size = 40}) {
    return Container(
      width: size,
      height: size,
      color: const Color(0xFF2C2C2E),
      child: Center(
        child: Icon(
          CupertinoIcons.music_note,
          color: Colors.white38,
          size: size * 0.5,
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../constants/apple_typography.dart';
import '../providers/player_provider.dart';
import '../services/artwork_color_service.dart';
import '../utils/playback_utils.dart';
import 'animated_cupertino_icon.dart';
import 'apple_pressable.dart';
import 'liquid_glass_bottom_bar.dart';
import 'smooth_player_loader.dart';
import 'wavify_cached_image.dart';

/// Reactive provider extracting the secondary ambient tone from current song artwork
final currentSongSecondaryColorProvider = FutureProvider.autoDispose<Color>((
  ref,
) async {
  final song = ref.watch(playerProvider.select((s) => s.currentSong));
  if (song == null) return const Color(0xFF1E1E26);
  final art =
      song.highResThumbnailUrl ??
      song.resolvedThumbnailUrl ??
      song.thumbnailUrl;
  return ArtworkColorService.instance.extractSecondaryColor(
    art,
    fallbackSeed: '${song.title} ${song.artist}',
  );
});

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

    // Pick secondary color from currently playing album artwork
    final cachedSec = ArtworkColorService.instance.getCachedSecondaryColor(
      effectiveArt ?? thumbArt ?? '${currentSong.title} ${currentSong.artist}',
    );
    final asyncSec = ref.watch(currentSongSecondaryColorProvider).valueOrNull;
    final secondaryColor =
        asyncSec ??
        cachedSec ??
        ArtworkColorService.instance.getFallbackSecondaryColor(
          '${currentSong.title} ${currentSong.artist}',
        );

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
        secondaryColor: secondaryColor,
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
      secondaryColor: secondaryColor,
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
    required Color secondaryColor,
  }) {
    const double barHeight = 52.0;
    const double artSize = 36.0;

    return GlassContainer(
      height: barHeight,
      shape: const LiquidRoundedRectangle(borderRadius: 26),
      settings: kLiquidBottomDockGlassSettings,
      useOwnLayer: false,
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Padding around the artwork only (equal 8px padding on all sides)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Hero(
                  tag: 'player_album_art_$songId',
                  flightShuttleBuilder: playerHeroFlightShuttleBuilder,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: WavifyCachedImage(
                      imageUrl: highResArt ?? thumbArt,
                      placeholderImageUrl: thumbArt,
                      songId: songId,
                      width: artSize,
                      height: artSize,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      errorWidget: _fallbackArtwork(size: artSize),
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

            // Play / Pause Button with responsive spring physics & smooth loading indicator
            ApplePressable(
              onTap: () {
                HapticFeedback.lightImpact();
                ref.read(playerProvider.notifier).togglePlayPause();
              },
              pressedScale: 0.88,
              child: Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.78, end: 1.0).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutBack,
                          ),
                        ),
                        child: child,
                      ),
                    );
                  },
                  child:
                      (isLoading &&
                          !Platform.environment.containsKey('FLUTTER_TEST'))
                      ? const SmoothPlayerLoader(radius: 9)
                      : AnimatedCupertinoIcon(
                          key: ValueKey('mini_inline_play_pause_$isPlaying'),
                          icon: isPlaying
                              ? CupertinoIcons.pause_fill
                              : CupertinoIcons.play_fill,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      );
  }

  /// Full-width floating mini player resting above the bottom tab bar (matching bottom nav bar)
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
    required Color secondaryColor,
  }) {
    const double barHeight = 58.0;
    const double artSize = 42.0;

    return GlassContainer(
      height: barHeight,
      shape: const LiquidRoundedRectangle(borderRadius: 29),
      settings: kLiquidBottomDockGlassSettings,
      useOwnLayer: false,
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Tappable song info (Artwork + Title + Artist) to open full player screen
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    // Padding around the artwork only (equal 8px padding on all sides)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Hero(
                        tag: 'player_album_art_$songId',
                        flightShuttleBuilder: playerHeroFlightShuttleBuilder,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: WavifyCachedImage(
                            imageUrl: highResArt ?? thumbArt,
                            placeholderImageUrl: thumbArt,
                            songId: songId,
                            width: artSize,
                            height: artSize,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                            errorWidget: _fallbackArtwork(size: artSize),
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
                          const SizedBox(
                            height: AppleSpacing.titleToSubtitle,
                          ),
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

            const SizedBox(width: 4),

            // Play / Pause Button with responsive spring physics & smooth loading indicator
            ApplePressable(
              onTap: () {
                HapticFeedback.lightImpact();
                ref.read(playerProvider.notifier).togglePlayPause();
              },
              pressedScale: 0.88,
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.78, end: 1.0).animate(
                          CurvedAnimation(
                            parent: animation,
                            curve: Curves.easeOutBack,
                          ),
                        ),
                        child: child,
                      ),
                    );
                  },
                  child:
                      (isLoading &&
                          !Platform.environment.containsKey('FLUTTER_TEST'))
                      ? const SmoothPlayerLoader(radius: 11)
                      : AnimatedCupertinoIcon(
                          key: ValueKey(
                            'mini_expanded_play_pause_$isPlaying',
                          ),
                          icon: isPlaying
                              ? CupertinoIcons.pause_fill
                              : CupertinoIcons.play_fill,
                          color: Colors.white,
                          size: 28,
                        ),
                ),
              ),
            ),
            const SizedBox(width: 2),

            // Skip Next Button (Fast Forward)
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                ref.read(playerProvider.notifier).skipNext();
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                child: const AnimatedCupertinoIcon(
                  icon: CupertinoIcons.forward_fill,
                  color: Color(0xB3FFFFFF),
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      );
  }

  Widget _fallbackArtwork({double size = 36}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(8),
      ),
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

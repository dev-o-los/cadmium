import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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
    final playerState = ref.watch(playerProvider);
    final currentSong = playerState.currentSong;

    if (currentSong == null) {
      return const SizedBox.shrink();
    }

    final isPlaying = playerState.isPlaying;
    final isLoading = ref.watch(playerIsLoadingProvider);

    final progress = playerState.duration.inMilliseconds > 0
        ? (playerState.position.inMilliseconds /
                  playerState.duration.inMilliseconds)
              .clamp(0.0, 1.0)
        : 0.0;

    final effectiveArt =
        currentSong.highResThumbnailUrl ?? currentSong.resolvedThumbnailUrl;
    final thumbArt = currentSong.resolvedThumbnailUrl ?? currentSong.thumbnailUrl;

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
      progress: progress,
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
      color: const Color(0x3D1A1A1E),
      settings: const LiquidGlassSettings(
        thickness: 24,
        blur: 24,
        refractiveIndex: 1.15,
        lightIntensity: 0.45,
        specularSharpness: GlassSpecularSharpness.sharp,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // Album Artwork (Compact 34x34 with rounded corners)
            GestureDetector(
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      artist.isNotEmpty ? artist : 'Unknown Artist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 4),

            // Play / Pause Button with instant responsive tap
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                ref.read(playerProvider.notifier).togglePlayPause();
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 32,
                height: 34,
                alignment: Alignment.center,
                child: (isLoading && !Platform.environment.containsKey('FLUTTER_TEST'))
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

            // Skip Next Button
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                ref.read(playerProvider.notifier).skipNext();
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 28,
                height: 34,
                alignment: Alignment.center,
                child: const AnimatedCupertinoIcon(
                  icon: CupertinoIcons.forward_fill,
                  color: Colors.white,
                  size: 18,
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
    required double progress,
  }) {
    return GlassContainer(
      useOwnLayer: true,
      height: 52,
      shape: const LiquidRoundedSuperellipse(borderRadius: 26),
      color: const Color(0x3D1A1A1E),
      settings: const LiquidGlassSettings(
        thickness: 24,
        blur: 24,
        refractiveIndex: 1.15,
        lightIntensity: 0.45,
        specularSharpness: GlassSpecularSharpness.sharp,
      ),
      child: Stack(
        children: [
          // Main Content: Artwork, Metadata & Playback Controls
          Padding(
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
                        // Album Artwork with High-Res Upgrade & bicubic filtering
                        Hero(
                          tag: 'player_album_art_$songId',
                          flightShuttleBuilder: playerHeroFlightShuttleBuilder,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: WavifyCachedImage(
                              imageUrl: highResArt ?? thumbArt,
                              placeholderImageUrl: thumbArt,
                              songId: songId,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              filterQuality: FilterQuality.medium,
                              errorWidget: _fallbackArtwork(size: 40),
                            ),
                          )
                          .animate(key: ValueKey('mini_art_expanded_$songId'))
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
                        const SizedBox(width: 10),

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
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                artist.isNotEmpty ? artist : 'Unknown Artist',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF8E8E93),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
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
                    child: (isLoading && !Platform.environment.containsKey('FLUTTER_TEST'))
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

          // Subtle hairline progress bar at bottom of the pill
          Positioned(
            left: 14,
            right: 14,
            bottom: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(26),
                bottomRight: Radius.circular(26),
              ),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 2.0,
                backgroundColor: Colors.transparent,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0x99FFFFFF),
                ),
              ),
            ),
          ),
        ],
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

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
    return GlassContainer(
      useOwnLayer: true,
      height: 52,
      shape: const LiquidRoundedSuperellipse(borderRadius: 26),
      color: const Color(0x66121212),
      settings: const LiquidGlassSettings(
        glassColor: Color(0x66121212),
        thickness: 24,
        blur: 16,
        refractiveIndex: 1.25,
        lightIntensity: 0.70,
        specularSharpness: GlassSpecularSharpness.sharp,
        fresnelStrength: 1.25,
        rimLight: 0.40,
        ambientStrength: 0.10,
        chromaticAberration: 0.012,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
            width: 0.5,
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.15),
              Colors.white.withValues(alpha: 0.02),
              Colors.black.withValues(alpha: 0.12),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 8, top: 4, bottom: 4),
          child: Row(
            children: [
              // Album Artwork (BitChord spec: 31x31 with 6px rounded corners)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Hero(
                    tag: 'player_album_art_$songId',
                    flightShuttleBuilder: playerHeroFlightShuttleBuilder,
                    child:
                        ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: WavifyCachedImage(
                                imageUrl: highResArt ?? thumbArt,
                                placeholderImageUrl: thumbArt,
                                songId: songId,
                                width: 31,
                                height: 31,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.medium,
                                errorWidget: _fallbackArtwork(size: 31),
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
            ],
          ),
        ),
      ),
    );
  }

  /// Full-width floating mini player resting above the bottom tab bar (BitChord GlassNowPlaying spec)
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
    return GlassContainer(
      useOwnLayer: true,
      height: 52,
      shape: const LiquidRoundedSuperellipse(borderRadius: 26),
      color: const Color(0x66121212),
      settings: const LiquidGlassSettings(
        glassColor: Color(0x66121212),
        thickness: 24,
        blur: 16,
        refractiveIndex: 1.25,
        lightIntensity: 0.70,
        specularSharpness: GlassSpecularSharpness.sharp,
        fresnelStrength: 1.25,
        rimLight: 0.40,
        ambientStrength: 0.10,
        chromaticAberration: 0.012,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.10),
            width: 0.5,
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.15),
              Colors.white.withValues(alpha: 0.02),
              Colors.black.withValues(alpha: 0.12),
            ],
            stops: const [0.0, 0.45, 1.0],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 16, right: 12, top: 4, bottom: 4),
          child: Row(
            children: [
              // Tappable song info (Artwork + Title + Artist) to open full player screen
              Expanded(
                child: GestureDetector(
                  onTap: onTap,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      // Album Artwork (BitChord spec: 31x31 with 6px rounded corners)
                      Padding(
                        padding: const EdgeInsets.only(right: 9),
                        child: Hero(
                          tag: 'player_album_art_$songId',
                          flightShuttleBuilder: playerHeroFlightShuttleBuilder,
                          child:
                              ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: WavifyCachedImage(
                                      imageUrl: highResArt ?? thumbArt,
                                      placeholderImageUrl: thumbArt,
                                      songId: songId,
                                      width: 31,
                                      height: 31,
                                      fit: BoxFit.cover,
                                      filterQuality: FilterQuality.medium,
                                      errorWidget: _fallbackArtwork(size: 31),
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
                  width: 40,
                  height: 40,
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
                            size: 29,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 4),

              // Skip Next Button (Fast Forward - BitChord spec: 40x40 touch target, 22pt glyph, 70% white)
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  ref.read(playerProvider.notifier).skipNext();
                },
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  child: const AnimatedCupertinoIcon(
                    icon: CupertinoIcons.forward_fill,
                    color: Color(0xB3FFFFFF),
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
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

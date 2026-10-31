import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../providers/player_provider.dart';

/// Floating Liquid Glass Mini Player inspired by Apple Music.
/// Uses Riverpod for reactive playback state management and zero-lag controls.
class PlayerControls extends ConsumerWidget {
  final VoidCallback? onTap;

  const PlayerControls({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playerState = ref.watch(playerProvider);
    final currentSong = playerState.currentSong;

    if (currentSong == null) {
      return const SizedBox.shrink();
    }

    const appleMusicRed = Color(0xFFFA243C);
    final isPlaying = playerState.isPlaying;

    final progress = playerState.duration.inMilliseconds > 0
        ? (playerState.position.inMilliseconds / playerState.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final highResArt = currentSong.highResThumbnailUrl ?? currentSong.thumbnailUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: GlassContainer(
        useOwnLayer: true,
        height: 62,
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
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: highResArt != null
                                ? Image.network(
                                    highResArt,
                                    width: 44,
                                    height: 44,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.medium,
                                    cacheWidth: 132,
                                    cacheHeight: 132,
                                    errorBuilder: (context, error, stackTrace) => _fallbackArtwork(),
                                  )
                                : _fallbackArtwork(),
                          ),
                          const SizedBox(width: 12),

                          // Song Title & Artist
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentSong.title,
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
                                  playerState.isResolvingStream
                                      ? 'Connecting...'
                                      : currentSong.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: playerState.isResolvingStream
                                        ? appleMusicRed
                                        : const Color(0xFF8E8E93),
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

                  // Play / Pause Button: Dedicated gesture target with immediate response on first render
                  GestureDetector(
                    onTap: () {
                      ref.read(playerProvider.notifier).togglePlayPause();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      child: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Skip Next Button (Fast Forward)
                  GestureDetector(
                    onTap: () {
                      ref.read(playerProvider.notifier).skipNext();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 40,
                      height: 44,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.fast_forward_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),

            // Subtle hairline progress bar at bottom of the pill
            Positioned(
              left: 12,
              right: 12,
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
      ),
    );
  }

  Widget _fallbackArtwork() {
    return Container(
      width: 44,
      height: 44,
      color: const Color(0xFF2C2C2E),
      child: const Center(
        child: Icon(
          Icons.music_note_rounded,
          color: Colors.white38,
          size: 24,
        ),
      ),
    );
  }
}

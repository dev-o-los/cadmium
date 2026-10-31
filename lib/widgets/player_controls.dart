import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import '../models/song_item.dart';

/// Floating Liquid Glass Mini Player inspired by Apple Music.
/// Floats right above the liquid glass bottom dock.
class PlayerControls extends StatelessWidget {
  final SongItem? currentSong;
  final AudioPlayer audioPlayer;
  final bool isResolvingStream;
  final VoidCallback onTogglePlayPause;
  final VoidCallback? onSkipNext;
  final VoidCallback? onTap;

  const PlayerControls({
    super.key,
    required this.currentSong,
    required this.audioPlayer,
    required this.isResolvingStream,
    required this.onTogglePlayPause,
    this.onSkipNext,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (currentSong == null) {
      return const SizedBox.shrink();
    }

    const appleMusicRed = Color(0xFFFA243C);

    return StreamBuilder<PlayerState>(
      stream: audioPlayer.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final processingState = playerState?.processingState ?? ProcessingState.idle;
        final isPlaying = playerState?.playing ?? false;
        final isCompleted = processingState == ProcessingState.completed;

        // Requirement: When audio is playing (or active), immediately show the pause
        // icon so the user can pause or stop playback without being blocked by a buffer spinner.
        final showPauseIcon = (isPlaying || isResolvingStream) && !isCompleted;

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
          child: GestureDetector(
            onTap: onTap,
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
                        // Album Artwork
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: currentSong!.thumbnailUrl != null
                              ? Image.network(
                                  currentSong!.thumbnailUrl!,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _fallbackArtwork(),
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
                                currentSong!.title,
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
                                isResolvingStream
                                    ? 'Connecting...'
                                    : currentSong!.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isResolvingStream
                                      ? appleMusicRed
                                      : const Color(0xFF8E8E93),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Play / Pause Button: Immediately responds and shows pause icon when playing
                        IconButton(
                          onPressed: onTogglePlayPause,
                          iconSize: 30,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          splashRadius: 22,
                          icon: Icon(
                            showPauseIcon
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Skip Next Button (Fast Forward)
                        IconButton(
                          onPressed: onSkipNext ?? onTogglePlayPause,
                          iconSize: 26,
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          splashRadius: 22,
                          icon: const Icon(
                            Icons.fast_forward_rounded,
                            color: Colors.white,
                            size: 26,
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
                    child: StreamBuilder<Duration>(
                      stream: audioPlayer.positionStream,
                      builder: (context, posSnapshot) {
                        final position = posSnapshot.data ?? Duration.zero;
                        final duration = audioPlayer.duration ??
                            Duration(seconds: currentSong!.durationSeconds ?? 0);
                        final progress = duration.inMilliseconds > 0
                            ? (position.inMilliseconds / duration.inMilliseconds)
                                .clamp(0.0, 1.0)
                            : 0.0;

                        return ClipRRect(
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
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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

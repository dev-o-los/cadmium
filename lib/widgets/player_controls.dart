import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song_item.dart';

/// Apple Music styled Floating Frosted Mini Player.
/// Floats right above the bottom navigation bar with translucent blur,
/// album artwork, smooth play/pause, skip controls, and progress tracking.
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

        final isBuffering = processingState == ProcessingState.buffering ||
            processingState == ProcessingState.loading ||
            isResolvingStream;

        final isCompleted = processingState == ProcessingState.completed;

        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: GestureDetector(
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xDC252528),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                      width: 0.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
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
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
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
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Play / Pause Button - Fix: when playing, immediately show pause and allow stopping
                            IconButton(
                              onPressed: onTogglePlayPause,
                              iconSize: 28,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              splashRadius: 22,
                              icon: (isPlaying && !isCompleted)
                                  ? const Icon(
                                      Icons.pause_rounded,
                                      color: Colors.white,
                                      size: 30,
                                    )
                                  : isBuffering
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 30,
                                        ),
                            ),
                            const SizedBox(width: 4),

                            // Skip Next Button (Apple Music style)
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
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: StreamBuilder<Duration>(
                          stream: audioPlayer.positionStream,
                          builder: (context, posSnapshot) {
                            final position = posSnapshot.data ?? Duration.zero;
                            final total = audioPlayer.duration ??
                                Duration(seconds: currentSong?.durationSeconds ?? 1);

                            final double progress = (total.inMilliseconds > 0)
                                ? (position.inMilliseconds / total.inMilliseconds)
                                    .clamp(0.0, 1.0)
                                : 0.0;

                            return ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(14),
                              ),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 2.0,
                                backgroundColor: Colors.white.withValues(alpha: 0.08),
                                valueColor: const AlwaysStoppedAnimation<Color>(appleMusicRed),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
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
      color: const Color(0xFF3A3A3C),
      child: const Icon(
        Icons.music_note_rounded,
        color: Colors.white70,
        size: 24,
      ),
    );
  }
}

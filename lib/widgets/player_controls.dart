import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song_item.dart';

/// Minimal Material 3 Player Controls Widget.
/// Displays currently playing song metadata, playback status,
/// and a unified play/pause/loading action button.
class PlayerControls extends StatelessWidget {
  final SongItem? currentSong;
  final AudioPlayer audioPlayer;
  final bool isResolvingStream;
  final VoidCallback onTogglePlayPause;

  const PlayerControls({
    super.key,
    required this.currentSong,
    required this.audioPlayer,
    required this.isResolvingStream,
    required this.onTogglePlayPause,
  });

  @override
  Widget build(BuildContext context) {
    if (currentSong == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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

        // Determine human-readable status text
        String statusLabel;
        if (isResolvingStream) {
          statusLabel = 'Fetching stream...';
        } else if (processingState == ProcessingState.loading) {
          statusLabel = 'Loading...';
        } else if (processingState == ProcessingState.buffering) {
          statusLabel = 'Buffering...';
        } else if (isCompleted) {
          statusLabel = 'Finished';
        } else if (isPlaying) {
          statusLabel = 'Playing';
        } else {
          statusLabel = 'Paused';
        }

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                // Song Thumbnail or Music Icon
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: currentSong!.thumbnailUrl != null
                      ? Image.network(
                          currentSong!.thumbnailUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => _fallbackArtwork(colorScheme),
                        )
                      : _fallbackArtwork(colorScheme),
                ),
                const SizedBox(width: 12),

                // Song Title & Artist + Playback State Label
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentSong!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              currentSong!.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isPlaying
                                  ? colorScheme.primaryContainer
                                  : colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              statusLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isPlaying
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Single Unified Play/Pause/Loading Button
                IconButton.filled(
                  onPressed: isBuffering ? null : onTogglePlayPause,
                  iconSize: 28,
                  icon: isBuffering
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : Icon(
                          (isPlaying && !isCompleted)
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _fallbackArtwork(ColorScheme colorScheme) {
    return Container(
      width: 48,
      height: 48,
      color: colorScheme.primaryContainer,
      child: Icon(
        Icons.music_note_rounded,
        color: colorScheme.onPrimaryContainer,
      ),
    );
  }
}


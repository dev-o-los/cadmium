import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song_item.dart';

/// Full-Screen Apple Music-inspired Now Playing screen.
/// Features prominent album artwork, dynamic blurred background,
/// interactive duration scrubber, transport controls, and volume slider.
class PlayerScreen extends StatefulWidget {
  final SongItem song;
  final AudioPlayer audioPlayer;
  final bool isResolvingStream;
  final VoidCallback onTogglePlayPause;
  final VoidCallback? onSkipNext;
  final VoidCallback? onSkipPrevious;

  const PlayerScreen({
    super.key,
    required this.song,
    required this.audioPlayer,
    required this.isResolvingStream,
    required this.onTogglePlayPause,
    this.onSkipNext,
    this.onSkipPrevious,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  static const Color appleRed = Color(0xFFFA243C);
  static const Color appleSecondaryText = Color(0xFF8E8E93);

  bool _isFavorite = false;
  bool _isShuffle = false;
  LoopMode _loopMode = LoopMode.off;
  double _volume = 0.8;
  bool _isDraggingSlider = false;
  double _dragSliderValue = 0.0;

  @override
  void initState() {
    super.initState();
    _volume = widget.audioPlayer.volume;
    _loopMode = widget.audioPlayer.loopMode;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final artworkSize = (size.width - 64).clamp(240.0, 340.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Dynamic Blurred Background from Album Art
          if (widget.song.thumbnailUrl != null)
            Positioned.fill(
              child: Image.network(
                widget.song.thumbnailUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Container(color: const Color(0xFF1C1C1E)),
              ),
            ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                color: Colors.black.withValues(alpha: 0.78),
              ),
            ),
          ),

          // Main Screen Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top Navigation Bar (Chevron down + Header + More actions)
                  _buildTopBar(context),

                  // Prominent Album Artwork with dynamic scale
                  StreamBuilder<PlayerState>(
                    stream: widget.audioPlayer.playerStateStream,
                    builder: (context, snapshot) {
                      final isPlaying = snapshot.data?.playing ?? false;
                      final isBuffering = widget.isResolvingStream ||
                          snapshot.data?.processingState == ProcessingState.buffering ||
                          snapshot.data?.processingState == ProcessingState.loading;

                      final scale = (isPlaying && !isBuffering) ? 1.0 : 0.88;

                      return AnimatedScale(
                        scale: scale,
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutCubic,
                        child: Container(
                          width: artworkSize,
                          height: artworkSize,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.55),
                                blurRadius: 28,
                                offset: const Offset(0, 14),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: widget.song.thumbnailUrl != null
                                ? Image.network(
                                    widget.song.thumbnailUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        _fallbackArtwork(),
                                  )
                                : _fallbackArtwork(),
                          ),
                        ),
                      );
                    },
                  ),

                  // Track Metadata (Title, Artist, Like button)
                  _buildTrackInfo(),

                  // Scrubber Time Slider
                  _buildDurationScrubber(),

                  // Main Playback Controls (Previous, Play/Pause, Next)
                  _buildPlaybackControls(),

                  // Volume & Output Bottom Bar
                  _buildBottomControls(),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 36),
          onPressed: () => Navigator.of(context).pop(),
        ),
        Column(
          children: [
            const Text(
              'PLAYING FROM',
              style: TextStyle(
                color: appleSecondaryText,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              widget.song.artist,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70, size: 28),
          onPressed: () {
            // Options sheet if needed
          },
        ),
      ],
    );
  }

  Widget _buildTrackInfo() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: appleSecondaryText,
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
            color: _isFavorite ? appleRed : Colors.white70,
            size: 28,
          ),
          onPressed: () {
            setState(() {
              _isFavorite = !_isFavorite;
            });
          },
        ),
      ],
    );
  }

  Widget _buildDurationScrubber() {
    return StreamBuilder<Duration>(
      stream: widget.audioPlayer.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = widget.audioPlayer.duration ??
            Duration(seconds: widget.song.durationSeconds ?? 0);

        final totalMs = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
        final currentMs = _isDraggingSlider
            ? _dragSliderValue
            : position.inMilliseconds.toDouble().clamp(0.0, totalMs);

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.5,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                overlayColor: Colors.white.withValues(alpha: 0.12),
              ),
              child: Slider(
                min: 0.0,
                max: totalMs,
                value: currentMs.clamp(0.0, totalMs),
                onChangeStart: (_) {
                  setState(() {
                    _isDraggingSlider = true;
                  });
                },
                onChanged: (val) {
                  setState(() {
                    _dragSliderValue = val;
                  });
                },
                onChangeEnd: (val) async {
                  await widget.audioPlayer.seek(Duration(milliseconds: val.toInt()));
                  setState(() {
                    _isDraggingSlider = false;
                  });
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(Duration(milliseconds: currentMs.toInt())),
                    style: const TextStyle(
                      color: appleSecondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '-${_formatDuration(Duration(milliseconds: (totalMs - currentMs).toInt()))}',
                    style: const TextStyle(
                      color: appleSecondaryText,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlaybackControls() {
    return StreamBuilder<PlayerState>(
      stream: widget.audioPlayer.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final isPlaying = playerState?.playing ?? false;
        final isCompleted = playerState?.processingState == ProcessingState.completed;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Shuffle
            IconButton(
              icon: Icon(
                Icons.shuffle_rounded,
                color: _isShuffle ? appleRed : Colors.white60,
                size: 24,
              ),
              onPressed: () {
                setState(() {
                  _isShuffle = !_isShuffle;
                  widget.audioPlayer.setShuffleModeEnabled(_isShuffle);
                });
              },
            ),

            // Previous
            IconButton(
              icon: const Icon(
                Icons.skip_previous_rounded,
                color: Colors.white,
                size: 42,
              ),
              onPressed: widget.onSkipPrevious ?? () => widget.audioPlayer.seek(Duration.zero),
            ),

            // Main Large Play / Pause button
            GestureDetector(
              onTap: widget.onTogglePlayPause,
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: Center(
                  child: Icon(
                    (isPlaying && !isCompleted)
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.black,
                    size: 44,
                  ),
                ),
              ),
            ),

            // Next
            IconButton(
              icon: const Icon(
                Icons.skip_next_rounded,
                color: Colors.white,
                size: 42,
              ),
              onPressed: widget.onSkipNext,
            ),

            // Repeat / Loop
            IconButton(
              icon: Icon(
                _loopMode == LoopMode.one
                    ? Icons.repeat_one_rounded
                    : _loopMode == LoopMode.all
                        ? Icons.repeat_rounded
                        : Icons.repeat_rounded,
                color: _loopMode != LoopMode.off ? appleRed : Colors.white60,
                size: 24,
              ),
              onPressed: () {
                setState(() {
                  if (_loopMode == LoopMode.off) {
                    _loopMode = LoopMode.all;
                  } else if (_loopMode == LoopMode.all) {
                    _loopMode = LoopMode.one;
                  } else {
                    _loopMode = LoopMode.off;
                  }
                  widget.audioPlayer.setLoopMode(_loopMode);
                });
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.volume_mute_rounded, color: appleSecondaryText, size: 20),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3.0,
                activeTrackColor: Colors.white70,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: _volume,
                min: 0.0,
                max: 1.0,
                onChanged: (val) {
                  setState(() {
                    _volume = val;
                  });
                  widget.audioPlayer.setVolume(val);
                },
              ),
            ),
          ),
          const Icon(Icons.volume_up_rounded, color: appleSecondaryText, size: 20),
        ],
      ),
    );
  }

  Widget _fallbackArtwork() {
    return Container(
      color: const Color(0xFF2C2C2E),
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: Colors.white24, size: 80),
      ),
    );
  }
}


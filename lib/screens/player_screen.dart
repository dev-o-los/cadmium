import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../constants/app_colors.dart';
import '../constants/apple_typography.dart';
import '../models/song_item.dart';
import '../providers/favorites_provider.dart';
import '../providers/player_provider.dart';
import '../services/artwork_color_service.dart';
import '../services/song_metrics_cache_service.dart';
import '../utils/playback_utils.dart';
import '../widgets/ambient_video_canvas.dart';
import '../widgets/animated_cupertino_icon.dart';
import '../widgets/animated_equalizer_bars.dart';
import '../widgets/apple_glass_bottom_sheet.dart';
import '../widgets/apple_music_slider.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/apple_lyrics_view.dart';
import '../widgets/smooth_player_loader.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/wavify_cached_image.dart';

/// Reactive provider extracting the brightest vibrant color from current album artwork
final currentSongBestColorProvider =
    FutureProvider.autoDispose<Color>((ref) async {
  final song = ref.watch(playerProvider.select((s) => s.currentSong));
  if (song == null) return const Color(0xFFE10600);
  final art = song.highResThumbnailUrl ??
      song.resolvedThumbnailUrl ??
      song.thumbnailUrl;
  return ArtworkColorService.instance.extractBestVibrantColor(
    art,
    fallbackSeed: '${song.title} ${song.artist}',
  );
});

enum PlayerViewMode { nowPlaying, lyrics, queue }

/// Full-Screen Apple Music-inspired Now Playing screen:
/// - Seamless edge-to-edge artwork extending behind status bar with gradual downward blur transition
/// - Downside player controls smoothly collapse/slide down after inactivity when playing
/// - When collapsed, only track title/album, artist, favourite, and dot buttons remain visible
/// - Full-size karaoke lyrics mode with downside controls collapsed
/// - Clean camera-notch-free top bar with truncated "Playing from Album"
/// - Lifted transport and dock buttons (38px up from bottom)
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with TickerProviderStateMixin {
  static const Color appleSecondaryText = AppColors.appleSecondaryText;

  PlayerViewMode _currentMode = PlayerViewMode.nowPlaying;

  // Background ambient animation controller (subtle 20s breathing zoom)
  late AnimationController _ambientAnimController;

  // Downside controls slide & fade animation controller (1.0 = expanded, 0.0 = collapsed downside)
  late AnimationController _controlsAnimController;

  // Mode transition animation controller (0.0 = nowPlaying, 1.0 = lyrics / queue)
  late AnimationController _modeAnimController;

  // Interactive downward drag-to-dismiss state
  double _dragOffsetY = 0.0;
  late AnimationController _dragSnapBackController;
  late Animation<double> _dragSnapBackAnimation;

  // Auto-hide timer for collapsing downside controls after 5-10s (7 seconds default)
  Timer? _autoHideTimer;

  // Scrubber drag state (local UI interaction only)
  bool _isDraggingSlider = false;
  double _dragSliderValue = 0.0;

  @override
  void initState() {
    super.initState();

    // Ambient background breathing animation (20 seconds continuous smooth oscillation)
    _ambientAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat(reverse: true);

    // Downside player collapse/expand animation controller (starts visible)
    _controlsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      value: 1.0,
    );

    // Mode transition controller (0.0 = nowPlaying, 1.0 = lyrics/queue)
    _modeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 440),
      value: _currentMode == PlayerViewMode.nowPlaying ? 0.0 : 1.0,
    );

    // Interactive downward drag snap back
    _dragSnapBackController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 240),
        )..addListener(() {
          setState(() {
            _dragOffsetY = _dragSnapBackAnimation.value;
          });
        });

    // Auto-collapse check after initial screen load only if in lyrics mode
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final isPlaying = ref.read(playerProvider).isPlaying;
        if (isPlaying && _currentMode == PlayerViewMode.lyrics) {
          _startAutoHideTimer();
        }
      }
    });
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (_dragSnapBackController.isAnimating) {
      _dragSnapBackController.stop();
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final next = _dragOffsetY + details.delta.dy;
    if (next >= 0) {
      setState(() {
        _dragOffsetY = next;
      });
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffsetY > 110 ||
        (details.primaryVelocity != null && details.primaryVelocity! > 400)) {
      Navigator.of(context).pop();
    } else if (_dragOffsetY > 0) {
      _dragSnapBackAnimation = Tween<double>(begin: _dragOffsetY, end: 0.0)
          .animate(
            CurvedAnimation(
              parent: _dragSnapBackController,
              curve: Curves.easeOutCubic,
            ),
          );
      _dragSnapBackController.forward(from: 0.0);
    }
  }

  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    if (!mounted) return;
    // Auto-hide controls only when in lyrics mode
    if (_currentMode != PlayerViewMode.lyrics) {
      if (_controlsAnimController.value < 1.0) {
        _controlsAnimController.forward();
      }
      return;
    }
    final isPlaying = ref.read(playerProvider).isPlaying;
    if (isPlaying && !_isDraggingSlider) {
      _autoHideTimer = Timer(const Duration(seconds: 7), () {
        if (mounted &&
            ref.read(playerProvider).isPlaying &&
            !_isDraggingSlider &&
            _currentMode == PlayerViewMode.lyrics) {
          _controlsAnimController.reverse();
        }
      });
    }
  }

  void _cancelAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = null;
  }

  void _resetAutoHideTimer() {
    _cancelAutoHideTimer();
    if (_controlsAnimController.value < 1.0) {
      _controlsAnimController.forward();
    }
    if (_currentMode == PlayerViewMode.lyrics) {
      _startAutoHideTimer();
    }
  }

  void _toggleControls() {
    // Only allow collapsing controls when in lyrics mode
    if (_currentMode != PlayerViewMode.lyrics) {
      if (_controlsAnimController.value < 1.0) {
        _controlsAnimController.forward();
      }
      return;
    }
    if (_controlsAnimController.isAnimating) return;
    if (_controlsAnimController.value > 0.5) {
      _cancelAutoHideTimer();
      _controlsAnimController.reverse();
    } else {
      _controlsAnimController.forward();
      _startAutoHideTimer();
    }
  }

  void _switchMode(PlayerViewMode newMode) {
    if (_currentMode == newMode && !_modeAnimController.isAnimating) return;
    final oldMode = _currentMode;
    setState(() {
      _currentMode = newMode;
    });

    if (newMode == PlayerViewMode.nowPlaying) {
      _modeAnimController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 440),
        curve: Curves.easeInOutCubic,
      );
      _cancelAutoHideTimer();
      _controlsAnimController.forward();
    } else {
      if (oldMode == PlayerViewMode.nowPlaying) {
        _modeAnimController.animateTo(
          1.0,
          duration: const Duration(milliseconds: 440),
          curve: Curves.easeInOutCubic,
        );
      }
      _controlsAnimController.forward();
      if (newMode == PlayerViewMode.lyrics) {
        _startAutoHideTimer();
      } else {
        _cancelAutoHideTimer();
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _showAudioRouteModal() {
    showAudioOutputModal(context, ref);
  }

  void _showSongOptionsSheet(SongItem song) {
    showTrackOptionsModal(context, ref, song);
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _ambientAnimController.dispose();
    _controlsAnimController.dispose();
    _modeAnimController.dispose();
    _dragSnapBackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(playerProvider.select((s) => s.currentSong));

    if (song == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'No song currently playing',
            style: TextStyle(color: appleSecondaryText),
          ),
        ),
      );
    }

    final isFavorite = ref.watch(
      favoritesProvider.select((list) => list.any((s) => s.id == song.id)),
    );

    // Auto-hide controls when song starts playing ONLY in lyrics mode; keep visible in nowPlaying and queue
    ref.listen<bool>(playerProvider.select((s) => s.isPlaying), (
      previous,
      isPlaying,
    ) {
      if (isPlaying) {
        if (_currentMode == PlayerViewMode.lyrics) {
          _startAutoHideTimer();
        } else {
          _cancelAutoHideTimer();
          _controlsAnimController.forward();
        }
      } else {
        _cancelAutoHideTimer();
        _controlsAnimController.forward();
      }
    });

    final screenHeight = MediaQuery.sizeOf(context).height;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: SizedBox(
        height: screenHeight,
        width: screenWidth,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Transform.translate(
            offset: Offset(0, _dragOffsetY),
            child: GestureDetector(
              onTap: () {
                // Tapping anywhere reveals controls if collapsed, or resets inactivity timer in lyrics mode
                if (_controlsAnimController.value < 0.5) {
                  _controlsAnimController.forward();
                  if (_currentMode == PlayerViewMode.lyrics) {
                    _startAutoHideTimer();
                  }
                } else if (_currentMode == PlayerViewMode.lyrics) {
                  _startAutoHideTimer();
                }
              },
              behavior: HitTestBehavior.translucent,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Edge-to-edge Animated Ambient Artwork Canvas with gradual downward blur transition
                  _buildAmbientBackdrop(song, screenHeight),

                  // 2. Continuous morphing album artwork (animates between Now Playing and Lyrics header, and Hero from miniplayer)
                  _buildMorphingArtwork(
                    song: song,
                    screenWidth: screenWidth,
                    screenHeight: screenHeight,
                    headerTop: math.max(topPadding, 48) + 18.0,
                  ),

                  // 3. Top Header Area (gesture drag handle, "Playing from Album" in Now Playing, and Title/Artist/Actions in Lyrics)
                  _buildTopHeader(
                    song: song,
                    headerTop: math.max(topPadding, 48) + 18.0,
                    isFavorite: isFavorite,
                  ),

                  // 4. Center Alternate Mode Content (Lyrics or Queue)
                  _buildCenterContent(
                    song: song,
                    headerTop: math.max(topPadding, 48) + 18.0,
                    bottomPadding: bottomPadding,
                  ),

                  // 5. Bottom Controls (Metadata row in Now Playing, Scrubber, Transport, Dock)
                  _buildBottomControls(
                    song: song,
                    bottomPadding: bottomPadding,
                    isFavorite: isFavorite,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// AMOLED high-contrast vibrancy matrix:
  /// Gently enriches shadow depth, increases color saturation by ~5%,
  /// and ensures dark tones snap to pitch black on OLED/AMOLED displays.
  static const ColorFilter _amoledVibrancyFilter = ColorFilter.matrix([
    1.05,
    0.00,
    0.00,
    0.00,
    -2,
    0.00,
    1.05,
    0.00,
    0.00,
    -2,
    0.00,
    0.00,
    1.05,
    0.00,
    -2,
    0.00,
    0.00,
    0.00,
    1.00,
    0,
  ]);

  Widget _buildAmbientBackdrop(SongItem song, double screenHeight) {
    final artworkUrl = song.highResThumbnailUrl ?? song.resolvedThumbnailUrl;
    if (artworkUrl == null || artworkUrl.isEmpty) {
      return Container(color: Colors.black);
    }

    final animatedArtworkUrl =
        ref.watch(playerProvider.select((s) => s.animatedArtworkUrl)) ??
        song.animatedArtworkUrl;

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _ambientAnimController,
          _modeAnimController,
          _controlsAnimController,
        ]),
        builder: (context, _) {
          final scale = 1.0 + (_ambientAnimController.value * 0.05);
          final modeVal = _modeAnimController.value;
          final controlsVal = CurvedAnimation(
            parent: _controlsAnimController,
            curve: Curves.easeInOutCubic,
          ).value;

          // In nowPlaying mode, blur smoothly transitions from 15.0 down to 0.0 when controls collapse.
          // In lyrics/queue mode, keep ambient blur (15.0) for readability of text.
          final effectiveSigma = ui.lerpDouble(
            15.0 * modeVal,
            15.0,
            controlsVal,
          )!.clamp(0.0, 15.0);

          Widget backdropImage = WavifyCachedImage(
            imageUrl:
                AmbientVideoCanvas.isVideoUrl(
                  animatedArtworkUrl,
                )
                ? artworkUrl
                : (animatedArtworkUrl ?? artworkUrl),
            placeholderImageUrl:
                song.resolvedThumbnailUrl ??
                song.thumbnailUrl,
            songId: song.id,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            filterQuality: FilterQuality.medium,
            errorWidget: const SizedBox(),
          );

          backdropImage = ColorFiltered(
            colorFilter: _amoledVibrancyFilter,
            child: backdropImage,
          );

          if (effectiveSigma > 0.1) {
            backdropImage = ImageFiltered(
              imageFilter: ui.ImageFilter.blur(
                sigmaX: effectiveSigma,
                sigmaY: effectiveSigma,
              ),
              child: backdropImage,
            );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              // Pitch black AMOLED base
              Container(color: Colors.black),

              // Full-bleed artwork backdrop (blurred when controls are up, crisp when controls collapse)
              Positioned.fill(
                    child: ClipRect(
                      child: Transform.scale(
                        scale: scale * (1.0 + (0.15 * controlsVal)),
                        alignment: Alignment.topCenter,
                        child: backdropImage,
                      ),
                    ),
                  )
                  .animate(key: ValueKey('player_screen_ambient_${song.id}'))
                  .fadeIn(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                  ),

              // Smooth darkness dissolve in Now Playing: fades out as controls collapse
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.15 * controlsVal),
                        Colors.black.withValues(alpha: 0.45 * controlsVal),
                        Colors.black.withValues(alpha: 0.72 * controlsVal),
                        Colors.black.withValues(alpha: 0.86 * controlsVal),
                      ],
                      stops: const [0.0, 0.38, 0.52, 0.68, 0.84, 1.0],
                    ),
                  ),
                ),
              ),

              // Dark overlay tint for Lyrics / Queue mode (fades in as modeVal -> 1.0)
              if (modeVal > 0.0)
                Positioned.fill(
                  child: Container(
                    color: Color.lerp(
                      Colors.transparent,
                      const Color(0x7508080A),
                      modeVal,
                    ),
                  ),
                ),

              // Top Status Bar Vignette (preserves status icons readability, fades when controls collapse)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 120,
                child: Opacity(
                  opacity: controlsVal,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.50),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMorphingArtwork({
    required SongItem song,
    required double screenWidth,
    required double screenHeight,
    required double headerTop,
  }) {
    final artworkUrl = song.highResThumbnailUrl ?? song.resolvedThumbnailUrl;
    if (artworkUrl == null || artworkUrl.isEmpty) {
      return Container(color: Colors.black);
    }

    final animatedArtworkUrl =
        ref.watch(playerProvider.select((s) => s.animatedArtworkUrl)) ??
        song.animatedArtworkUrl;
    final animatedArtworkHeaders = ref.watch(
      playerProvider.select((s) => s.animatedArtworkHeaders),
    );
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));

    const double targetThumbSize = 48.0;

    return AnimatedBuilder(
      animation: Listenable.merge([
        _modeAnimController,
        _ambientAnimController,
        _controlsAnimController,
      ]),
      builder: (context, _) {
        final modeVal = CurvedAnimation(
          parent: _modeAnimController,
          curve: Curves.easeInOutCubic,
        ).value;
        final controlsVal = CurvedAnimation(
          parent: _controlsAnimController,
          curve: Curves.easeInOutCubic,
        ).value;

        // Subtle breathing zoom scale (1.0 to 1.05) when in expanded nowPlaying mode with controls visible
        final breathingScale =
            1.0 + (_ambientAnimController.value * 0.05 * (1.0 - modeVal) * controlsVal);

        // When in Now Playing mode:
        // - if controlsVal == 1.0 (controls visible), height is 50% screen height
        // - if controlsVal == 0.0 (controls collapsed), height is 100% screen height (full screen video/artwork!)
        // When transitioning to lyrics/queue mode (modeVal -> 1.0), height smoothly transitions to targetThumbSize (48.0)
        final expandedHeight = ui.lerpDouble(
          screenHeight,
          screenHeight * 0.50,
          controlsVal,
        )!;
        final height = ui.lerpDouble(
          expandedHeight,
          targetThumbSize,
          modeVal,
        )!;

        // Interpolate rect geometry between Now Playing full/50% canvas and Lyrics 48x48 header thumbnail
        final left = ui.lerpDouble(0.0, 24.0, modeVal)!;
        final top = ui.lerpDouble(0.0, headerTop, modeVal)!;
        final width = ui.lerpDouble(screenWidth, targetThumbSize, modeVal)!;
        final borderRadius = ui.lerpDouble(0.0, 12.0, modeVal)!;

        // Base image content
        Widget imageWidget = WavifyCachedImage(
          imageUrl: artworkUrl,
          placeholderImageUrl: song.resolvedThumbnailUrl ?? song.thumbnailUrl,
          songId: song.id,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.high,
          errorWidget: _fallbackMiniArt(
            size: targetThumbSize,
            borderRadius: borderRadius,
          ),
        );

        // Hardware-accelerated ambient moving video canvas when available
        if (animatedArtworkUrl != null && animatedArtworkUrl.isNotEmpty) {
          imageWidget = Stack(
            fit: StackFit.expand,
            children: [
              imageWidget,
              AmbientVideoCanvas(
                mediaUrl: animatedArtworkUrl,
                headers: animatedArtworkHeaders,
                fallbackImageUrl: song.thumbnailUrl,
                isPlaying: isPlaying,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ],
          );
        }

        // Apply breathing zoom only in Now Playing mode with controls visible
        imageWidget = Transform.scale(
          scale: breathingScale,
          alignment: Alignment.topCenter,
          child: ColorFiltered(
            colorFilter: _amoledVibrancyFilter,
            child: imageWidget,
          ),
        );

        // Downward blur dissolve shader mask: feathered in expanded mode when controls are visible,
        // completely eliminated when controls collapse so the video is full-screen edge-to-edge
        final dissolveFactor = (controlsVal * (1.0 - modeVal)).clamp(0.0, 1.0);
        if (modeVal < 0.96 && dissolveFactor > 0.02) {
          imageWidget = ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black,
                  Colors.black,
                  Color.lerp(Colors.black, const Color(0xEE000000), dissolveFactor)!,
                  Color.lerp(Colors.black, const Color(0x88000000), dissolveFactor)!,
                  Color.lerp(Colors.black, const Color(0x22000000), dissolveFactor)!,
                  Color.lerp(Colors.black, const Color(0x00000000), dissolveFactor)!,
                ],
                stops: const [0.0, 0.60, 0.74, 0.86, 0.95, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: imageWidget,
          );
        }

        // Subtle, smooth crossfade and gentle scale transition when shifting albums or tracks
        final transitionedArtwork = AnimatedSwitcher(
          duration: const Duration(milliseconds: 380),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              fit: StackFit.expand,
              children: [
                ...previousChildren,
                ?currentChild,
              ],
            );
          },
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey('player_art_switch_${song.album ?? song.id}_${song.id}'),
            child: imageWidget,
          ),
        );

        return Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: GestureDetector(
            onTap: () {
              if (_modeAnimController.value > 0.4) {
                // Clicking the album art on the music player upside in lyrics tab
                // gradually opens the album art!
                _switchMode(PlayerViewMode.nowPlaying);
              } else {
                // Clicking the album art in now playing toggles downside controls
                _toggleControls();
              }
            },
            onVerticalDragStart: (modeVal < 0.3) ? _onVerticalDragStart : null,
            onVerticalDragUpdate: (modeVal < 0.3)
                ? _onVerticalDragUpdate
                : null,
            onVerticalDragEnd: (modeVal < 0.3) ? _onVerticalDragEnd : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(borderRadius),
                boxShadow: modeVal > 0.05
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45 * modeVal),
                          blurRadius: 14 * modeVal,
                          offset: Offset(0, 5 * modeVal),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius),
                child: Hero(
                  tag: 'player_album_art_${song.id}',
                  flightShuttleBuilder: playerHeroFlightShuttleBuilder,
                  child: Container(
                    key: ValueKey('player_screen_artwork_${song.id}'),
                    child: transitionedArtwork,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopHeader({
    required SongItem song,
    required double headerTop,
    required bool isFavorite,
  }) {
    final playingFromText =
        (song.album != null && song.album!.trim().isNotEmpty)
        ? 'Playing from ${song.album!.trim()}'
        : 'Playing from ${song.artist.trim()}';

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: headerTop + 54,
      child: GestureDetector(
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        behavior: HitTestBehavior.translucent,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _modeAnimController,
            _controlsAnimController,
          ]),
          builder: (context, _) {
            final modeVal = _modeAnimController.value;
            final controlsVal = CurvedAnimation(
              parent: _controlsAnimController,
              curve: Curves.easeInOutCubic,
            ).value;

            return Stack(
              children: [
                // 1. Now Playing Top Header: Grab Bar + "Playing from <Album/Artist>" (fades out smoothly with controls)
                if (modeVal < 0.95)
                  Positioned(
                    top: headerTop - 14,
                    left: 36,
                    right: 36,
                    child: IgnorePointer(
                      ignoring: controlsVal < 0.1,
                      child: Opacity(
                        opacity: ((1.0 - (modeVal * 2.5)) * controlsVal).clamp(0.0, 1.0),
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 36,
                                height: 4.5,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.38),
                                  borderRadius: BorderRadius.circular(2.25),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                playingFromText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.70),
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                // 2. Lyrics / Queue Top Header Metadata (beside 48x48 thumbnail: title, artist, star, 3-dots)
                if (modeVal > 0.05)
                  Positioned(
                    top: headerTop,
                    left: 86,
                    right: 20,
                    height: 48,
                    child: Opacity(
                      opacity: ((modeVal - 0.25) / 0.75).clamp(0.0, 1.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    if (_isExplicit(song.title, song.album))
                                      _buildExplicitBadge(),
                                    Expanded(
                                      child: Text(
                                        song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppleTypography.songTitle,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(
                                  height: AppleSpacing.titleToSubtitle,
                                ),
                                ApplePressable(
                                  onTap: () => openArtistScreen(
                                    context,
                                    artistName: song.artist,
                                  ),
                                  child: Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppleTypography.songArtist,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildLiquidGlassButton(
                            size: 36,
                            color: isFavorite
                                ? Colors.white.withValues(alpha: 0.24)
                                : Colors.white.withValues(alpha: 0.12),
                            onTap: () => ref
                                .read(favoritesProvider.notifier)
                                .toggleFavorite(song),
                            icon: AnimatedCupertinoIcon(
                              icon: isFavorite
                                  ? CupertinoIcons.star_fill
                                  : CupertinoIcons.star,
                              color: Colors.white,
                              size: 17,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildLiquidGlassButton(
                            size: 36,
                            onTap: () => _showSongOptionsSheet(song),
                            icon: const AnimatedCupertinoIcon(
                              icon: CupertinoIcons.ellipsis,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCenterContent({
    required SongItem song,
    required double headerTop,
    required double bottomPadding,
  }) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _modeAnimController,
        _controlsAnimController,
      ]),
      builder: (context, _) {
        final modeVal = _modeAnimController.value;
        if (modeVal == 0.0) {
          return const SizedBox.shrink();
        }

        final opacity = ((modeVal - 0.20) / 0.80).clamp(0.0, 1.0);
        final slideUp = (1.0 - modeVal) * 28.0;

        // Space occupied by bottom controls when expanded vs collapsed
        final controlsExtra = _controlsAnimController.value * 230.0;

        return Positioned(
          top: headerTop + 54,
          left: 0,
          right: 0,
          bottom: math.max(bottomPadding, 24) + 68 + controlsExtra + 14.0,
          child: Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, slideUp),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.0, 0.04),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _currentMode == PlayerViewMode.lyrics
                    ? KeyedSubtree(
                        key: const ValueKey('lyrics_mode'),
                        child: _buildLyricsContent(),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('queue_mode'),
                        child: _buildQueueContent(song),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomControls({
    required SongItem song,
    required double bottomPadding,
    required bool isFavorite,
  }) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomPadding + 54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Metadata Row: Track Title & Artist on Left, Star & 3-dots on Right
            AnimatedBuilder(
              animation: _modeAnimController,
              builder: (context, _) {
                final modeVal = _modeAnimController.value;
                if (modeVal >= 0.95) {
                  return const SizedBox.shrink();
                }

                return Opacity(
                  opacity: (1.0 - (modeVal * 2.2)).clamp(0.0, 1.0),
                  child: _buildMetadataRow(song, isFavorite),
                );
              },
            ),

            // Downside collapsible player controls (Scrubber, transport, dock)
            ClipRect(
              child: SizeTransition(
                sizeFactor: CurvedAnimation(
                  parent: _controlsAnimController,
                  curve: Curves.easeInOutCubic,
                ),
                alignment: Alignment.topCenter,
                child: FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _controlsAnimController,
                    curve: const Interval(0.25, 1.0, curve: Curves.easeOut),
                  ),
                  child: SlideTransition(
                    position:
                        Tween<Offset>(
                          begin: const Offset(0.0, 0.25),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: _controlsAnimController,
                            curve: Curves.easeInOutCubic,
                          ),
                        ),
                    child: AnimatedBuilder(
                      animation: _controlsAnimController,
                      builder: (context, child) {
                        if (_controlsAnimController.value == 0.0) {
                          return const SizedBox.shrink();
                        }
                        return child!;
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_currentMode != PlayerViewMode.lyrics)
                            const SizedBox(height: 20)
                          else
                            const SizedBox(height: 8),

                          // Lyrics Hook Preview Banner (visible in Now Playing and Queue modes)
                          if (_currentMode != PlayerViewMode.lyrics) ...[
                            Consumer(
                              builder: (context, ref, _) {
                                final activeLyric = ref.watch(
                                  playerProvider.select((s) {
                                    if (s.lyrics.isNotEmpty) {
                                      if (s.activeLyricIndex >= 0 &&
                                          s.activeLyricIndex <
                                              s.lyrics.length) {
                                        final lyricText = s
                                            .lyrics[s.activeLyricIndex]
                                            .text
                                            .trim();
                                        if (lyricText.isNotEmpty) {
                                          return lyricText;
                                        }
                                      } else if (s.lyrics.first.text
                                          .trim()
                                          .isNotEmpty) {
                                        return s.lyrics.first.text.trim();
                                      }
                                    }
                                    return 'The hook is on the way';
                                  }),
                                );

                                return ApplePressable(
                                  onTap: () =>
                                      _switchMode(PlayerViewMode.lyrics),
                                  pressedScale: 0.98,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          CupertinoIcons.music_note_2,
                                          color: Colors.white,
                                          size: 15,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 320,
                                            ),
                                            layoutBuilder:
                                                (
                                                  currentChild,
                                                  previousChildren,
                                                ) {
                                                  return Stack(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    children: [
                                                      ...previousChildren,
                                                      ?currentChild,
                                                    ],
                                                  );
                                                },
                                            transitionBuilder:
                                                (child, animation) {
                                                  final isEntering =
                                                      (child.key
                                                              as ValueKey<
                                                                String
                                                              >?)
                                                          ?.value ==
                                                      activeLyric;
                                                  final offsetAnimation =
                                                      isEntering
                                                      ? Tween<Offset>(
                                                          begin: const Offset(
                                                            0.0,
                                                            0.9,
                                                          ),
                                                          end: Offset.zero,
                                                        ).animate(
                                                          CurvedAnimation(
                                                            parent: animation,
                                                            curve: Curves
                                                                .easeOutCubic,
                                                          ),
                                                        )
                                                      : Tween<Offset>(
                                                          begin: const Offset(
                                                            0.0,
                                                            -0.9,
                                                          ),
                                                          end: Offset.zero,
                                                        ).animate(
                                                          CurvedAnimation(
                                                            parent: animation,
                                                            curve: Curves
                                                                .easeInCubic,
                                                          ),
                                                        );

                                                  return ClipRect(
                                                    child: SlideTransition(
                                                      position: offsetAnimation,
                                                      child: FadeTransition(
                                                        opacity: animation,
                                                        child: child,
                                                      ),
                                                    ),
                                                  );
                                                },
                                            child: Text(
                                              activeLyric,
                                              key: ValueKey<String>(
                                                activeLyric,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.85,
                                                ),
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w500,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 5),
                                        Icon(
                                          CupertinoIcons.chevron_right,
                                          color: Colors.white.withValues(
                                            alpha: 0.45,
                                          ),
                                          size: 12.5,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 4),
                          ],

                          // Slider Bar with appropriate padding top & bottom
                          _buildDurationScrubber(),
                          const SizedBox(height: 40),

                          // Player Controls (Transport) with padding at top and bottom
                          _buildTransportControls(),
                          const SizedBox(height: 40),

                          // Bottom Parts (Action Dock: Lyrics, Speaker, Queue) - ALWAYS at the bottom!
                          _buildActionDock(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Reusable circular Liquid Glass button for actions like favourite and ellipsis.
  /// Uses authentic GlassContainer from liquid_glass_widgets with LiquidOval shape,
  /// real-time refraction physics, and specular highlight rim.
  Widget _buildLiquidGlassButton({
    required Widget icon,
    required VoidCallback onTap,
    double size = 36,
    Color? color,
  }) {
    return ApplePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: GlassContainer(
        useOwnLayer: true,
        width: size,
        height: size,
        shape: const LiquidOval(),
        color: color ?? Colors.white.withValues(alpha: 0.10),
        settings: const LiquidGlassSettings(
          thickness: 24,
          blur: 20,
          refractiveIndex: 1.25,
          lightIntensity: 0.75,
          specularSharpness: GlassSpecularSharpness.sharp,
          fresnelStrength: 1.30,
          rimLight: 0.45,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
              width: 0.8,
            ),
          ),
          child: Center(child: icon),
        ),
      ),
    );
  }

  bool _isExplicit(String title, [String? album]) {
    final lower = (title + (album ?? '')).toLowerCase();
    return lower.contains('(explicit') ||
        lower.contains('[explicit') ||
        lower.contains('explicit version') ||
        lower.contains('explicit');
  }

  Widget _buildExplicitBadge() {
    return Container(
      margin: const EdgeInsets.only(right: 5),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text('E', style: AppleTypography.explicitBadge),
    );
  }

  /// Metadata Row: Song Title + Artist on Left (tight padding), Liquid Glass Star & 3-dots on Right
  Widget _buildMetadataRow(SongItem song, bool isFavorite) {
    return GestureDetector(
      onTap: () {
        if (_controlsAnimController.value < 0.5) {
          _controlsAnimController.forward();
          _startAutoHideTimer();
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (_isExplicit(song.title, song.album))
                      _buildExplicitBadge(),
                    Expanded(
                      child: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppleTypography.playerTitle.copyWith(
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.70),
                              blurRadius: 10,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppleSpacing.titleToSubtitle),
                ApplePressable(
                  onTap: () =>
                      openArtistScreen(context, artistName: song.artist),
                  child: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppleTypography.playerArtist.copyWith(
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.70),
                          blurRadius: 8,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Liquid Glass Star / Favourite Button
          _buildLiquidGlassButton(
            size: 36,
            color: isFavorite
                ? Colors.white.withValues(alpha: 0.24)
                : Colors.white.withValues(alpha: 0.12),
            onTap: () {
              ref.read(favoritesProvider.notifier).toggleFavorite(song);
              _resetAutoHideTimer();
            },
            icon: AnimatedCupertinoIcon(
              icon: isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
              color: Colors.white,
              size: 17,
            ),
          ),
          const SizedBox(width: 8),

          // Liquid Glass 3-dots Button
          _buildLiquidGlassButton(
            size: 36,
            onTap: () {
              _showSongOptionsSheet(song);
              _cancelAutoHideTimer();
            },
            icon: const AnimatedCupertinoIcon(
              icon: CupertinoIcons.ellipsis,
              color: Colors.white,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLyricsContent() {
    return Consumer(
      builder: (context, ref, _) {
        final playerState = ref.watch(playerProvider);
        final effectivePositionMs = _isDraggingSlider
            ? _dragSliderValue.toInt()
            : playerState.position.inMilliseconds;
        final isActuallyPlaying =
            playerState.isPlaying &&
            !playerState.isBuffering &&
            !playerState.isResolvingStream &&
            !_isDraggingSlider;

        return AppleLyricsView(
          lyrics: playerState.lyrics,
          activeLyricIndex: playerState.activeLyricIndex,
          currentPositionMs: effectivePositionMs,
          isPlaying: isActuallyPlaying,
          isLoading: playerState.isLoadingLyrics,
          lyricsSource: playerState.lyricsSource,
          lyricsSongwriters: playerState.lyricsSongwriters,
          selectedProvider: playerState.selectedLyricsProvider,
          onProviderChanged: (provider) {
            ref.read(playerProvider.notifier).setLyricsProvider(provider);
            _resetAutoHideTimer();
          },
          onSeekToLyric: (line) {
            ref.read(playerProvider.notifier).seekToLyric(line);
            _resetAutoHideTimer();
          },
          onTapBackground: _toggleControls,
        );
      },
    );
  }

  Widget _buildQueueContent(SongItem song) {
    return Consumer(
      builder: (context, ref, _) {
        final queue = ref.watch(playerProvider.select((s) => s.queue));
        final autoplayQueue = ref.watch(
          playerProvider.select((s) => s.autoplayQueue),
        );
        final isAutoplay = ref.watch(
          playerProvider.select((s) => s.isAutoplay),
        );
        final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Queue', style: AppleTypography.sectionTitle),
              const SizedBox(height: AppleSpacing.sectionHeaderToContent),

              // Now Playing Item
              const Text('NOW PLAYING', style: AppleTypography.eyebrow),
              const SizedBox(height: 8),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        WavifyCachedImage(
                          imageUrl:
                              song.highResThumbnailUrl ??
                              song.resolvedThumbnailUrl,
                          placeholderImageUrl:
                              song.resolvedThumbnailUrl ?? song.thumbnailUrl,
                          songId: song.id,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.medium,
                          errorWidget: _fallbackMiniArt(
                            size: 48,
                            borderRadius: 8,
                          ),
                        ),
                        if (isPlaying)
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: AnimatedEqualizerBars(
                                isPlaying: true,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            if (_isExplicit(song.title, song.album))
                              _buildExplicitBadge(),
                            Expanded(
                              child: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppleTypography.songTitle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppleSpacing.titleToSubtitle),
                        GestureDetector(
                          onTap: () => openArtistScreen(
                            context,
                            artistName: song.artist,
                          ),
                          child: Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppleTypography.songArtist,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ApplePressable(
                    onTap: () {
                      ref.read(playerProvider.notifier).removeCurrentSong();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        CupertinoIcons.xmark,
                        color: Colors.white.withValues(alpha: 0.45),
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Scrollable Queue & AutoPlay tracklist
              Expanded(
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white,
                        Colors.white,
                        Colors.white,
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.85, 0.94, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.dstIn,
                  child: ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      // Manual Queue items (if any)
                      if (queue.isNotEmpty) ...[
                        const Text(
                          'NEXT IN QUEUE',
                          style: AppleTypography.eyebrow,
                        ),
                        const SizedBox(height: 8),
                        Theme(
                          data: Theme.of(context).copyWith(
                            canvasColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                          ),
                          child: ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: queue.length,
                            buildDefaultDragHandles: false,
                            // ignore: deprecated_member_use
                            onReorder: (oldIndex, newIndex) {
                              ref
                                  .read(playerProvider.notifier)
                                  .reorderQueue(oldIndex, newIndex);
                            },
                            itemBuilder: (context, index) {
                              final item = queue[index];
                              return _buildQueueItemRow(
                                key: ValueKey('manual_q_${item.id}_$index'),
                                index: index,
                                item: item,
                                onRemove: () {
                                  ref
                                      .read(playerProvider.notifier)
                                      .removeFromQueue(index);
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // AutoPlay Section matching Image 2
                      if (isAutoplay) ...[
                        Row(
                          children: const [
                            Icon(
                              CupertinoIcons.infinite,
                              color: Colors.white,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'AutoPlay',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Similar music, selected to play next',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.60),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (autoplayQueue.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  CupertinoActivityIndicator(
                                    color: Colors.white,
                                    radius: 7,
                                  ),
                                  SizedBox(width: 10),
                                  Flexible(
                                    child: Text(
                                      'Discovering similar music from YouTube Music...',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          Theme(
                            data: Theme.of(context).copyWith(
                              canvasColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                            ),
                            child: ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: autoplayQueue.length,
                              buildDefaultDragHandles: false,
                              // ignore: deprecated_member_use
                              onReorder: (oldIndex, newIndex) {
                                ref
                                    .read(playerProvider.notifier)
                                    .reorderAutoplayQueue(oldIndex, newIndex);
                              },
                              itemBuilder: (context, index) {
                                final item = autoplayQueue[index];
                                return _buildQueueItemRow(
                                  key: ValueKey('autoplay_q_${item.id}_$index'),
                                  index: index,
                                  item: item,
                                  onRemove: () {
                                    ref
                                        .read(playerProvider.notifier)
                                        .removeFromAutoplayQueue(index);
                                  },
                                );
                              },
                            ),
                          ),
                      ] else if (queue.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 36),
                            child: Text(
                              'Queue is empty. Turn on AutoPlay for similar tracks.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.50),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQueueItemRow({
    required Key key,
    required int index,
    required SongItem item,
    required VoidCallback onRemove,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Container(
              padding: const EdgeInsets.only(
                right: 12,
                top: 8,
                bottom: 8,
              ),
              color: Colors.transparent,
              child: Icon(
                Icons.drag_handle_rounded,
                color: Colors.white.withValues(alpha: 0.40),
                size: 20,
              ),
            ),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: WavifyCachedImage(
              imageUrl:
                  item.highResThumbnailUrl ?? item.resolvedThumbnailUrl,
              placeholderImageUrl:
                  item.resolvedThumbnailUrl ?? item.thumbnailUrl,
              songId: item.id,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              errorWidget: _fallbackMiniArt(size: 44, borderRadius: 8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () {
                ref
                    .read(playerProvider.notifier)
                    .playSong(item, forceReload: true);
              },
              behavior: HitTestBehavior.opaque,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (_isExplicit(item.title, item.album))
                        _buildExplicitBadge(),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppleTypography.songTitle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppleSpacing.titleToSubtitle),
                  Text(
                    item.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppleTypography.songArtist,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          ApplePressable(
            onTap: onRemove,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                CupertinoIcons.xmark,
                color: Colors.white.withValues(alpha: 0.45),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // SHARED SCRUBBER, CONTROLS & APPLE DOCK
  // =========================================================================
  Widget _buildDurationScrubber() {
    return Consumer(
      builder: (context, ref, _) {
        final duration = ref.watch(playerProvider.select((s) => s.duration));
        final position = ref.watch(playerProvider.select((s) => s.position));
        final currentSong = ref.watch(
          playerProvider.select((s) => s.currentSong),
        );

        int durationMs = duration.inMilliseconds;
        if (durationMs <= 0 && currentSong != null) {
          if (currentSong.durationSeconds != null &&
              currentSong.durationSeconds! > 0) {
            durationMs = currentSong.durationSeconds! * 1000;
          } else {
            final cached = SongMetricsCacheService.instance.getDuration(
              currentSong.id,
            );
            if (cached != null && cached.inMilliseconds > 0) {
              durationMs = cached.inMilliseconds;
            }
          }
        }

        final hasValidDuration = durationMs > 0;
        final totalMs = hasValidDuration ? durationMs.toDouble() : 1.0;

        final currentMs = _isDraggingSlider
            ? _dragSliderValue
            : position.inMilliseconds.toDouble().clamp(0.0, totalMs);

        final elapsedStr = _formatDuration(
          Duration(milliseconds: currentMs.toInt()),
        );
        final remainingStr = hasValidDuration
            ? '-${_formatDuration(Duration(milliseconds: (totalMs - currentMs).toInt()))}'
            : '--:--';

        return AppleMusicSlider(
          value: currentMs,
          max: totalMs,
          elapsedText: elapsedStr,
          remainingText: remainingStr,
          onChangeStart: (_) {
            setState(() => _isDraggingSlider = true);
            _cancelAutoHideTimer();
          },
          onChanged: (val) => setState(() => _dragSliderValue = val),
          onChangeEnd: (val) {
            setState(() => _isDraggingSlider = false);
            ref
                .read(playerProvider.notifier)
                .seek(Duration(milliseconds: val.toInt()));
            _startAutoHideTimer();
          },
        );
      },
    );
  }

  Widget _buildTransportControls() {
    return Consumer(
      builder: (context, ref, _) {
        final notifier = ref.read(playerProvider.notifier);
        final showPauseIcon = ref.watch(
          playerProvider.select((s) => s.isPlaying),
        );
        final isLoading = ref.watch(playerIsLoadingProvider);
        final isTestMode = Platform.environment.containsKey('FLUTTER_TEST');

        Widget playPauseWidget;
        if (isLoading && !isTestMode) {
          playPauseWidget = const SmoothPlayerLoader(
            radius: 18,
            color: Colors.white,
          );
        } else {
          playPauseWidget = AnimatedCupertinoIcon(
            key: ValueKey('main_play_pause_$showPauseIcon'),
            icon: showPauseIcon
                ? CupertinoIcons.pause_fill
                : CupertinoIcons.play_fill,
            color: Colors.white,
            size: 52,
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Previous Track
              IconButton(
                icon: const AnimatedCupertinoIcon(
                  icon: CupertinoIcons.backward_fill,
                  color: Colors.white,
                  size: 40,
                ),
                onPressed: () {
                  notifier.skipPrevious();
                  _resetAutoHideTimer();
                },
                splashRadius: 30,
              ),

              const SizedBox(width: 44),

              // Main Play / Pause button with responsive spring physics & smooth loading indicator
              ApplePressable(
                onTap: () {
                  notifier.togglePlayPause();
                  _resetAutoHideTimer();
                },
                pressedScale: 0.90,
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.80, end: 1.0).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutBack,
                            ),
                          ),
                          child: child,
                        ),
                      );
                    },
                    child: SizedBox(
                      key: ValueKey('transport_loader_${isLoading && !isTestMode}_$showPauseIcon'),
                      width: 72,
                      height: 72,
                      child: Center(child: playPauseWidget),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 44),

              // Next Track
              IconButton(
                icon: const AnimatedCupertinoIcon(
                  icon: CupertinoIcons.forward_fill,
                  color: Colors.white,
                  size: 40,
                ),
                onPressed: () {
                  notifier.skipNext();
                  _resetAutoHideTimer();
                },
                splashRadius: 30,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlaybackCapsuleDock({WidgetRef? explicitRef}) {
    return Consumer(
      builder: (context, ref, _) {
        final actualRef = explicitRef ?? ref;
        final notifier = actualRef.read(playerProvider.notifier);
        final isShuffle = actualRef.watch(
          playerProvider.select((s) => s.isShuffle),
        );
        final loopMode = actualRef.watch(
          playerProvider.select((s) => s.loopMode),
        );
        final isAutoplay = actualRef.watch(
          playerProvider.select((s) => s.isAutoplay),
        );

        return Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(21),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildQueueDockSegment(
                icon: AnimatedCupertinoIcon(
                  icon: CupertinoIcons.shuffle,
                  color: isShuffle
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                  size: 20,
                ),
                isSelected: isShuffle,
                onTap: () {
                  notifier.toggleShuffle();
                  _resetAutoHideTimer();
                },
              ),
              const SizedBox(width: 3),
              _buildQueueDockSegment(
                icon: AnimatedCupertinoIcon(
                  icon: loopMode == LoopMode.one
                      ? CupertinoIcons.repeat_1
                      : CupertinoIcons.repeat,
                  color: loopMode != LoopMode.off
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                  size: 20,
                ),
                isSelected: loopMode != LoopMode.off,
                onTap: () {
                  notifier.cycleLoopMode();
                  _resetAutoHideTimer();
                },
              ),
              const SizedBox(width: 3),
              _buildQueueDockSegment(
                icon: AnimatedCupertinoIcon(
                  icon: CupertinoIcons.infinite,
                  color: isAutoplay
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                  size: 20,
                ),
                isSelected: isAutoplay,
                onTap: () {
                  notifier.toggleAutoplay();
                  _resetAutoHideTimer();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQueueDockSegment({
    required Widget icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ApplePressable(
      onTap: onTap,
      pressedScale: 0.90,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.26)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: icon,
      ),
    );
  }

  Widget _buildActionDock() {
    if (_currentMode == PlayerViewMode.queue) {
      // In Queue mode, display: [Lyrics, Capsule(Shuffle, Repeat, Infinity), Queue Active Card]
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ApplePressable(
            onTap: () => _switchMode(PlayerViewMode.lyrics),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: AnimatedCupertinoIcon(
                icon: CupertinoIcons.quote_bubble,
                color: Colors.white.withValues(alpha: 0.65),
                size: 22,
              ),
            ),
          ),

          // Center Pill Dock for Shuffle, Repeat, Infinity
          _buildPlaybackCapsuleDock(),

          // Queue Active Card (taps to return to Now Playing)
          ApplePressable(
            onTap: () => _switchMode(PlayerViewMode.nowPlaying),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const AnimatedCupertinoIcon(
                icon: CupertinoIcons.list_bullet,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
        ],
      );
    }

    // Default Action Dock: [Lyrics, Speaker, Queue]
    final isLyricsActive = _currentMode == PlayerViewMode.lyrics;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        // Lyrics Toggle Button
        Container(
          decoration: BoxDecoration(
            color: isLyricsActive
                ? Colors.white.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: AnimatedCupertinoIcon(
              icon: isLyricsActive
                  ? CupertinoIcons.quote_bubble_fill
                  : CupertinoIcons.quote_bubble,
              color: isLyricsActive ? Colors.white : Colors.white60,
              size: 24,
            ),
            onPressed: () {
              _switchMode(
                isLyricsActive
                    ? PlayerViewMode.nowPlaying
                    : PlayerViewMode.lyrics,
              );
            },
          ),
        ),

        // Speaker Button (Audio Output Route)
        IconButton(
          icon: const AnimatedCupertinoIcon(
            icon: CupertinoIcons.speaker_2_fill,
            color: Colors.white60,
            size: 24,
          ),
          onPressed: () {
            _showAudioRouteModal();
            _cancelAutoHideTimer();
          },
        ),

        // Queue Toggle Button
        IconButton(
          icon: const AnimatedCupertinoIcon(
            icon: CupertinoIcons.list_bullet,
            color: Colors.white60,
            size: 24,
          ),
          onPressed: () => _switchMode(PlayerViewMode.queue),
        ),
      ],
    );
  }

  Widget _fallbackMiniArt({double size = 40, double borderRadius = 8}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF2C2C2E),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        CupertinoIcons.music_note,
        color: Colors.white38,
        size: size > 48 ? 26 : 22,
      ),
    );
  }
}

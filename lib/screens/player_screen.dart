import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/app_shimmer.dart';
import '../widgets/apple_glass_bottom_sheet.dart';
import '../widgets/apple_music_slider.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/apple_lyrics_view.dart';
import '../widgets/smooth_player_loader.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/wavify_cached_image.dart';

/// Reactive provider extracting the solid primary color strictly from album artwork via PaletteGenerator.
final currentSongPrimaryColorProvider =
    FutureProvider.autoDispose<Color>((ref) async {
  ref.watch(
    playerProvider.select((s) => (s.currentSong?.id, s.currentSong?.thumbnailUrl)),
  );
  final song = ref.read(playerProvider).currentSong;
  if (song == null) return const Color(0xFF1F2438);
  final art = ArtworkColorService.extractableArtworkUrl(
    highResUrl: song.highResThumbnailUrl,
    resolvedUrl: song.resolvedThumbnailUrl,
    thumbnailUrl: song.thumbnailUrl,
  );
  return ArtworkColorService.instance.extractAttractiveColor(
    art,
    fallbackSeed: '${song.title} ${song.artist}',
  );
});

/// Reactive provider extracting the secondary most important color strictly from album artwork.
final currentSongSecondaryColorProvider =
    FutureProvider.autoDispose<Color>((ref) async {
  ref.watch(
    playerProvider.select((s) => (s.currentSong?.id, s.currentSong?.thumbnailUrl)),
  );
  final song = ref.read(playerProvider).currentSong;
  if (song == null) return const Color(0xFF282034);
  final art = ArtworkColorService.extractableArtworkUrl(
    highResUrl: song.highResThumbnailUrl,
    resolvedUrl: song.resolvedThumbnailUrl,
    thumbnailUrl: song.thumbnailUrl,
  );
  return ArtworkColorService.instance.extractSecondaryColor(
    art,
    fallbackSeed: '${song.title} ${song.artist}',
  );
});

/// Reactive provider extracting the dominant (most populated) color in the bottom area and whole album artwork.
final currentSongDominantColorProvider =
    FutureProvider.autoDispose<Color>((ref) async {
  ref.watch(
    playerProvider.select((s) => (s.currentSong?.id, s.currentSong?.thumbnailUrl)),
  );
  final song = ref.read(playerProvider).currentSong;
  if (song == null) return const Color(0xFF141418);
  final art = ArtworkColorService.extractableArtworkUrl(
    highResUrl: song.highResThumbnailUrl,
    resolvedUrl: song.resolvedThumbnailUrl,
    thumbnailUrl: song.thumbnailUrl,
  );
  return ArtworkColorService.instance.extractDominantColor(
    art,
    fallbackSeed: '${song.title} ${song.artist}',
  );
});

/// Reactive provider extracting the brightest vibrant color strictly from album artwork.
final currentSongBestColorProvider =
    FutureProvider.autoDispose<Color>((ref) async {
  ref.watch(
    playerProvider.select((s) => (s.currentSong?.id, s.currentSong?.thumbnailUrl)),
  );
  final song = ref.read(playerProvider).currentSong;
  if (song == null) return const Color(0xFFE10600);
  final art = ArtworkColorService.extractableArtworkUrl(
    highResUrl: song.highResThumbnailUrl,
    resolvedUrl: song.resolvedThumbnailUrl,
    thumbnailUrl: song.thumbnailUrl,
  );
  return ArtworkColorService.instance.extractBestVibrantColor(
    art,
    fallbackSeed: '${song.title} ${song.artist}',
  );
});

enum PlayerViewMode { nowPlaying, lyrics, queue }

class _PlayerScreenColors {
  final Color primary;
  final Color secondary;
  final Color deeper;
  final Color dominant;

  const _PlayerScreenColors({
    required this.primary,
    required this.secondary,
    required this.deeper,
    required this.dominant,
  });

  static _PlayerScreenColors lerp(_PlayerScreenColors a, _PlayerScreenColors b, double t) {
    return _PlayerScreenColors(
      primary: Color.lerp(a.primary, b.primary, t) ?? b.primary,
      secondary: Color.lerp(a.secondary, b.secondary, t) ?? b.secondary,
      deeper: Color.lerp(a.deeper, b.deeper, t) ?? b.deeper,
      dominant: Color.lerp(a.dominant, b.dominant, t) ?? b.dominant,
    );
  }
}

class _PlayerColorsTween extends Tween<_PlayerScreenColors> {
  _PlayerColorsTween({super.end});

  @override
  _PlayerScreenColors lerp(double t) {
    if (begin == null) return end!;
    return _PlayerScreenColors.lerp(begin!, end!, t);
  }
}

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
  int _tabDirection = 1;

  // Downside controls slide & fade animation controller (1.0 = expanded, 0.0 = collapsed downside)
  late AnimationController _controlsAnimController;

  // Mode transition animation controller (0.0 = nowPlaying, 1.0 = lyrics / queue)
  late AnimationController _modeAnimController;

  // Interactive downward drag-to-dismiss state
  double _dragOffsetY = 0.0;
  late AnimationController _dragSnapBackController;
  late Animation<double> _dragSnapBackAnimation;

  // Auto-hide timer for collapsing downside controls after 7s ONLY in lyrics mode
  Timer? _autoHideTimer;

  // Continuous ambient background dynamic fluid flow controller (Apple Music style)
  late final AnimationController _ambientFlowController;

  // Scrubber drag state (local UI interaction only)
  bool _isDraggingSlider = false;
  double _dragSliderValue = 0.0;

  @override
  void initState() {
    super.initState();

    // Downside player collapse/expand animation controller (starts visible)
    _controlsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      value: 1.0,
    );

    // Mode transition controller (0.0 = nowPlaying, 1.0 = lyrics/queue)
    _modeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: _currentMode == PlayerViewMode.nowPlaying ? 0.0 : 1.0,
    );

    // Continuous Apple Music-inspired ambient atmosphere flow
    _ambientFlowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    );
    if (kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST')) {
      _ambientFlowController.repeat(reverse: true);
    }

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

    // Auto-collapse check after initial screen load (Lyrics mode only)
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
    // Auto-hide controls ONLY when in lyrics mode; never move player down in Now Playing or Queue
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
    // Only Lyrics mode hides/restores controls; Now Playing (60/40) and Queue always stay docked
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
      _tabDirection = newMode.index >= oldMode.index ? 1 : -1;
      _currentMode = newMode;
    });

    if (newMode == PlayerViewMode.nowPlaying) {
      _modeAnimController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 400),
        curve: const Cubic(0.16, 1.0, 0.3, 1.0),
      );
      _cancelAutoHideTimer();
      _controlsAnimController.forward();
    } else {
      if (oldMode == PlayerViewMode.nowPlaying) {
        _modeAnimController.animateTo(
          1.0,
          duration: const Duration(milliseconds: 400),
          curve: const Cubic(0.16, 1.0, 0.3, 1.0),
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
    _cancelAutoHideTimer();
    if (_controlsAnimController.value < 1.0) {
      _controlsAnimController.forward();
    }
    showAudioOutputModal(context, ref);
  }

  void _showSongOptionsSheet(SongItem song) {
    _cancelAutoHideTimer();
    if (_controlsAnimController.value < 1.0) {
      _controlsAnimController.forward();
    }
    showTrackOptionsModal(context, ref, song);
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _ambientFlowController.dispose();
    _controlsAnimController.dispose();
    _modeAnimController.dispose();
    _dragSnapBackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(playerProvider.select((s) => s.currentSong));
    // Re-evaluate palette & artwork when master album art asynchronously replaces video thumbnail
    ref.watch(playerProvider.select((s) => s.currentSong?.thumbnailUrl));

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

    // Auto-hide controls ONLY in lyrics mode
    ref.listen<bool>(playerProvider.select((s) => s.isPlaying), (
      previous,
      isPlaying,
    ) {
      if (isPlaying) {
        if (_currentMode == PlayerViewMode.lyrics) {
          _startAutoHideTimer();
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
                // Only Lyrics mode hides/reveals controls; Now Playing (60/40) and Queue always stay docked
                if (_currentMode != PlayerViewMode.lyrics) return;
                if (_controlsAnimController.value < 0.5) {
                  _controlsAnimController.forward();
                }
                _startAutoHideTimer();
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

  /// Derives a rich, saturated Apple Music-inspired palette from the album artwork
  /// rooted in the most populated (dominant) color of the artwork's bottom area,
  /// differentiated with harmonic secondary and vibrant bloom layers so the bottom player
  /// feels living, dynamic, and organic.
  ({
    Color upper,
    Color mid,
    Color lower,
    Color bottomAnchor,
    Color lyricsGlow,
    Color accentBloom,
    Color dominantBottom,
  })
      _computeAtmosphericPalette(SongItem song) {
    final artworkUrl = ArtworkColorService.extractableArtworkUrl(
      highResUrl: song.highResThumbnailUrl,
      resolvedUrl: song.resolvedThumbnailUrl,
      thumbnailUrl: song.thumbnailUrl,
    );
    final seed = '${song.title} ${song.artist}';

    // The most populated color in that bottom area of the whole album art
    final dominantColor = (artworkUrl != null)
        ? (ref.watch(currentSongDominantColorProvider).asData?.value ??
              ArtworkColorService.instance.getCachedDominantColor(artworkUrl) ??
              ArtworkColorService.instance.getFallbackDominantColor(seed))
        : ArtworkColorService.instance.getFallbackDominantColor(seed);

    final bestColor = (artworkUrl != null)
        ? (ref.watch(currentSongBestColorProvider).asData?.value ??
              ArtworkColorService.instance.getCachedBestColor(artworkUrl) ??
              ArtworkColorService.instance.getCachedColor(artworkUrl) ??
              ArtworkColorService.instance.getFallbackBestColor(seed))
        : ArtworkColorService.instance.getFallbackBestColor(seed);

    final primaryColor = (artworkUrl != null)
        ? (ref.watch(currentSongPrimaryColorProvider).asData?.value ??
              ArtworkColorService.instance.getCachedColor(artworkUrl) ??
              bestColor)
        : ArtworkColorService.instance.getFallbackBestColor(seed);

    final secondaryColor = (artworkUrl != null)
        ? (ref.watch(currentSongSecondaryColorProvider).asData?.value ??
              ArtworkColorService.instance.getCachedSecondaryColor(artworkUrl) ??
              primaryColor)
        : ArtworkColorService.instance.getFallbackSecondaryColor(seed);

    final domHsl = HSLColor.fromColor(dominantColor);
    final baseHsl = HSLColor.fromColor(bestColor);
    final primaryHsl = HSLColor.fromColor(primaryColor);
    final secondaryHsl = HSLColor.fromColor(secondaryColor);
    final isNeutral = domHsl.saturation < 0.10 && primaryHsl.saturation < 0.10;

    final double domSat = isNeutral
        ? 0.04
        : (domHsl.saturation * 1.05).clamp(0.35, 0.70);

    // 1. Bottom Anchor: Deep, comfortable OLED base rooted in the most populated color of the artwork
    final Color bottomAnchor = domHsl
        .withSaturation(domSat)
        .withLightness(isNeutral ? 0.07 : 0.11)
        .toColor();

    // 2. Dominant Bottom: Lower foundation for the bottom player area
    final Color dominantBottom = domHsl
        .withSaturation(domSat)
        .withLightness(isNeutral ? 0.10 : 0.15)
        .toColor();

    // 3. Lower Player Body (controls & dock): Differentiated with secondary harmony
    final Color lower = Color.lerp(
      dominantBottom,
      secondaryHsl
          .withSaturation(isNeutral ? 0.05 : 0.55)
          .withLightness(isNeutral ? 0.11 : 0.17)
          .toColor(),
      0.22,
    )!;

    // 4. Mid Player Body (scrubber, metadata, lyrics hook): Differentiated bridge into primary color
    final Color mid = Color.lerp(
      lower,
      primaryHsl
          .withSaturation(isNeutral ? 0.06 : 0.62)
          .withLightness(isNeutral ? 0.17 : 0.25)
          .toColor(),
      0.55,
    )!;

    // 5. Upper Dissolve: Luminous bloom blending into the artwork
    final Color upper = baseHsl
        .withSaturation(isNeutral ? 0.06 : 0.65)
        .withLightness(isNeutral ? 0.22 : 0.32)
        .toColor();

    // 6. Vibrant Accent Bloom: Dynamic Apple Music atmospheric contrast orb
    final Color accentBloom = Color.lerp(bestColor, secondaryColor, 0.40)!;

    // 7. Luminous glow for lyrics / queue
    final Color lyricsGlow = Color.lerp(mid, accentBloom, 0.35)!;

    return (
      upper: upper,
      mid: mid,
      lower: lower,
      bottomAnchor: bottomAnchor,
      lyricsGlow: lyricsGlow,
      accentBloom: accentBloom,
      dominantBottom: dominantBottom,
    );
  }

  Widget _buildAmbientBackdrop(SongItem song, double screenHeight) {
    final artworkUrl = ArtworkColorService.extractableArtworkUrl(
      highResUrl: song.highResThumbnailUrl,
      resolvedUrl: song.resolvedThumbnailUrl,
      thumbnailUrl: song.thumbnailUrl,
    );

    final palette = _computeAtmosphericPalette(song);
    final targetColors = _PlayerScreenColors(
      primary: palette.upper,
      secondary: palette.mid,
      deeper: palette.lower,
      dominant: palette.dominantBottom,
    );

    final Widget staticBlurLayer = (artworkUrl != null)
        ? RepaintBoundary(
            child: Opacity(
              opacity: 0.46,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 60,
                  sigmaY: 60,
                  tileMode: TileMode.mirror,
                ),
                child: WavifyCachedImage(
                  imageUrl: artworkUrl,
                  placeholderImageUrl: song.resolvedThumbnailUrl ?? song.thumbnailUrl,
                  songId: song.id,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.low,
                ),
              ),
            ),
          )
        : const SizedBox.shrink();

    return Positioned.fill(
      child: TweenAnimationBuilder<_PlayerScreenColors>(
        tween: _PlayerColorsTween(end: targetColors),
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
        child: KeyedSubtree(
          key: ValueKey('player_screen_ambient_${song.id}'),
          child: staticBlurLayer,
        ),
        builder: (context, animColors, blurChild) {
          return AnimatedBuilder(
            animation: Listenable.merge([
              _modeAnimController,
              _controlsAnimController,
              _ambientFlowController,
            ]),
            child: blurChild,
            builder: (context, innerChild) {
              final modeVal = _modeAnimController.value;
              final controlsVal = _controlsAnimController.value;
              final flowVal = _ambientFlowController.value;
              final flowSin = math.sin(flowVal * math.pi);
              final flowCos = math.cos(flowVal * math.pi);

              return Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Rich album-tinted foundation rooted in the most populated color of artwork
                  ColoredBox(color: palette.bottomAnchor),
                  if (innerChild != null) Positioned.fill(child: innerChild),

                  // 2. Apple Music-style dynamic floating accent bloom (subtly shifts & breathes)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(
                            -0.30 + 0.45 * flowSin,
                            0.20 + 0.22 * flowCos,
                          ),
                          radius: 1.10 + 0.15 * flowSin,
                          colors: [
                            palette.accentBloom.withValues(
                              alpha: 0.36 + 0.10 * flowSin,
                            ),
                            animColors.secondary.withValues(
                              alpha: 0.20 + 0.06 * flowCos,
                            ),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.55, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // 3. Apple Music-style dynamic secondary bottom radial bloom anchoring the bottom player
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(
                            0.35 - 0.40 * flowCos,
                            0.70 - 0.18 * flowSin,
                          ),
                          radius: 0.95 + 0.10 * flowCos,
                          colors: [
                            animColors.dominant.withValues(alpha: 0.48),
                            animColors.deeper.withValues(alpha: 0.20),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.50, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // 4. Apple Music-style colorful differentiated atmospheric wash extending into bottom player
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            animColors.primary.withValues(alpha: 0.38),
                            animColors.secondary.withValues(alpha: 0.62),
                            animColors.deeper.withValues(alpha: 0.78),
                            animColors.dominant.withValues(alpha: 0.90),
                            palette.bottomAnchor.withValues(alpha: 0.96),
                          ],
                          stops: [
                            0.0,
                            0.40 + 0.03 * flowSin,
                            0.68 + 0.03 * flowCos,
                            0.88,
                            1.0,
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Subtle diagonal wash for Lyrics / Queue translucent surface
                  if (modeVal > 0.001)
                    Positioned.fill(
                      child: Opacity(
                        opacity: modeVal,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                palette.lyricsGlow.withValues(alpha: 0.76),
                                animColors.secondary.withValues(alpha: 0.86),
                                animColors.deeper.withValues(alpha: 0.92),
                                palette.bottomAnchor.withValues(alpha: 0.96),
                              ],
                              stops: const [0.0, 0.36, 0.74, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Soft blur veil across video-to-player transition band (44%..68% vertical zone)
                  if (modeVal < 0.85)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: screenHeight * 0.42,
                      height: screenHeight * 0.28,
                      child: IgnorePointer(
                        child: Opacity(
                          opacity: (1.0 - (modeVal * 1.3)).clamp(0.0, 1.0),
                          child: ClipRect(
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(
                                sigmaX: 20,
                                sigmaY: 20,
                              ),
                              child: const ColoredBox(color: Colors.transparent),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Top status bar scrim for clock & notch icon legibility
                  if (controlsVal > 0.01)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 112,
                      child: Opacity(
                        opacity: controlsVal,
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x52000000),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
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

    // Build heavy image/video canvas ONCE per song/state change outside AnimatedBuilder
    // so tab/mode transitions run at full frame rate with crisp hardware video rendering.
    Widget staticMedia = WavifyCachedImage(
      imageUrl: artworkUrl,
      placeholderImageUrl: song.resolvedThumbnailUrl ?? song.thumbnailUrl,
      songId: song.id,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      filterQuality: FilterQuality.high,
      shimmerBaseColor: Colors.white.withValues(alpha: 0.14),
      shimmerHighlightColor: Colors.white.withValues(alpha: 0.32),
      errorWidget: _fallbackMiniArt(
        size: targetThumbSize,
        borderRadius: 12.0,
      ),
    );

    if (animatedArtworkUrl != null && animatedArtworkUrl.isNotEmpty) {
      staticMedia = Stack(
        fit: StackFit.expand,
        children: [
          staticMedia,
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

    final memoizedArtwork = RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 340),
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
        child: KeyedSubtree(
          key: ValueKey('player_art_switch_${song.album ?? song.id}_${song.id}'),
          child: staticMedia,
        ),
      ),
    );

    return AnimatedBuilder(
      animation: _modeAnimController,
      child: memoizedArtwork,
      builder: (context, artworkChild) {
        final modeVal = CurvedAnimation(
          parent: _modeAnimController,
          curve: const Cubic(0.16, 1.0, 0.3, 1.0),
        ).value;

        // Fixed 60% artwork/video top height in Now Playing mode -> 48px thumbnail in Lyrics/Queue
        final expandedHeight = screenHeight * 0.60;
        final height = ui.lerpDouble(
          expandedHeight,
          targetThumbSize,
          modeVal,
        )!;

        // Interpolate rect geometry between Now Playing 60% canvas and Lyrics/Queue 48x48 header thumbnail
        final left = ui.lerpDouble(0.0, 24.0, modeVal)!;
        final top = ui.lerpDouble(0.0, headerTop, modeVal)!;
        final width = ui.lerpDouble(screenWidth, targetThumbSize, modeVal)!;
        final borderRadius = ui.lerpDouble(0.0, 12.0, modeVal)!;

        // Downward alpha dissolve like previous versions so crisp video fades & mixes
        // organically into the blurred artwork + Apple Music bottom player palette.
        final dissolveFactor = (1.0 - (modeVal * 1.15)).clamp(0.0, 1.0);
        Widget heroContent = Container(
          key: ValueKey('player_screen_artwork_${song.id}'),
          child: artworkChild,
        );
        if (dissolveFactor > 0.02) {
          heroContent = ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black,
                  Colors.black,
                  Color.lerp(Colors.black, const Color(0xE8000000), dissolveFactor)!,
                  Color.lerp(Colors.black, const Color(0x88000000), dissolveFactor)!,
                  Color.lerp(Colors.black, const Color(0x28000000), dissolveFactor)!,
                  Color.lerp(Colors.black, const Color(0x00000000), dissolveFactor)!,
                ],
                stops: const [0.0, 0.64, 0.76, 0.88, 0.96, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: heroContent,
          );
        }

        return Positioned(
          left: left,
          top: top,
          width: width,
          height: height,
          child: GestureDetector(
            onTap: () {
              if (_modeAnimController.value > 0.4) {
                _switchMode(PlayerViewMode.nowPlaying);
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
                          color: Colors.black.withValues(alpha: 0.40 * modeVal),
                          blurRadius: 12 * modeVal,
                          offset: Offset(0, 4 * modeVal),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadius),
                child: Hero(
                  tag: 'player_album_art_${song.id}',
                  flightShuttleBuilder: playerHeroFlightShuttleBuilder,
                  child: heroContent,
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
        final modeVal = CurvedAnimation(
          parent: _modeAnimController,
          curve: const Cubic(0.16, 1.0, 0.3, 1.0),
        ).value;
        if (modeVal == 0.0) {
          return const SizedBox.shrink();
        }

        final opacity = ((modeVal - 0.15) / 0.85).clamp(0.0, 1.0);
        final slideUp = (1.0 - modeVal) * 24.0;
        final controlsVal = _controlsAnimController.value;

        // Exact bottom clearance matching rendered height of _buildBottomControls
        // so neither Lyrics nor Queue ever overflows behind scrubber/transport/dock.
        final double bottomInset = _currentMode == PlayerViewMode.lyrics
            ? ui.lerpDouble(
                math.max(bottomPadding, 16.0) + 16.0,
                bottomPadding + 304.0,
                controlsVal,
              )!
            : (math.max(bottomPadding, 16.0) + 348.0);

        return Positioned(
          top: headerTop + 54,
          left: 0,
          right: 0,
          bottom: bottomInset,
          child: ClipRect(
            child: Opacity(
              opacity: opacity,
              child: Transform.translate(
                offset: Offset(0, slideUp),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: const Cubic(0.16, 1.0, 0.3, 1.0),
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
                    final incomingKey = _currentMode == PlayerViewMode.lyrics
                        ? const ValueKey('lyrics_mode')
                        : const ValueKey('queue_mode');
                    final isIncoming = child.key == incomingKey;
                    final double dx = isIncoming
                        ? (_tabDirection >= 0 ? 0.06 : -0.06)
                        : (_tabDirection >= 0 ? -0.06 : 0.06);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: Offset(dx, 0.0),
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
    return AnimatedBuilder(
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

        // In Now Playing mode:
        // When expanded (controlsVal = 1.0), bottom is bottomPadding + 44.0.
        // When video moves down (controlsVal = 0.0), bottom lerps down to math.max(bottomPadding, 10.0) + 4.0,
        // so that the part up to the slider sits neatly at the bottom edge.
        // In Lyrics mode:
        // When expanded, bottom is bottomPadding + 44.0.
        // When collapsed, controlsVal is 0.0 and all children collapse to height 0.
        final bottomOffset = _currentMode == PlayerViewMode.lyrics
            ? (bottomPadding + 44.0)
            : ui.lerpDouble(
                math.max(bottomPadding, 10.0) + 4.0,
                bottomPadding + 44.0,
                controlsVal,
              )!;

        final gapMetadataToLyrics = ui.lerpDouble(10.0, 16.0, controlsVal)!;
        final gapLyricsToScrubber = ui.lerpDouble(2.0, 4.0, controlsVal)!;
        final gapScrubberToTransport = 36.0;
        final gapTransportToActionDock = 36.0;

        return Positioned(
          left: 0,
          right: 0,
          bottom: bottomOffset,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Metadata Row: Track Title & Artist on Left, Star & 3-dots on Right
                if (modeVal < 0.95)
                  Opacity(
                    opacity: (1.0 - (modeVal * 2.2)).clamp(0.0, 1.0),
                    child: _buildMetadataRow(song, isFavorite),
                  ),

                if (_currentMode != PlayerViewMode.lyrics)
                  SizedBox(height: gapMetadataToLyrics)
                else
                  const SizedBox(height: 8),

                // 2. Lyrics Hook Preview Banner (visible in Now Playing and Queue modes)
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
                  SizedBox(height: gapLyricsToScrubber),
                ],

                // 3. Slider Bar (Duration Scrubber)
                // In Lyrics Mode: Slider collapses with controlsVal so lyrics gets full view
                // In Now Playing Mode: Slider stays visible!
                if (_currentMode == PlayerViewMode.lyrics)
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
                        child: _buildDurationScrubber(),
                      ),
                    ),
                  )
                else
                  _buildDurationScrubber(),

                // 4. Everything after the slider (Player Controls & Action Dock)
                // In Now Playing mode: hidden and moved down when video is playing / collapsed!
                // In Lyrics mode: hidden when collapsed so lyrics gets full view!
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
                        curve: const Interval(0.20, 1.0, curve: Curves.easeOut),
                      ),
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.0, 0.25),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: _controlsAnimController,
                            curve: Curves.easeInOutCubic,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: gapScrubberToTransport),
                            _buildTransportControls(),
                            SizedBox(height: gapTransportToActionDock),
                            _buildActionDock(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
                        style: AppleTypography.playerTitle,
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
                    style: AppleTypography.playerArtist,
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
        final isLoadingAutoplay = ref.watch(
          playerProvider.select((s) => s.isLoadingAutoplay),
        );
        final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
        final palette = _computeAtmosphericPalette(song);

        return RepaintBoundary(
          child: Padding(
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
                            shimmerBaseColor: Colors.white.withValues(alpha: 0.14),
                            shimmerHighlightColor: Colors.white.withValues(alpha: 0.34),
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

                // Lazy sliver-backed Queue & AutoPlay tracklist with top & bottom blurriness and smooth fading
                Expanded(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      canvasColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Scrolling tracklist with top and bottom fading dissolve
                        ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black,
                                Colors.black,
                                Colors.transparent,
                              ],
                              stops: [0.0, 0.05, 0.92, 1.0],
                            ).createShader(bounds);
                          },
                          blendMode: BlendMode.dstIn,
                          child: CustomScrollView(
                            physics: const BouncingScrollPhysics(),
                            slivers: [
                              const SliverToBoxAdapter(
                                child: SizedBox(height: 8),
                              ),
                              if (queue.isNotEmpty) ...[
                                const SliverToBoxAdapter(
                                  child: Padding(
                                    padding: EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      'NEXT IN QUEUE',
                                      style: AppleTypography.eyebrow,
                                    ),
                                  ),
                                ),
                                SliverReorderableList(
                                  itemCount: queue.length,
                                  onReorderItem: (oldIndex, newIndex) {
                                    final adjustedIndex =
                                        newIndex > oldIndex ? newIndex + 1 : newIndex;
                                    ref
                                        .read(playerProvider.notifier)
                                        .reorderQueue(oldIndex, adjustedIndex);
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
                                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                              ],

                              if (isAutoplay) ...[
                                SliverToBoxAdapter(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Row(
                                        children: [
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
                                    ],
                                  ),
                                ),
                                if (autoplayQueue.isEmpty && isLoadingAutoplay)
                                  SliverToBoxAdapter(child: _buildQueueAutoplayShimmer())
                                else if (autoplayQueue.isEmpty)
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              'No similar tracks loaded yet.',
                                              style: TextStyle(
                                                color: Colors.white.withValues(alpha: 0.60),
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                          ApplePressable(
                                            onTap: () => ref
                                                .read(playerProvider.notifier)
                                                .fetchAutoplayQueueForCurrentSong(),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.16),
                                                borderRadius: BorderRadius.circular(14),
                                              ),
                                              child: const Text(
                                                'Retry',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  SliverReorderableList(
                                    itemCount: autoplayQueue.length,
                                    onReorderItem: (oldIndex, newIndex) {
                                      final adjustedIndex = newIndex > oldIndex
                                          ? newIndex + 1
                                          : newIndex;
                                      ref
                                          .read(playerProvider.notifier)
                                          .reorderAutoplayQueue(oldIndex, adjustedIndex);
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
                              ] else if (queue.isEmpty)
                                SliverToBoxAdapter(
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 32),
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
                                ),
                              const SliverToBoxAdapter(child: SizedBox(height: 36)),
                            ],
                          ),
                        ),

                        // Top progressive blur & delicate scrim dissolving songs at the top
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 30,
                          child: IgnorePointer(
                            child: ClipRect(
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        palette.bottomAnchor.withValues(alpha: 0.65),
                                        palette.bottomAnchor.withValues(alpha: 0.15),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.55, 1.0],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Bottom progressive blur & delicate scrim dissolving songs at the bottom
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: 36,
                          child: IgnorePointer(
                            child: ClipRect(
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        palette.bottomAnchor.withValues(alpha: 0.82),
                                        palette.bottomAnchor.withValues(alpha: 0.25),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.60, 1.0],
                                    ),
                                  ),
                                ),
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
          ),
        );
      },
    );
  }

  Widget _buildQueueAutoplayShimmer() {
    return AppShimmer(
      baseColor: Colors.white.withValues(alpha: 0.14),
      highlightColor: Colors.white.withValues(alpha: 0.34),
      child: Column(
        children: List.generate(4, (index) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                ShimmerBox(
                  width: 44,
                  height: 44,
                  borderRadius: BorderRadius.circular(8),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerBox(
                        height: 13,
                        width: index.isEven ? 185 : 155,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(height: 6),
                      ShimmerBox(
                        height: 11,
                        width: 105,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 6.5),
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
              shimmerBaseColor: Colors.white.withValues(alpha: 0.14),
              shimmerHighlightColor: Colors.white.withValues(alpha: 0.34),
              errorWidget: _fallbackMiniArt(size: 44, borderRadius: 8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ApplePressable(
              onTap: () {
                ref
                    .read(playerProvider.notifier)
                    .playSong(item, forceReload: true);
              },
              pressedScale: 0.98,
              borderRadius: BorderRadius.circular(8),
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
            if (_currentMode == PlayerViewMode.lyrics) {
              _startAutoHideTimer();
            }
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
    final isQueueActive = _currentMode == PlayerViewMode.queue;
    final isLyricsActive = _currentMode == PlayerViewMode.lyrics;

    final Widget dockChild = isQueueActive
        ? Row(
            key: const ValueKey('action_dock_queue'),
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
          )
        : Row(
            key: const ValueKey('action_dock_default'),
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

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: const Cubic(0.16, 1.0, 0.3, 1.0),
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: dockChild,
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

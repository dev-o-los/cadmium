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

import '../constants/app_colors.dart';
import '../models/song_item.dart';
import '../providers/favorites_provider.dart';
import '../providers/player_provider.dart';
import '../services/lyrics_service.dart';
import '../services/song_metrics_cache_service.dart';
import '../utils/playback_utils.dart';
import '../widgets/ambient_video_canvas.dart';
import '../widgets/animated_cupertino_icon.dart';
import '../widgets/animated_equalizer_bars.dart';
import '../widgets/apple_glass_bottom_sheet.dart';
import '../widgets/apple_music_slider.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/apple_lyrics_view.dart';
import '../widgets/wavify_cached_image.dart';

enum PlayerViewMode {
  nowPlaying,
  lyrics,
  queue,
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

class _PlayerScreenState extends ConsumerState<PlayerScreen> with TickerProviderStateMixin {
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
    _dragSnapBackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
      setState(() {
        _dragOffsetY = _dragSnapBackAnimation.value;
      });
    });

    // Auto-collapse check after initial screen load if a song is already playing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final isPlaying = ref.read(playerProvider).isPlaying;
        if (isPlaying) {
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
    if (_dragOffsetY > 110 || (details.primaryVelocity != null && details.primaryVelocity! > 400)) {
      Navigator.of(context).pop();
    } else if (_dragOffsetY > 0) {
      _dragSnapBackAnimation = Tween<double>(
        begin: _dragOffsetY,
        end: 0.0,
      ).animate(CurvedAnimation(
        parent: _dragSnapBackController,
        curve: Curves.easeOutCubic,
      ));
      _dragSnapBackController.forward(from: 0.0);
    }
  }

  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    if (!mounted) return;
    final isPlaying = ref.read(playerProvider).isPlaying;
    if (isPlaying && !_isDraggingSlider) {
      _autoHideTimer = Timer(const Duration(seconds: 7), () {
        if (mounted && ref.read(playerProvider).isPlaying && !_isDraggingSlider) {
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
    _startAutoHideTimer();
  }

  void _toggleControls() {
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
    } else if (oldMode == PlayerViewMode.nowPlaying) {
      _modeAnimController.animateTo(
        1.0,
        duration: const Duration(milliseconds: 440),
        curve: Curves.easeInOutCubic,
      );
    }

    // Bring controls into view smoothly when switching modes,
    // and start the auto-hide timer to animate downside gradually
    _controlsAnimController.forward();
    _startAutoHideTimer();
  }



  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _showAudioRouteModal() {
    final notifier = ref.read(playerProvider.notifier);
    notifier.refreshAudioDevices();

    showAppleGlassBottomSheet(
      context: context,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final playerState = ref.watch(playerProvider);
            double localVolume = playerState.volume;
            final devices = playerState.availableAudioDevices.isNotEmpty
                ? playerState.availableAudioDevices
                : [playerState.connectedDevice];

            return StatefulBuilder(
              builder: (context, setModalState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: Text(
                        'Audio Output',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ),
                    AppleSheetGroup(
                      children: [
                        for (int i = 0; i < devices.length; i++) ...[
                          if (i > 0) const AppleSheetDivider(),
                          Builder(
                            builder: (context) {
                              final device = devices[i];
                              final isCurrent = device.id == playerState.connectedDevice.id;
                              return AppleSheetActionTile(
                                icon: device.icon,
                                title: device.name,
                                subtitle: device.subtitle,
                                trailing: isCurrent
                                    ? const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.white, size: 22)
                                    : null,
                                onTap: () {
                                  notifier.selectAudioDevice(device);
                                },
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    const AppleSheetDivider(indent: 0, endIndent: 0),
                    const SizedBox(height: 6),
                    AppleSheetGroup(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(CupertinoIcons.volume_mute, color: Colors.white70, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: AppleMusicSlider(
                                  value: localVolume,
                                  min: 0.0,
                                  max: 1.0,
                                  showTimestamps: false,
                                  onChanged: (v) {
                                    setModalState(() => localVolume = v);
                                    notifier.setVolume(v);
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Icon(CupertinoIcons.volume_up, color: Colors.white70, size: 20),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _showSongOptionsSheet(SongItem song) {
    final isFav = ref.read(favoritesProvider.notifier).isFavorite(song.id);

    showAppleGlassBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Track Header
            Padding(
              padding: const EdgeInsets.only(bottom: 14, left: 2, right: 2),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: WavifyCachedImage(
                      imageUrl: song.highResThumbnailUrl ?? song.resolvedThumbnailUrl,
                      placeholderImageUrl: song.resolvedThumbnailUrl ?? song.thumbnailUrl,
                      songId: song.id,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      errorWidget: _fallbackMiniArt(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            openArtistScreen(context, artistName: song.artist);
                          },
                          child: Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Sleek Apple-style Lyrics Provider switcher
            AppleSheetGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Consumer(
                    builder: (context, ref, _) {
                      final selectedProvider = ref.watch(playerProvider.select((s) => s.selectedLyricsProvider));
                      final isLoadingLyrics = ref.watch(playerProvider.select((s) => s.isLoadingLyrics));

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(CupertinoIcons.quote_bubble, color: Colors.white, size: 20),
                              SizedBox(width: 12),
                              Text(
                                'Lyrics Provider',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.22),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildOptionsProviderSegment(
                                  type: LyricsProviderType.lrcRed,
                                  label: 'lrc.red',
                                  icon: CupertinoIcons.sparkles,
                                  isSelected: selectedProvider == LyricsProviderType.lrcRed,
                                  isLoading: isLoadingLyrics && selectedProvider == LyricsProviderType.lrcRed,
                                  onTap: () {
                                    ref.read(playerProvider.notifier).setLyricsProvider(LyricsProviderType.lrcRed);
                                  },
                                ),
                                const SizedBox(width: 3),
                                _buildOptionsProviderSegment(
                                  type: LyricsProviderType.youTube,
                                  label: 'YouTube',
                                  icon: CupertinoIcons.play_rectangle,
                                  isSelected: selectedProvider == LyricsProviderType.youTube,
                                  isLoading: isLoadingLyrics && selectedProvider == LyricsProviderType.youTube,
                                  onTap: () {
                                    ref.read(playerProvider.notifier).setLyricsProvider(LyricsProviderType.youTube);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const AppleSheetDivider(indent: 0, endIndent: 0),
            const SizedBox(height: 6),
            // Actions
            AppleSheetGroup(
              children: [
                AppleSheetActionTile(
                  icon: isFav ? CupertinoIcons.star_fill : CupertinoIcons.star,
                  title: isFav ? 'Remove from Favorites' : 'Add to Favorites',
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(favoritesProvider.notifier).toggleFavorite(song);
                  },
                ),
                const AppleSheetDivider(),
                AppleSheetActionTile(
                  icon: CupertinoIcons.text_badge_plus,
                  title: 'Add to a Playlist...',
                  onTap: () => Navigator.pop(context),
                ),
                const AppleSheetDivider(),
                AppleSheetActionTile(
                  icon: CupertinoIcons.music_albums,
                  title: (song.album != null && song.album!.isNotEmpty) ? 'View Album (${song.album})' : 'View Album',
                  onTap: () => Navigator.pop(context),
                ),
                const AppleSheetDivider(),
                AppleSheetActionTile(
                  icon: CupertinoIcons.person_fill,
                  title: 'Go to Artist (${song.artist})',
                  onTap: () {
                    Navigator.pop(context);
                    openArtistScreen(context, artistName: song.artist);
                  },
                ),
                const AppleSheetDivider(),
                AppleSheetActionTile(
                  icon: CupertinoIcons.share,
                  title: 'Share Song...',
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        );
      },
    );
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
    final playerState = ref.watch(playerProvider);
    final song = playerState.currentSong;

    if (song == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('No song currently playing', style: TextStyle(color: appleSecondaryText)),
        ),
      );
    }

    final isFavorite = ref.watch(favoritesProvider.select((list) => list.any((s) => s.id == song.id)));

    // Auto-hide controls when song starts playing; reveal when paused
    ref.listen<bool>(playerProvider.select((s) => s.isPlaying), (previous, isPlaying) {
      if (isPlaying) {
        _startAutoHideTimer();
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
                // Tapping anywhere reveals controls if collapsed, or resets inactivity timer
                if (_controlsAnimController.value < 0.5) {
                  _controlsAnimController.forward();
                  _startAutoHideTimer();
                } else {
                  _startAutoHideTimer();
                }
              },
              behavior: HitTestBehavior.translucent,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Edge-to-edge Animated Ambient Artwork Canvas with gradual downward blur transition
                  _buildAmbientBackdrop(song, playerState, screenHeight),

                  // 2. Continuous morphing album artwork (animates between Now Playing and Lyrics header, and Hero from miniplayer)
                  _buildMorphingArtwork(
                    song: song,
                    playerState: playerState,
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
                    playerState: playerState,
                    headerTop: math.max(topPadding, 48) + 18.0,
                    bottomPadding: bottomPadding,
                  ),

                  // 5. Bottom Controls (Metadata row in Now Playing, Scrubber, Transport, Dock)
                  _buildBottomControls(
                    song: song,
                    playerState: playerState,
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
    1.05, 0.00, 0.00, 0.00, -2,
    0.00, 1.05, 0.00, 0.00, -2,
    0.00, 0.00, 1.05, 0.00, -2,
    0.00, 0.00, 0.00, 1.00,  0,
  ]);

  Widget _buildAmbientBackdrop(
    SongItem song,
    PlayerStateModel playerState,
    double screenHeight,
  ) {
    final artworkUrl = song.highResThumbnailUrl ?? song.resolvedThumbnailUrl;
    if (artworkUrl == null || artworkUrl.isEmpty) {
      return Container(color: Colors.black);
    }

    final animatedArtworkUrl = playerState.animatedArtworkUrl ?? song.animatedArtworkUrl;

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: Listenable.merge([_ambientAnimController, _modeAnimController]),
        builder: (context, _) {
          final scale = 1.0 + (_ambientAnimController.value * 0.05);
          final modeVal = _modeAnimController.value;

          return Stack(
            fit: StackFit.expand,
            children: [
              // Pitch black AMOLED base
              Container(color: Colors.black),

              // Full-bleed blurred artwork backdrop
              Positioned.fill(
                child: ClipRect(
                  child: Transform.scale(
                    scale: scale * 1.15,
                    alignment: Alignment.topCenter,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                      child: ColorFiltered(
                        colorFilter: _amoledVibrancyFilter,
                        child: WavifyCachedImage(
                          imageUrl: AmbientVideoCanvas.isVideoUrl(animatedArtworkUrl)
                              ? artworkUrl
                              : (animatedArtworkUrl ?? artworkUrl),
                          placeholderImageUrl: song.resolvedThumbnailUrl ?? song.thumbnailUrl,
                          songId: song.id,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          filterQuality: FilterQuality.medium,
                          errorWidget: const SizedBox(),
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .animate(key: ValueKey('player_screen_ambient_${song.id}'))
              .fadeIn(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeOut,
              ),

              // Smooth darkness dissolve in Now Playing expanded mode
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.18),
                        Colors.black.withValues(alpha: 0.62),
                        Colors.black.withValues(alpha: 0.92),
                        Colors.black,
                      ],
                      stops: const [0.0, 0.46, 0.64, 0.78, 0.90, 1.0],
                    ),
                  ),
                ),
              ),

              // Dark overlay tint for Lyrics / Queue mode (fades in as modeVal -> 1.0)
              if (modeVal > 0.0)
                Positioned.fill(
                  child: Container(
                    color: Color.lerp(Colors.transparent, const Color(0xD808080A), modeVal),
                  ),
                ),

              // Top Status Bar Vignette (preserves status icons readability)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 120,
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
            ],
          );
        },
      ),
    );
  }

  Widget _buildMorphingArtwork({
    required SongItem song,
    required PlayerStateModel playerState,
    required double screenWidth,
    required double screenHeight,
    required double headerTop,
  }) {
    final artworkUrl = song.highResThumbnailUrl ?? song.resolvedThumbnailUrl;
    if (artworkUrl == null || artworkUrl.isEmpty) {
      return Container(color: Colors.black);
    }

    final animatedArtworkUrl = playerState.animatedArtworkUrl ?? song.animatedArtworkUrl;
    final animatedArtworkHeaders = playerState.animatedArtworkHeaders;
    final isPlaying = playerState.isPlaying;

    const double targetThumbSize = 48.0;

    return AnimatedBuilder(
      animation: Listenable.merge([_modeAnimController, _ambientAnimController]),
      builder: (context, _) {
        final modeVal = CurvedAnimation(
          parent: _modeAnimController,
          curve: Curves.easeInOutCubic,
        ).value;

        // Subtle breathing zoom scale (1.0 to 1.05) when in expanded nowPlaying mode
        final breathingScale = 1.0 + (_ambientAnimController.value * 0.05 * (1.0 - modeVal));

        // Interpolate rect geometry between Now Playing full canvas and Lyrics 48x48 header thumbnail
        final left = ui.lerpDouble(0.0, 24.0, modeVal)!;
        final top = ui.lerpDouble(0.0, headerTop, modeVal)!;
        final width = ui.lerpDouble(screenWidth, targetThumbSize, modeVal)!;
        final height = ui.lerpDouble(screenHeight * 0.70, targetThumbSize, modeVal)!;
        final borderRadius = ui.lerpDouble(0.0, 12.0, modeVal)!;

        // Base image content
        Widget imageWidget = WavifyCachedImage(
          imageUrl: artworkUrl,
          placeholderImageUrl: song.resolvedThumbnailUrl ?? song.thumbnailUrl,
          songId: song.id,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          filterQuality: FilterQuality.high,
          errorWidget: _fallbackMiniArt(size: targetThumbSize, borderRadius: borderRadius),
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

        // Apply breathing zoom only in Now Playing expanded mode
        imageWidget = Transform.scale(
          scale: breathingScale,
          alignment: Alignment.topCenter,
          child: ColorFiltered(
            colorFilter: _amoledVibrancyFilter,
            child: imageWidget,
          ),
        );

        // Downward blur dissolve shader mask: feathered in expanded mode, crisp in thumbnail mode
        if (modeVal < 0.96) {
          imageWidget = ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black,
                  Colors.black,
                  Color.lerp(const Color(0xEE000000), Colors.black, modeVal)!,
                  Color.lerp(const Color(0x88000000), Colors.black, modeVal)!,
                  Color.lerp(const Color(0x22000000), Colors.black, modeVal)!,
                  Color.lerp(const Color(0x00000000), Colors.black, modeVal)!,
                ],
                stops: const [0.0, 0.58, 0.72, 0.84, 0.94, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.dstIn,
            child: imageWidget,
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
                // Clicking the album art on the music player upside in lyrics tab
                // gradually opens the album art!
                _switchMode(PlayerViewMode.nowPlaying);
              } else {
                // Clicking the album art in now playing toggles downside controls
                _toggleControls();
              }
            },
            onVerticalDragStart: (modeVal < 0.3) ? _onVerticalDragStart : null,
            onVerticalDragUpdate: (modeVal < 0.3) ? _onVerticalDragUpdate : null,
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
                    child: imageWidget,
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
    final playingFromText = (song.album != null && song.album!.trim().isNotEmpty)
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
          animation: _modeAnimController,
          builder: (context, _) {
            final modeVal = _modeAnimController.value;

            return Stack(
              children: [
                // 1. Now Playing Top Header: Grab Bar + "Playing from <Album/Artist>"
                if (modeVal < 0.95)
                  Positioned(
                    top: headerTop - 14,
                    left: 36,
                    right: 36,
                    child: Opacity(
                      opacity: (1.0 - (modeVal * 2.5)).clamp(0.0, 1.0),
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
                                    if (_isExplicit(song.title, song.album)) _buildExplicitBadge(),
                                    Expanded(
                                      child: Text(
                                        song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                ApplePressable(
                                  onTap: () => openArtistScreen(context, artistName: song.artist),
                                  child: Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.78),
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildLiquidGlassButton(
                            size: 36,
                            onTap: () => ref.read(favoritesProvider.notifier).toggleFavorite(song),
                            icon: AnimatedCupertinoIcon(
                              icon: isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
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
    required PlayerStateModel playerState,
    required double headerTop,
    required double bottomPadding,
  }) {
    return AnimatedBuilder(
      animation: Listenable.merge([_modeAnimController, _controlsAnimController]),
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
                        child: _buildLyricsContent(playerState),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('queue_mode'),
                        child: _buildQueueContent(playerState, song),
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
    required PlayerStateModel playerState,
    required double bottomPadding,
    required bool isFavorite,
  }) {
    String activeLyric = 'The hook is on the way';
    if (playerState.lyrics.isNotEmpty) {
      if (playerState.activeLyricIndex >= 0 &&
          playerState.activeLyricIndex < playerState.lyrics.length) {
        final lyricText = playerState.lyrics[playerState.activeLyricIndex].text.trim();
        if (lyricText.isNotEmpty) {
          activeLyric = lyricText;
        }
      } else if (playerState.lyrics.first.text.trim().isNotEmpty) {
        activeLyric = playerState.lyrics.first.text.trim();
      }
    }

    return Positioned(
      left: 0,
      right: 0,
      bottom: math.max(bottomPadding, 24) + 68,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Now Playing Metadata Row (Title, Artist, Star, 3-dots)
            // Fades out as lyrics mode opens
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
                    position: Tween<Offset>(
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
                          const SizedBox(height: 10),

                          // Lyrics Hook Preview Banner (visible in Now Playing and Queue modes)
                          if (_currentMode != PlayerViewMode.lyrics) ...[
                            ApplePressable(
                              onTap: () => _switchMode(PlayerViewMode.lyrics),
                              pressedScale: 0.98,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      CupertinoIcons.music_note_2,
                                      color: Colors.white,
                                      size: 15,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 320),
                                        layoutBuilder: (currentChild, previousChildren) {
                                          return Stack(
                                            alignment: Alignment.centerLeft,
                                            children: [
                                              ...previousChildren,
                                              ?currentChild,
                                            ],
                                          );
                                        },
                                        transitionBuilder: (child, animation) {
                                          final isEntering = (child.key as ValueKey<String>?)?.value == activeLyric;
                                          final offsetAnimation = isEntering
                                              ? Tween<Offset>(
                                                  begin: const Offset(0.0, 0.9),
                                                  end: Offset.zero,
                                                ).animate(CurvedAnimation(
                                                  parent: animation,
                                                  curve: Curves.easeOutCubic,
                                                ))
                                              : Tween<Offset>(
                                                  begin: const Offset(0.0, -0.9),
                                                  end: Offset.zero,
                                                ).animate(CurvedAnimation(
                                                  parent: animation,
                                                  curve: Curves.easeInCubic,
                                                ));

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
                                          key: ValueKey<String>(activeLyric),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.85),
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
                                      color: Colors.white.withValues(alpha: 0.45),
                                      size: 12.5,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                          ] else
                            const SizedBox(height: 4),

                          // Scrubber Slider (Apple style sleek bar)
                          _buildDurationScrubber(playerState),
                          const SizedBox(height: 36),

                          // Transport Controls: Skip prev, Play/Pause, Skip next
                          _buildTransportControls(playerState),
                          const SizedBox(height: 36),

                          // Bottom Action Dock: Lyrics, Audio Route, Queue
                          _buildActionDock(playerState),
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
  /// Uses a high-contrast dark frosted glass backing + crisp white border rim + backdrop blur
  /// to ensure the button and icon are sharply visible over any album art (light or dark).
  Widget _buildLiquidGlassButton({
    required Widget icon,
    required VoidCallback onTap,
    double size = 36,
  }) {
    return ApplePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.38),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.32),
                width: 0.9,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 6,
                  offset: const Offset(0, 1.5),
                ),
              ],
            ),
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(child: icon),
              ),
            ),
          ),
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
      child: const Text(
        'E',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
      ),
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
                    if (_isExplicit(song.title, song.album)) _buildExplicitBadge(),
                    Expanded(
                      child: Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.4,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                ApplePressable(
                  onTap: () => openArtistScreen(context, artistName: song.artist),
                  child: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                      height: 1.15,
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



  Widget _buildLyricsContent(PlayerStateModel playerState) {
    final effectivePositionMs = _isDraggingSlider
        ? _dragSliderValue.toInt()
        : playerState.position.inMilliseconds;
    final isActuallyPlaying = playerState.isPlaying &&
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
  }

  Widget _buildQueueContent(PlayerStateModel playerState, SongItem song) {
    final queue = playerState.queue;

    final nextFromTitle = (song.album != null && song.album!.trim().isNotEmpty)
        ? 'Next from: ${song.album!.trim()}'
        : 'Next from: ${song.artist.trim()}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Queue',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),

          // Now Playing Item
          Text(
            'Now playing',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    WavifyCachedImage(
                      imageUrl: song.highResThumbnailUrl ?? song.resolvedThumbnailUrl,
                      placeholderImageUrl: song.resolvedThumbnailUrl ?? song.thumbnailUrl,
                      songId: song.id,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      errorWidget: _fallbackMiniArt(size: 48, borderRadius: 8),
                    ),
                    if (playerState.isPlaying)
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
                        if (_isExplicit(song.title, song.album)) _buildExplicitBadge(),
                        Expanded(
                          child: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    GestureDetector(
                      onTap: () => openArtistScreen(context, artistName: song.artist),
                      child: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.70),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ApplePressable(
                onTap: () {
                  ref.read(playerProvider.notifier).skipNext();
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
          const SizedBox(height: 20),

          // Next From Queue List Header
          Text(
            nextFromTitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),

          // Reorderable Queue Tracklist
          Expanded(
            child: queue.isEmpty
                ? Center(
                    child: Text(
                      'No more songs in queue',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.50),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                : ShaderMask(
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
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        canvasColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                      ),
                      child: ReorderableListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: queue.length,
                        physics: const BouncingScrollPhysics(),
                        buildDefaultDragHandles: false,
                        // ignore: deprecated_member_use
                        onReorder: (oldIndex, newIndex) {
                          ref.read(playerProvider.notifier).reorderQueue(oldIndex, newIndex);
                        },
                        itemBuilder: (context, index) {
                          final item = queue[index];
                          return Container(
                            key: ValueKey('queue_item_${item.id}_$index'),
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                ReorderableDragStartListener(
                                  index: index,
                                  child: Container(
                                    padding: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
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
                                    imageUrl: item.highResThumbnailUrl ?? item.resolvedThumbnailUrl,
                                    placeholderImageUrl: item.resolvedThumbnailUrl ?? item.thumbnailUrl,
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
                                      ref.read(playerProvider.notifier).playSong(item, forceReload: true);
                                    },
                                    behavior: HitTestBehavior.opaque,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            if (_isExplicit(item.title, item.album)) _buildExplicitBadge(),
                                            Expanded(
                                              child: Text(
                                                item.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: -0.2,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          item.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.60),
                                            fontSize: 13,
                                            fontWeight: FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ApplePressable(
                                  onTap: () {
                                    ref.read(playerProvider.notifier).removeFromQueue(index);
                                  },
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
                        },
                      ),
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
  Widget _buildDurationScrubber(PlayerStateModel playerState) {
    int durationMs = playerState.duration.inMilliseconds;
    if (durationMs <= 0 && playerState.currentSong != null) {
      final song = playerState.currentSong!;
      if (song.durationSeconds != null && song.durationSeconds! > 0) {
        durationMs = song.durationSeconds! * 1000;
      } else {
        final cached = SongMetricsCacheService.instance.getDuration(song.id);
        if (cached != null && cached.inMilliseconds > 0) {
          durationMs = cached.inMilliseconds;
        }
      }
    }

    final hasValidDuration = durationMs > 0;
    final totalMs = hasValidDuration ? durationMs.toDouble() : 1.0;

    final currentMs = _isDraggingSlider
        ? _dragSliderValue
        : playerState.position.inMilliseconds.toDouble().clamp(0.0, totalMs);

    final elapsedStr = _formatDuration(Duration(milliseconds: currentMs.toInt()));
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
        ref.read(playerProvider.notifier).seek(Duration(milliseconds: val.toInt()));
        _startAutoHideTimer();
      },
    );
  }

  Widget _buildTransportControls(PlayerStateModel playerState) {
    final notifier = ref.read(playerProvider.notifier);
    final showPauseIcon = playerState.isPlaying;
    final isLoading = ref.watch(playerIsLoadingProvider);
    final isTestMode = Platform.environment.containsKey('FLUTTER_TEST');

    Widget playPauseWidget;
    if (isLoading && !isTestMode) {
      playPauseWidget = const CupertinoActivityIndicator(
        radius: 18,
        color: Colors.white,
      );
    } else {
      playPauseWidget = AnimatedCupertinoIcon(
        icon: showPauseIcon ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
        color: Colors.white,
        size: 52,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Previous Track
          IconButton(
            icon: const AnimatedCupertinoIcon(icon: CupertinoIcons.backward_fill, color: Colors.white, size: 40),
            onPressed: () {
              notifier.skipPrevious();
              _resetAutoHideTimer();
            },
            splashRadius: 30,
          ),

          // Main Play / Pause button
          GestureDetector(
            onTap: () {
              notifier.togglePlayPause();
              _resetAutoHideTimer();
            },
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Center(
                child: playPauseWidget,
              ),
            ),
          ),

          // Next Track
          IconButton(
            icon: const AnimatedCupertinoIcon(icon: CupertinoIcons.forward_fill, color: Colors.white, size: 40),
            onPressed: () {
              notifier.skipNext();
              _resetAutoHideTimer();
            },
            splashRadius: 30,
          ),
        ],
      ),
    );
  }

  Widget _buildQueueDockSegment({
    required Widget icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return ApplePressable(
      onTap: onTap,
      pressedScale: 0.92,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: icon,
      ),
    );
  }

  Widget _buildActionDock(PlayerStateModel playerState) {
    final notifier = ref.read(playerProvider.notifier);

    if (_currentMode == PlayerViewMode.queue) {
      // In Queue mode, display: [Lyrics, Pill(Shuffle, Loop, Infinity), Queue Active Pill]
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildQueueDockSegment(
                  icon: AnimatedCupertinoIcon(
                    icon: CupertinoIcons.shuffle,
                    color: playerState.isShuffle ? Colors.white : Colors.white.withValues(alpha: 0.50),
                    size: 20,
                  ),
                  isSelected: playerState.isShuffle,
                  onTap: () {
                    notifier.toggleShuffle();
                    _resetAutoHideTimer();
                  },
                ),
                _buildQueueDockSegment(
                  icon: AnimatedCupertinoIcon(
                    icon: playerState.loopMode == LoopMode.one
                        ? CupertinoIcons.repeat_1
                        : CupertinoIcons.repeat,
                    color: playerState.loopMode != LoopMode.off ? Colors.white : Colors.white.withValues(alpha: 0.50),
                    size: 20,
                  ),
                  isSelected: playerState.loopMode != LoopMode.off,
                  onTap: () {
                    notifier.cycleLoopMode();
                    _resetAutoHideTimer();
                  },
                ),
                _buildQueueDockSegment(
                  icon: AnimatedCupertinoIcon(
                    icon: CupertinoIcons.infinite,
                    color: Colors.white.withValues(alpha: 0.70),
                    size: 20,
                  ),
                  isSelected: false,
                  onTap: () {},
                ),
              ],
            ),
          ),

          // Queue Active Card (taps to return to Now Playing)
          ApplePressable(
            onTap: () => _switchMode(PlayerViewMode.nowPlaying),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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

    // Default Action Dock: [Lyrics, Output Route, Queue]
    final isLyricsActive = _currentMode == PlayerViewMode.lyrics;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        // Lyrics Toggle Button
        Container(
          decoration: BoxDecoration(
            color: isLyricsActive ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: AnimatedCupertinoIcon(
              icon: isLyricsActive ? CupertinoIcons.quote_bubble_fill : CupertinoIcons.quote_bubble,
              color: isLyricsActive ? Colors.white : Colors.white60,
              size: 24,
            ),
            onPressed: () {
              _switchMode(isLyricsActive ? PlayerViewMode.nowPlaying : PlayerViewMode.lyrics);
            },
          ),
        ),

        // Audio Output Route Button (Android Cast Icon for audio outputs)
        IconButton(
          icon: const Icon(
            Icons.cast_rounded,
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
          icon: const AnimatedCupertinoIcon(icon: CupertinoIcons.list_bullet, color: Colors.white60, size: 24),
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

  Widget _buildOptionsProviderSegment({
    required LyricsProviderType type,
    required String label,
    required IconData icon,
    required bool isSelected,
    bool isLoading = false,
    required VoidCallback onTap,
  }) {
    return ApplePressable(
      onTap: onTap,
      pressedScale: 0.95,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : Colors.white60,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white60,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                letterSpacing: -0.2,
              ),
            ),
            if (isSelected && isLoading) ...[
              const SizedBox(width: 5),
              const CupertinoActivityIndicator(
                radius: 5,
                color: Colors.white,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

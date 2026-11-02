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

import '../models/song_item.dart';
import '../providers/favorites_provider.dart';
import '../providers/player_provider.dart';
import '../services/lyrics_service.dart';
import '../services/song_metrics_cache_service.dart';
import '../utils/playback_utils.dart';
import '../widgets/ambient_video_canvas.dart';
import '../widgets/animated_cupertino_icon.dart';
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
  static const Color appleRed = Color(0xFFFA243C);
  static const Color appleSecondaryText = Color(0xFF8E8E93);

  PlayerViewMode _currentMode = PlayerViewMode.nowPlaying;

  // Background ambient animation controller (subtle 20s breathing zoom)
  late AnimationController _ambientAnimController;

  // Downside controls slide & fade animation controller (1.0 = expanded, 0.0 = collapsed downside)
  late AnimationController _controlsAnimController;

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
    if (_currentMode == newMode) return;
    setState(() {
      _currentMode = newMode;
    });

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

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Audio Output',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        ...devices.map((device) {
                          final isCurrent = device.id == playerState.connectedDevice.id;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: AnimatedCupertinoIcon(
                              icon: device.icon,
                              color: Colors.white,
                              size: 28,
                            ),
                            title: Text(
                              device.name,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              device.subtitle,
                              style: const TextStyle(color: appleSecondaryText),
                            ),
                            trailing: isCurrent
                                ? const Icon(CupertinoIcons.checkmark_circle_fill, color: appleRed)
                                : null,
                            onTap: () {
                              notifier.selectAudioDevice(device);
                            },
                          );
                        }),
                        const Divider(color: Color(0xFF2C2C2E)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(CupertinoIcons.volume_mute, color: appleSecondaryText, size: 20),
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
                            const Icon(CupertinoIcons.volume_up, color: appleSecondaryText, size: 20),
                          ],
                        ),
                      ],
                    ),
                  ),
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

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: song.thumbnailUrl != null
                        ? WavifyCachedImage(
                            imageUrl: song.highResThumbnailUrl ?? song.thumbnailUrl!,
                            songId: song.id,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                            errorWidget: _fallbackMiniArt(),
                          )
                        : _fallbackMiniArt(),
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      openArtistScreen(context, artistName: song.artist);
                    },
                    child: Text(
                      song.artist,
                      maxLines: 1,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75)),
                    ),
                  ),
                ),
                const Divider(color: Color(0xFF2C2C2E)),
                // Sleek Apple-style Lyrics Provider switcher
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
                              SizedBox(width: 14),
                              Text(
                                'Lyrics Provider',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.14),
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
                                const SizedBox(width: 2),
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
                const Divider(color: Color(0xFF2C2C2E)),
                ListTile(
                  leading: Icon(
                    isFav ? CupertinoIcons.star_fill : CupertinoIcons.star,
                    color: isFav ? appleRed : Colors.white,
                  ),
                  title: Text(
                    isFav ? 'Remove from Favorites' : 'Add to Favorites',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(favoritesProvider.notifier).toggleFavorite(song);
                  },
                ),
                ListTile(
                  leading: const Icon(CupertinoIcons.text_badge_plus, color: Colors.white),
                  title: const Text('Add to a Playlist...', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context),
                ),
                ListTile(
                  leading: const Icon(CupertinoIcons.music_albums, color: Colors.white),
                  title: Text(
                    (song.album != null && song.album!.isNotEmpty) ? 'View Album (${song.album})' : 'View Album',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.pop(context),
                ),
                ListTile(
                  leading: const Icon(CupertinoIcons.person_fill, color: Colors.white),
                  title: Text('Go to Artist (${song.artist})', style: const TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    openArtistScreen(context, artistName: song.artist);
                  },
                ),
                ListTile(
                  leading: const Icon(CupertinoIcons.share, color: Colors.white),
                  title: const Text('Share Song...', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _ambientAnimController.dispose();
    _controlsAnimController.dispose();
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
          body: GestureDetector(
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
                // 1. Edge-to-edge Animated Artwork Canvas with gradual downward blur transition
                _buildArtworkCanvas(
                  song,
                  screenHeight,
                  animatedArtworkUrl: playerState.animatedArtworkUrl ?? song.animatedArtworkUrl,
                  animatedArtworkHeaders: playerState.animatedArtworkHeaders,
                  isPlaying: playerState.isPlaying,
                ),

                // 2. Animated Switcher for the Main View (Now Playing, Synced Lyrics, Queue)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _currentMode == PlayerViewMode.nowPlaying
                      ? _buildNowPlayingOverlay(song, playerState, topPadding, bottomPadding, isFavorite)
                      : _buildAlternateModeView(song, playerState, topPadding, bottomPadding, isFavorite),
                ),
              ],
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

  /// Edge-to-edge Artwork Canvas with seamless downward blur dissolve:
  /// - Base layer: full-bleed Gaussian blurred ambient glow (sigma: 42), animated with video motion when available
  /// - Foreground layer: pristine, studio-master crisp artwork (1800x1800 uncompressed) and anti-aliased looping moving artwork ("GIF video")
  /// - Bottom gradient: seamlessly darkens into pure OLED pitch black behind downside controls
  /// - Zero white line / artifact: all shader masks use pure black alpha masks and are clipped with ClipRect
  Widget _buildArtworkCanvas(
    SongItem song,
    double screenHeight, {
    String? animatedArtworkUrl,
    Map<String, String>? animatedArtworkHeaders,
    bool isPlaying = true,
  }) {
    if (song.thumbnailUrl == null) {
      return Container(color: Colors.black);
    }

    final artworkUrl = song.highResThumbnailUrl ?? song.thumbnailUrl!;

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _ambientAnimController,
        builder: (context, child) {
          // Subtle breathing zoom scale (1.0 to 1.05)
          final scale = 1.0 + (_ambientAnimController.value * 0.05);

          return Stack(
            fit: StackFit.expand,
            children: [
              // Solid OLED Pitch Black Base
              Container(color: Colors.black),

              if (_currentMode == PlayerViewMode.nowPlaying) ...[
                // Layer A: Full-bleed blurred artwork backdrop
                // Covers the canvas with a rich Gaussian bokeh blur, animated when animatedArtworkUrl is present
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
                            placeholderImageUrl: song.thumbnailUrl,
                            songId: song.id,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            filterQuality: FilterQuality.medium,
                            errorWidget: WavifyCachedImage(
                              imageUrl: artworkUrl,
                              placeholderImageUrl: song.thumbnailUrl,
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
                  )
                  .scale(
                    begin: const Offset(0.75, 0.75),
                    end: const Offset(1.0, 1.0),
                    duration: const Duration(milliseconds: 550),
                    curve: Curves.easeOutCubic,
                  ),
                ),

                // Layer B: Studio-Master crisp artwork (1800x1800) starting sharp at top and gradually dissolving into Layer A
                // Both layers share identical Alignment.topCenter and BoxFit.cover,
                // creating the seamless illusion of the image gradually blurring as it goes down.
                // Keeps the upper 58% of the canvas 100% tack-sharp before feathering into the blurred base.
                // When animatedArtworkUrl ("GIF video") is available, it plays in loop seamlessly with anti-aliasing.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: screenHeight * 0.76,
                  child: ClipRect(
                    child: ShaderMask(
                      shaderCallback: (bounds) {
                        return const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black,
                            Colors.black,
                            Color(0xEE000000),
                            Color(0x88000000),
                            Color(0x22000000),
                            Color(0x00000000),
                          ],
                          stops: [0.0, 0.58, 0.72, 0.84, 0.94, 1.0],
                        ).createShader(bounds);
                      },
                      blendMode: BlendMode.dstIn,
                      child: Transform.scale(
                        scale: scale,
                        alignment: Alignment.topCenter,
                        child: ColorFiltered(
                          colorFilter: _amoledVibrancyFilter,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // 1. Crystal-clear 1800x1800 studio-master artwork (instant display & razor sharpness)
                              WavifyCachedImage(
                                imageUrl: artworkUrl,
                                placeholderImageUrl: song.thumbnailUrl,
                                songId: song.id,
                                fit: BoxFit.cover,
                                alignment: Alignment.topCenter,
                                filterQuality: FilterQuality.high,
                                errorWidget: const SizedBox(),
                              ),

                              // 2. High-Definition Hardware-Accelerated Ambient Moving Video Canvas (1080p/720p 60fps)
                              if (animatedArtworkUrl != null && animatedArtworkUrl.isNotEmpty)
                                AmbientVideoCanvas(
                                  mediaUrl: animatedArtworkUrl,
                                  headers: animatedArtworkHeaders,
                                  fallbackImageUrl: song.thumbnailUrl,
                                  isPlaying: isPlaying,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.topCenter,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                  .animate(key: ValueKey('player_screen_artwork_${song.id}'))
                  .fadeIn(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                  )
                  .scale(
                    begin: const Offset(0.38, 0.38),
                    end: const Offset(1.0, 1.0),
                    alignment: Alignment.bottomLeft,
                    duration: const Duration(milliseconds: 480),
                    curve: Curves.easeOutCubic,
                  )
                  .move(
                    begin: const Offset(-28, 150),
                    end: Offset.zero,
                    duration: const Duration(milliseconds: 480),
                    curve: Curves.easeOutCubic,
                  ),
                ),

                // Layer C: Smooth Darkness Dissolve
                // Preserves high luminosity across the artwork, darkening into pitch black at the controls
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

                // Layer D: Top Status Bar Vignette (preserves status icons readability)
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
              ] else ...[
                // Lyrics / Queue Mode: atmospheric blurred backdrop with dark tint overlay
                Positioned.fill(
                  child: ClipRect(
                    child: Transform.scale(
                      scale: 1.15,
                      alignment: Alignment.center,
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                        child: ColorFiltered(
                          colorFilter: _amoledVibrancyFilter,
                          child: Image.network(
                            artworkUrl,
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            filterQuality: FilterQuality.medium,
                            isAntiAlias: true,
                            errorBuilder: (_, _, _) => Container(color: Colors.black),
                          ),
                        ),
                      ),
                    ),
                  )
                  .animate(key: ValueKey('player_screen_lyrics_bg_${song.id}'))
                  .fadeIn(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOut,
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    color: const Color(0xD808080A),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // =========================================================================
  // OVERLAY: NOW PLAYING VIEW
  // =========================================================================
  Widget _buildNowPlayingOverlay(
    SongItem song,
    PlayerStateModel playerState,
    double topPadding,
    double bottomPadding,
    bool isFavorite,
  ) {
    final activeLyric = playerState.activeLyricIndex >= 0 &&
            playerState.activeLyricIndex < playerState.lyrics.length
        ? playerState.lyrics[playerState.activeLyricIndex].text
        : 'The hook is on the way';

    final playingFromText = (song.album != null && song.album!.trim().isNotEmpty)
        ? 'Playing from ${song.album!.trim()}'
        : 'Playing from ${song.artist.trim()}';

    return Column(
      key: const ValueKey('now_playing_view'),
      children: [
        // Top Header: "Playing from <Album/Artist>" (safely below camera notch on all devices)
        Padding(
          padding: EdgeInsets.only(
            top: math.max(topPadding, 48) + 18,
            left: 48,
            right: 48,
          ),
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: double.infinity,
              child: Text(
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
            ),
          ),
        ),

        // Middle artwork touch area: tapping toggles downside controls
        Expanded(
          child: GestureDetector(
            onTap: _toggleControls,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),

        // Bottom Section:
        // - Metadata Row: Title, Artist, Favourite, 3-dots (always visible)
        // - Downside Controls: Scrubber, transport controls, dock (collapsible downwards)
        Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, math.max(bottomPadding, 16) + 52),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Metadata Row (stays visible even when downside controls collapse)
              _buildMetadataRow(song, isFavorite),

              // Downside collapsible player controls
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
                          children: [
                            const SizedBox(height: 20),

                            // Lyrics Hook Preview Banner (♫ The hook is on the way >)
                            // Reduced image size, tight spacing to slider
                            GestureDetector(
                              onTap: () => _switchMode(PlayerViewMode.lyrics),
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 0),
                                child: Row(
                                  children: [
                                    const AnimatedCupertinoIcon(
                                      icon: CupertinoIcons.music_note,
                                      color: Colors.white70,
                                      size: 13,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        activeLyric,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withValues(alpha: 0.85),
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                    const Icon(CupertinoIcons.chevron_right, color: appleSecondaryText, size: 13),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),

                            // Scrubber Slider
                            _buildDurationScrubber(playerState),
                            const SizedBox(height: 26),

                            // Transport Controls: Skip prev, Play/Pause, Skip next
                            _buildTransportControls(playerState),
                            const SizedBox(height: 38),

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
      ],
    );
  }

  /// Reusable circular Liquid Glass button for actions like favourite and ellipsis
  Widget _buildLiquidGlassButton({
    required Widget icon,
    required VoidCallback onTap,
    double size = 44,
  }) {
    return ApplePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size / 2),
      child: GlassContainer(
        useOwnLayer: true,
        width: size,
        height: size,
        shape: LiquidRoundedSuperellipse(borderRadius: size / 2),
        color: const Color(0x33FFFFFF),
        settings: const LiquidGlassSettings(
          thickness: 20,
          blur: 24,
          refractiveIndex: 1.18,
          lightIntensity: 0.50,
          specularSharpness: GlassSpecularSharpness.sharp,
        ),
        child: Center(child: icon),
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

  /// Metadata Row: Song Title + Artist on Left (aligned flush), Liquid Glass Star & 3-dots on Right
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
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
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
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Liquid Glass Star / Favourite Button
          _buildLiquidGlassButton(
            size: 44,
            onTap: () {
              ref.read(favoritesProvider.notifier).toggleFavorite(song);
              _resetAutoHideTimer();
            },
            icon: AnimatedCupertinoIcon(
              icon: isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
              color: isFavorite ? appleRed : Colors.white,
              size: 21,
            ),
          ),
          const SizedBox(width: 10),

          // Liquid Glass 3-dots Button
          _buildLiquidGlassButton(
            size: 44,
            onTap: () {
              _showSongOptionsSheet(song);
              _cancelAutoHideTimer();
            },
            icon: const AnimatedCupertinoIcon(
              icon: CupertinoIcons.ellipsis,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // ALTERNATE MODES: LYRICS OR QUEUE VIEW
  // =========================================================================
  Widget _buildAlternateModeView(
    SongItem song,
    PlayerStateModel playerState,
    double topPadding,
    double bottomPadding,
    bool isFavorite,
  ) {
    const double artworkSize = 58.0;

    return Column(
      key: ValueKey('mode_${_currentMode.name}'),
      children: [
        // Top Artwork Header (cleanly below punch-hole camera with generous top padding)
        Padding(
          padding: EdgeInsets.only(
            top: math.max(topPadding, 48) + 18,
            left: 24,
            right: 20,
            bottom: 12,
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _switchMode(PlayerViewMode.nowPlaying),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: artworkSize,
                  height: artworkSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: song.thumbnailUrl != null
                        ? WavifyCachedImage(
                            imageUrl: song.highResThumbnailUrl ?? song.thumbnailUrl!,
                            songId: song.id,
                            width: artworkSize,
                            height: artworkSize,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                            errorWidget: _fallbackMiniArt(size: artworkSize, borderRadius: 12),
                          )
                        : _fallbackMiniArt(size: artworkSize, borderRadius: 12),
                  ),
                )
                .animate(key: ValueKey('player_header_art_${song.id}'))
                .fadeIn(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                )
                .scale(
                  begin: const Offset(0.85, 0.85),
                  end: const Offset(1.0, 1.0),
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                ),
              ),
              const SizedBox(width: 14),
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
                size: 40,
                onTap: () => ref.read(favoritesProvider.notifier).toggleFavorite(song),
                icon: AnimatedCupertinoIcon(
                  icon: isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
                  color: isFavorite ? appleRed : Colors.white70,
                  size: 19,
                ),
              ),
              const SizedBox(width: 8),
              _buildLiquidGlassButton(
                size: 40,
                onTap: () => _showSongOptionsSheet(song),
                icon: const AnimatedCupertinoIcon(
                  icon: CupertinoIcons.ellipsis,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
            ],
          ),
        ),

        // Center Content: Synced Lyrics (opens in full size) or Queue List
        Expanded(
          child: _currentMode == PlayerViewMode.lyrics
              ? _buildLyricsContent(playerState)
              : _buildQueueContent(playerState, song),
        ),

        // Bottom Controls: Collapsible downwards with smooth animation in lyrics mode
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
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(24, 6, 24, math.max(bottomPadding, 16) + 48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildDurationScrubber(playerState),
                        const SizedBox(height: 22),
                        _buildTransportControls(playerState),
                        const SizedBox(height: 36),
                        _buildActionDock(playerState),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Queue',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 14),

          // Now Playing Item
          const Text('Now playing', style: TextStyle(color: appleSecondaryText, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: song.thumbnailUrl != null
                  ? WavifyCachedImage(
                      imageUrl: song.highResThumbnailUrl ?? song.thumbnailUrl!,
                      songId: song.id,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      errorWidget: _fallbackMiniArt(),
                    )
                  : _fallbackMiniArt(),
            ),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            subtitle: GestureDetector(
              onTap: () => openArtistScreen(context, artistName: song.artist),
              child: Text(
                song.artist,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            trailing: const Icon(CupertinoIcons.waveform, color: appleRed, size: 22),
          ),
          const Divider(color: Color(0xFF2C2C2E), height: 24),

          // Next From Queue List
          Text(
            (song.album != null && song.album!.isNotEmpty) ? 'Next from: ${song.album}' : 'Next from: ${song.artist}',
            style: const TextStyle(color: appleSecondaryText, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: queue.isEmpty
                ? const Center(
                    child: Text('No more songs in queue', style: TextStyle(color: appleSecondaryText)),
                  )
                : ListView.separated(
                    itemCount: queue.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final item = queue[index];
                      return Dismissible(
                        key: Key('queue_${item.id}_$index'),
                        direction: DismissDirection.endToStart,
                        onDismissed: (direction) {
                          ref.read(playerProvider.notifier).removeFromQueue(index);
                        },
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          color: Colors.redAccent,
                          child: const Icon(CupertinoIcons.trash, color: Colors.white),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(CupertinoIcons.bars, color: appleSecondaryText, size: 20),
                              const SizedBox(width: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: item.thumbnailUrl != null
                                    ? WavifyCachedImage(
                                        imageUrl: item.highResThumbnailUrl ?? item.thumbnailUrl!,
                                        songId: item.id,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        filterQuality: FilterQuality.medium,
                                        errorWidget: _fallbackMiniArt(),
                                      )
                                    : _fallbackMiniArt(),
                              ),
                            ],
                          ),
                          title: Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            item.artist,
                            maxLines: 1,
                            style: const TextStyle(color: appleSecondaryText, fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(CupertinoIcons.xmark, color: appleSecondaryText, size: 16),
                            onPressed: () {
                              ref.read(playerProvider.notifier).removeFromQueue(index);
                            },
                          ),
                          onTap: () {
                            ref.read(playerProvider.notifier).playSong(item, forceReload: true);
                          },
                        ),
                      );
                    },
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

  Widget _buildActionDock(PlayerStateModel playerState) {
    final notifier = ref.read(playerProvider.notifier);

    if (_currentMode == PlayerViewMode.queue) {
      // In Queue mode, display: [Lyrics, Pill(Shuffle, Loop, Infinity), Queue Active]
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: AnimatedCupertinoIcon(
              icon: CupertinoIcons.quote_bubble,
              color: Colors.white.withValues(alpha: 0.6),
              size: 22,
            ),
            onPressed: () => _switchMode(PlayerViewMode.lyrics),
          ),

          // Center Pill Dock for Shuffle, Repeat, Infinity
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: AnimatedCupertinoIcon(
                    icon: CupertinoIcons.shuffle,
                    color: playerState.isShuffle ? Colors.white : Colors.white38,
                    size: 22,
                  ),
                  onPressed: () {
                    notifier.toggleShuffle();
                    _resetAutoHideTimer();
                  },
                ),
                IconButton(
                  icon: AnimatedCupertinoIcon(
                    icon: playerState.loopMode == LoopMode.one
                        ? CupertinoIcons.repeat_1
                        : CupertinoIcons.repeat,
                    color: playerState.loopMode != LoopMode.off ? Colors.white : Colors.white38,
                    size: 22,
                  ),
                  onPressed: () {
                    notifier.cycleLoopMode();
                    _resetAutoHideTimer();
                  },
                ),
                IconButton(
                  icon: const AnimatedCupertinoIcon(
                    icon: CupertinoIcons.infinite,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: () {},
                ),
              ],
            ),
          ),

          // Queue Active Pill (taps to return to Now Playing)
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const AnimatedCupertinoIcon(icon: CupertinoIcons.list_bullet, color: Colors.white, size: 22),
              onPressed: () => _switchMode(PlayerViewMode.nowPlaying),
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
            color: isLyricsActive ? Colors.white.withValues(alpha: 0.25) : Colors.transparent,
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

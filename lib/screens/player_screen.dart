import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models/song_item.dart';
import '../providers/player_provider.dart';

enum PlayerViewMode {
  nowPlaying,
  lyrics,
  queue,
}

/// Full-Screen Apple Music-inspired Now Playing screen matching reference screenshot:
/// - Edge-to-edge animated artwork canvas extending all the way behind the status bar (no SafeArea)
/// - Seamless vertical gradient dissolve blending artwork smoothly into pure OLED black
/// - Responsive Apple Music transport controls (pure white glyphs on dark background, no circle plate)
/// - High-contrast metadata row: [E] Explicit badge, bold Title, Artist, star & 3-dots action buttons
/// - Real-time lyrics preview hook banner: ♫ The hook is on the way >
/// - Precision time scrubber with mm:ss elapsed and -mm:ss remaining timestamps
/// - Frosted action dock: Synced Lyrics, Audio Output Route (iBall Musiwave), and Queue
/// - 3 Seamless Modes: Now Playing (Artwork), Synced Lyrics (Karaoke), and Queue
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

  // Scrubber drag state (local UI interaction only)
  bool _isDraggingSlider = false;
  double _dragSliderValue = 0.0;

  // Favorite toggle (local UI state)
  bool _isFavorite = false;

  final ScrollController _lyricsScrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    // Ambient background breathing animation (20 seconds continuous smooth oscillation)
    _ambientAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat(reverse: true);
  }

  void _scrollToActiveLyric(int activeIndex) {
    if (_currentMode == PlayerViewMode.lyrics && _lyricsScrollController.hasClients && activeIndex >= 0) {
      final targetOffset = (activeIndex * 72.0) - 140.0;
      _lyricsScrollController.animateTo(
        math.max(0.0, targetOffset),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  void _showAudioRouteModal() {
    final playerState = ref.read(playerProvider);
    final notifier = ref.read(playerProvider.notifier);
    double localVolume = playerState.volume;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
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
                      'AirPlay & Bluetooth',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.headphones_rounded, color: Colors.white, size: 28),
                      title: const Text('iBall Musiwave', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Connected • Spatial Audio Ready', style: TextStyle(color: appleSecondaryText)),
                      trailing: const Icon(Icons.check_circle_rounded, color: appleRed),
                    ),
                    const Divider(color: Color(0xFF2C2C2E)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.volume_mute_rounded, color: appleSecondaryText, size: 20),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                              trackHeight: 4,
                            ),
                            child: Slider(
                              value: localVolume,
                              min: 0.0,
                              max: 1.0,
                              onChanged: (v) {
                                setModalState(() => localVolume = v);
                                notifier.setVolume(v);
                              },
                            ),
                          ),
                        ),
                        const Icon(Icons.volume_up_rounded, color: appleSecondaryText, size: 20),
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
  }

  void _showSongOptionsSheet(SongItem song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
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
                        ? Image.network(
                            song.highResThumbnailUrl ?? song.thumbnailUrl!,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                            cacheWidth: 132,
                            cacheHeight: 132,
                            errorBuilder: (context, error, stackTrace) => _fallbackMiniArt(),
                          )
                        : _fallbackMiniArt(),
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(song.artist, maxLines: 1, style: const TextStyle(color: appleSecondaryText)),
                ),
                const Divider(color: Color(0xFF2C2C2E)),
                ListTile(
                  leading: const Icon(Icons.playlist_add_rounded, color: Colors.white),
                  title: const Text('Add to a Playlist...', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context),
                ),
                ListTile(
                  leading: const Icon(Icons.album_rounded, color: Colors.white),
                  title: Text(
                    (song.album != null && song.album!.isNotEmpty) ? 'View Album (${song.album})' : 'View Album',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.pop(context),
                ),
                ListTile(
                  leading: const Icon(Icons.person_rounded, color: Colors.white),
                  title: Text('Go to Artist (${song.artist})', style: const TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context),
                ),
                ListTile(
                  leading: const Icon(Icons.share_rounded, color: Colors.white),
                  title: const Text('Share Song...', style: TextStyle(color: Colors.white)),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _ambientAnimController.dispose();
    _lyricsScrollController.dispose();
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

    // Scroll lyrics smoothly when active line updates
    ref.listen<int>(playerProvider.select((s) => s.activeLyricIndex), (previous, activeIndex) {
      _scrollToActiveLyric(activeIndex);
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
          body: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Edge-to-edge Animated Artwork Canvas extending behind status bar (y=0)
              _buildArtworkCanvas(song, screenHeight),

              // 2. Animated Switcher for the Main View (Now Playing, Synced Lyrics, Queue)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _currentMode == PlayerViewMode.nowPlaying
                    ? _buildNowPlayingOverlay(song, playerState, topPadding, bottomPadding)
                    : _buildAlternateModeView(song, playerState, topPadding, bottomPadding),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Edge-to-edge Animated Artwork Canvas with downward gradient dissolve
  /// Extending all the way to status bar with no SafeArea widget
  Widget _buildArtworkCanvas(SongItem song, double screenHeight) {
    if (song.thumbnailUrl == null) {
      return Container(color: Colors.black);
    }

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _ambientAnimController,
        builder: (context, child) {
          // Subtle breathing zoom scale (1.0 to 1.055)
          final scale = 1.0 + (_ambientAnimController.value * 0.055);

          return Stack(
            fit: StackFit.expand,
            children: [
              // Solid OLED Pitch Black Base
              Container(color: Colors.black),

              if (_currentMode == PlayerViewMode.nowPlaying) ...[
                // Soft Ambient Bloom behind artwork for realistic lighting
                Positioned(
                  top: -40,
                  left: -40,
                  right: -40,
                  height: screenHeight * 0.72,
                  child: ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black,
                        Colors.black,
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.50, 1.0],
                    ).createShader(bounds),
                    blendMode: BlendMode.dstIn,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 45, sigmaY: 45),
                      child: Image.network(
                        song.highResThumbnailUrl ?? song.thumbnailUrl!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (context, error, stackTrace) => const SizedBox(),
                      ),
                    ),
                  ),
                ),

                // Sharp edge-to-edge Album Artwork extending from y=0
                // Dissolves downward into pure OLED black matching reference screenshot
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: screenHeight * 0.68,
                  child: ShaderMask(
                    shaderCallback: (bounds) {
                      return const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFFFFFFF),
                          Color(0xFFFFFFFF),
                          Color(0xD9FFFFFF),
                          Color(0x66FFFFFF),
                          Color(0x00FFFFFF),
                        ],
                        stops: [0.0, 0.40, 0.65, 0.85, 1.0],
                      ).createShader(bounds);
                    },
                    blendMode: BlendMode.dstIn,
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.center,
                      child: Image.network(
                        song.highResThumbnailUrl ?? song.thumbnailUrl!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
                      ),
                    ),
                  ),
                ),

                // Status Bar Shadow Gradient (ensures status icons & header text are 100% crisp)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 130,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.60),
                          Colors.black.withValues(alpha: 0.20),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),

                // Lower Screen Gradient Wash behind metadata and controls
                Positioned(
                  top: screenHeight * 0.45,
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.85),
                          Colors.black,
                        ],
                        stops: const [0.0, 0.25, 0.60, 1.0],
                      ),
                    ),
                  ),
                ),
              ] else ...[
                // Deep blurred ambient background for Lyrics / Queue modes
                Positioned.fill(
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                    child: Image.network(
                      song.highResThumbnailUrl ?? song.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(color: Colors.black),
                    ),
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
  // OVERLAY: NOW PLAYING VIEW (Matching uploaded screenshot 0bd43f94)
  // =========================================================================
  Widget _buildNowPlayingOverlay(
    SongItem song,
    PlayerStateModel playerState,
    double topPadding,
    double bottomPadding,
  ) {
    final activeLyric = playerState.activeLyricIndex >= 0 &&
            playerState.activeLyricIndex < playerState.lyrics.length
        ? playerState.lyrics[playerState.activeLyricIndex].text
        : 'The hook is on the way';

    final playingFromText = (song.album != null && song.album!.isNotEmpty)
        ? 'Playing from ${song.album}'
        : 'Playing from ${song.artist}';

    return Column(
      key: const ValueKey('now_playing_view'),
      children: [
        // Top Drag Handle & "Playing from <Album/Artist>" (extends behind status bar)
        Padding(
          padding: EdgeInsets.only(top: math.max(topPadding, 24) + 6),
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  playingFromText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),

        const Spacer(),

        // Bottom Content Section: Title, Star, Lyrics Banner, Scrubber, Transport Controls, Dock
        Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, math.max(bottomPadding, 16) + 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Metadata Row: [E] Title + Artist on Left, Star & More on Right
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            _buildExplicitBadge(),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: appleSecondaryText,
                            fontSize: 18,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Circular Star Button
                  GestureDetector(
                    onTap: () => setState(() => _isFavorite = !_isFavorite),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                      child: AnimatedScale(
                        scale: _isFavorite ? 1.15 : 1.0,
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutBack,
                        child: Icon(
                          _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                          color: _isFavorite ? appleRed : Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Circular 3-dots Button
                  GestureDetector(
                    onTap: () => _showSongOptionsSheet(song),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                      child: const Icon(
                        Icons.more_horiz_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Lyrics Hook Preview Banner (♫ The hook is on the way >)
              GestureDetector(
                onTap: () => setState(() => _currentMode = PlayerViewMode.lyrics),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.music_note_rounded, color: Colors.white70, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          activeLyric,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: appleSecondaryText, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // Scrubber Slider
              _buildDurationScrubber(playerState),
              const SizedBox(height: 16),

              // Large Apple Transport Controls: Fast Rewind, Play/Pause (pure white), Fast Forward
              _buildTransportControls(playerState),
              const SizedBox(height: 24),

              // Bottom Action Dock: Lyrics, Audio Route, Queue
              _buildActionDock(playerState),
              const SizedBox(height: 8),

              // Audio Output Route Label (iBall Musiwave)
              GestureDetector(
                onTap: _showAudioRouteModal,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.headphones_rounded, color: appleSecondaryText, size: 14),
                    const SizedBox(width: 6),
                    const Text(
                      'iBall Musiwave',
                      style: TextStyle(
                        color: appleSecondaryText,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
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
  ) {
    return Column(
      key: ValueKey('mode_${_currentMode.name}'),
      children: [
        // Top Mini Artwork Header
        Padding(
          padding: EdgeInsets.only(
            top: math.max(topPadding, 24) + 6,
            left: 20,
            right: 20,
            bottom: 8,
          ),
          child: Column(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: song.thumbnailUrl != null
                        ? Image.network(
                            song.highResThumbnailUrl ?? song.thumbnailUrl!,
                            width: 42,
                            height: 42,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.medium,
                            cacheWidth: 126,
                            cacheHeight: 126,
                            errorBuilder: (context, error, stackTrace) => _fallbackMiniArt(),
                          )
                        : _fallbackMiniArt(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildExplicitBadge(),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: appleSecondaryText,
                            fontSize: 13,
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
                      size: 24,
                    ),
                    onPressed: () => setState(() => _isFavorite = !_isFavorite),
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_horiz_rounded, color: Colors.white70, size: 24),
                    onPressed: () => _showSongOptionsSheet(song),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Center Content: Either Synced Lyrics or Queue List
        Expanded(
          child: _currentMode == PlayerViewMode.lyrics
              ? _buildLyricsContent(playerState)
              : _buildQueueContent(playerState, song),
        ),

        // Bottom Controls
        Padding(
          padding: EdgeInsets.fromLTRB(24, 6, 24, math.max(bottomPadding, 16) + 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDurationScrubber(playerState),
              const SizedBox(height: 14),
              _buildTransportControls(playerState),
              const SizedBox(height: 20),
              _buildActionDock(playerState),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showAudioRouteModal,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.headphones_rounded, color: appleSecondaryText, size: 14),
                    const SizedBox(width: 6),
                    const Text(
                      'iBall Musiwave',
                      style: TextStyle(
                        color: appleSecondaryText,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLyricsContent(PlayerStateModel playerState) {
    if (playerState.isLoadingLyrics) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Connecting lyrics...', style: TextStyle(color: appleSecondaryText)),
          ],
        ),
      );
    }

    final lyrics = playerState.lyrics;

    // Requirement: If no lyrics are found, show "No lyrics available right now"
    if (lyrics.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                child: const Icon(
                  Icons.lyrics_outlined,
                  color: appleSecondaryText,
                  size: 36,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'No lyrics available right now',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Lyrics for this track haven\'t been published yet.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListView.builder(
        controller: _lyricsScrollController,
        padding: const EdgeInsets.symmetric(vertical: 24),
        itemCount: lyrics.length + 1,
        itemBuilder: (context, index) {
          // Bottom attribution row (matching screenshot 77f39f89)
          if (index == lyrics.length) {
            return Padding(
              padding: const EdgeInsets.only(top: 28, bottom: 40),
              child: Row(
                children: [
                  const Text(
                    'Lyrics by YouTube Music',
                    style: TextStyle(
                      color: appleSecondaryText,
                      fontSize: 13,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    child: const Icon(Icons.language_rounded, color: Colors.white70, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                    child: const Icon(Icons.translate_rounded, color: Colors.white70, size: 16),
                  ),
                ],
              ),
            );
          }

          final line = lyrics[index];
          final isActive = index == playerState.activeLyricIndex;

          return GestureDetector(
            onTap: () {
              ref.read(playerProvider.notifier).seekToLyric(line);
            },
            behavior: HitTestBehavior.opaque,
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(vertical: isActive ? 14 : 8),
              child: Text(
                line.text,
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.38),
                  fontSize: isActive ? 30 : 23,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                  letterSpacing: -0.5,
                  height: 1.3,
                ),
              ),
            ),
          );
        },
      ),
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
                  ? Image.network(
                      song.highResThumbnailUrl ?? song.thumbnailUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      cacheWidth: 132,
                      cacheHeight: 132,
                      errorBuilder: (context, error, stackTrace) => _fallbackMiniArt(),
                    )
                  : _fallbackMiniArt(),
            ),
            title: Row(
              children: [
                _buildExplicitBadge(),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              song.artist,
              maxLines: 1,
              style: const TextStyle(color: appleSecondaryText, fontSize: 13),
            ),
            trailing: const Icon(Icons.equalizer_rounded, color: appleRed, size: 24),
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
                          child: const Icon(Icons.delete_outline, color: Colors.white),
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.drag_handle_rounded, color: appleSecondaryText, size: 20),
                              const SizedBox(width: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: item.thumbnailUrl != null
                                    ? Image.network(
                                        item.highResThumbnailUrl ?? item.thumbnailUrl!,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        filterQuality: FilterQuality.medium,
                                        cacheWidth: 120,
                                        cacheHeight: 120,
                                        errorBuilder: (context, error, stackTrace) => _fallbackMiniArt(),
                                      )
                                    : _fallbackMiniArt(),
                              ),
                            ],
                          ),
                          title: Row(
                            children: [
                              _buildExplicitBadge(),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            item.artist,
                            maxLines: 1,
                            style: const TextStyle(color: appleSecondaryText, fontSize: 12),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close_rounded, color: appleSecondaryText, size: 18),
                            onPressed: () {
                              ref.read(playerProvider.notifier).removeFromQueue(index);
                            },
                          ),
                          onTap: () {
                            ref.read(playerProvider.notifier).playSong(item);
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
    final totalMs = playerState.duration.inMilliseconds > 0
        ? playerState.duration.inMilliseconds.toDouble()
        : 1.0;

    final currentMs = _isDraggingSlider
        ? _dragSliderValue
        : playerState.position.inMilliseconds.toDouble().clamp(0.0, totalMs);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.5,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
            thumbColor: Colors.white,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4.5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            min: 0.0,
            max: totalMs,
            value: currentMs.clamp(0.0, totalMs),
            onChangeStart: (_) => setState(() => _isDraggingSlider = true),
            onChanged: (val) => setState(() => _dragSliderValue = val),
            onChangeEnd: (val) {
              setState(() => _isDraggingSlider = false);
              ref.read(playerProvider.notifier).seek(Duration(milliseconds: val.toInt()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(Duration(milliseconds: currentMs.toInt())),
                style: const TextStyle(color: appleSecondaryText, fontSize: 12, fontWeight: FontWeight.w500),
              ),
              Text(
                '-${_formatDuration(Duration(milliseconds: (totalMs - currentMs).toInt()))}',
                style: const TextStyle(color: appleSecondaryText, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransportControls(PlayerStateModel playerState) {
    final notifier = ref.read(playerProvider.notifier);
    final showPauseIcon = playerState.isPlaying;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Previous Track
          IconButton(
            icon: const Icon(Icons.fast_rewind_rounded, color: Colors.white, size: 44),
            onPressed: () => notifier.skipPrevious(),
            splashRadius: 30,
          ),

          // Main Play / Pause button (pure white glyphs on dark background, matching Apple Music reference)
          GestureDetector(
            onTap: () => notifier.togglePlayPause(),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Center(
                child: Icon(
                  showPauseIcon ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: showPauseIcon ? 56 : 60,
                ),
              ),
            ),
          ),

          // Next Track
          IconButton(
            icon: const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 44),
            onPressed: () => notifier.skipNext(),
            splashRadius: 30,
          ),
        ],
      ),
    );
  }

  Widget _buildActionDock(PlayerStateModel playerState) {
    final notifier = ref.read(playerProvider.notifier);

    if (_currentMode == PlayerViewMode.queue) {
      // In Queue mode, display: [Lyrics, Pill(Shuffle, Loop, Infinity), Queue Active] (matching Image 2)
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(
              Icons.chat_bubble_outline_rounded,
              color: Colors.white.withValues(alpha: 0.6),
              size: 22,
            ),
            onPressed: () => setState(() => _currentMode = PlayerViewMode.lyrics),
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
                  icon: Icon(
                    Icons.shuffle_rounded,
                    color: playerState.isShuffle ? Colors.white : Colors.white38,
                    size: 22,
                  ),
                  onPressed: () => notifier.toggleShuffle(),
                ),
                IconButton(
                  icon: Icon(
                    playerState.loopMode == LoopMode.one
                        ? Icons.repeat_one_rounded
                        : playerState.loopMode == LoopMode.all
                            ? Icons.repeat_rounded
                            : Icons.repeat_rounded,
                    color: playerState.loopMode != LoopMode.off ? Colors.white : Colors.white38,
                    size: 22,
                  ),
                  onPressed: () => notifier.cycleLoopMode(),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.all_inclusive_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  onPressed: () {},
                ),
              ],
            ),
          ),

          // Queue Active Pill
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.format_list_bulleted_rounded, color: Colors.white, size: 22),
              onPressed: () => setState(() => _currentMode = PlayerViewMode.nowPlaying),
            ),
          ),
        ],
      );
    }

    // Default Action Dock: [Lyrics, Output Route, Queue] (Images 3 & 4)
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
            icon: Icon(
              Icons.chat_bubble_outline_rounded,
              color: isLyricsActive ? Colors.white : Colors.white60,
              size: 24,
            ),
            onPressed: () {
              setState(() {
                _currentMode = isLyricsActive ? PlayerViewMode.nowPlaying : PlayerViewMode.lyrics;
              });
            },
          ),
        ),

        // Headphones / Audio Output Route Button
        IconButton(
          icon: const Icon(Icons.headphones_rounded, color: Colors.white60, size: 24),
          onPressed: _showAudioRouteModal,
        ),

        // Queue Toggle Button
        IconButton(
          icon: const Icon(Icons.format_list_bulleted_rounded, color: Colors.white60, size: 24),
          onPressed: () => setState(() => _currentMode = PlayerViewMode.queue),
        ),
      ],
    );
  }

  Widget _buildExplicitBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text(
        'E',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _fallbackMiniArt() {
    return Container(
      width: 40,
      height: 40,
      color: const Color(0xFF2C2C2E),
      child: const Icon(Icons.music_note_rounded, color: Colors.white38, size: 22),
    );
  }
}

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../models/song_item.dart';
import '../providers/player_provider.dart';

enum PlayerViewMode {
  nowPlaying,
  lyrics,
  queue,
}

/// Full-Screen Apple Music-inspired Now Playing screen powered by Riverpod.
/// Features:
/// - Safe area protection against notch/camera punch holes
/// - Ambient animated artwork canvas background
/// - 3 Seamless Modes: Now Playing (Artwork), Synced Lyrics, and Queue
/// - Zero build-phase setStates: reactive Riverpod state subscriptions
/// - Clear "No lyrics available right now" state when lyrics are unavailable
/// - Interactive scrubbing, transport controls, and AirPlay/Audio output sheet
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> with TickerProviderStateMixin {
  static const Color appleRed = Color(0xFFFA243C);
  static const Color appleSecondaryText = Color(0xFF8E8E93);

  PlayerViewMode _currentMode = PlayerViewMode.nowPlaying;

  // Background ambient animation controller
  late AnimationController _ambientAnimController;

  // Artwork scale animation on play/pause
  late AnimationController _artworkScaleController;
  late Animation<double> _artworkScaleAnimation;

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

    // Artwork scale animation: 1.0 when playing, 0.92 when paused
    _artworkScaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _artworkScaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _artworkScaleController, curve: Curves.easeOutCubic),
    );

    // Initial scale sync
    final initialPlaying = ref.read(playerProvider).isPlaying;
    if (initialPlaying) {
      _artworkScaleController.forward();
    }
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

  @override
  void dispose() {
    _ambientAnimController.dispose();
    _artworkScaleController.dispose();
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

    // Riverpod Event Listeners (Outside of Build)
    // 1. Smoothly scale artwork when play/pause state transitions
    ref.listen<bool>(playerProvider.select((s) => s.isPlaying), (previous, isPlaying) {
      if (isPlaying) {
        if (_artworkScaleController.value != 1.0 && !_artworkScaleController.isAnimating) {
          _artworkScaleController.forward();
        }
      } else {
        if (_artworkScaleController.value != 0.0 && !_artworkScaleController.isAnimating) {
          _artworkScaleController.reverse();
        }
      }
    });

    // 2. Smoothly scroll lyrics when active index advances
    ref.listen<int>(playerProvider.select((s) => s.activeLyricIndex), (previous, activeIndex) {
      _scrollToActiveLyric(activeIndex);
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Dynamic Animated Ambient Background Canvas
          _buildAnimatedBackground(song),

          // 2. Safe Area Content: Guarantees no notch or status bar collision
          SafeArea(
            child: Column(
              children: [
                // Top Drag Handle & Context Header
                _buildTopHeader(song),

                // Center Content Area: Swapped between Artwork, Synced Lyrics, and Queue
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: _buildCurrentView(playerState, song),
                  ),
                ),

                // Bottom Transport Controls, Scrubber & Action Dock
                _buildBottomControlsSection(playerState),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Dynamic Animated Ambient Artwork Canvas Background
  Widget _buildAnimatedBackground(SongItem song) {
    return AnimatedBuilder(
      animation: _ambientAnimController,
      builder: (context, child) {
        final scale = 1.0 + (_ambientAnimController.value * 0.08);
        final rotate = (_ambientAnimController.value - 0.5) * 0.04;

        return Stack(
          children: [
            // Ambient Artwork Scale & Pan
            if (song.thumbnailUrl != null)
              Positioned.fill(
                child: Transform.rotate(
                  angle: rotate,
                  child: Transform.scale(
                    scale: scale,
                    child: Image.network(
                      song.thumbnailUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Container(color: const Color(0xFF1A1A1E)),
                    ),
                  ),
                ),
              ),

            // High Quality Frosted Acrylic Glass Layer
            Positioned.fill(
              child: GlassContainer(
                useOwnLayer: true,
                color: const Color(0xB508080A),
                settings: const LiquidGlassSettings(
                  thickness: 35,
                  blur: 65,
                  refractiveIndex: 1.25,
                  lightIntensity: 0.4,
                  specularSharpness: GlassSpecularSharpness.soft,
                ),
              ),
            ),

            // Dark Linear Gradient Vignette for flawless Apple Music legibility
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.70),
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.88),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Top Header with Notch Safe Distance, Drag Handle and Mode Headers
  Widget _buildTopHeader(SongItem song) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        children: [
          // Centered Drag Handle Pill (Apple Music standard)
          Container(
            width: 38,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 12),

          // Header Row based on current mode
          if (_currentMode == PlayerViewMode.nowPlaying)
            Text(
              'Playing from ${song.artist}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
              ),
            )
          else
            // Header for Lyrics and Queue modes (Mini Artwork + Title + Star + More)
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: song.thumbnailUrl != null
                      ? Image.network(
                          song.thumbnailUrl!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
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
                  onPressed: () {},
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCurrentView(PlayerStateModel playerState, SongItem song) {
    switch (_currentMode) {
      case PlayerViewMode.nowPlaying:
        return _buildNowPlayingView(playerState, song);
      case PlayerViewMode.lyrics:
        return _buildLyricsView(playerState);
      case PlayerViewMode.queue:
        return _buildQueueView(playerState, song);
    }
  }

  // =========================================================================
  // VIEW 1: NOW PLAYING ARTWORK CANVAS (Images 4 & 5)
  // =========================================================================
  Widget _buildNowPlayingView(PlayerStateModel playerState, SongItem song) {
    final activeLyric = playerState.activeLyricIndex >= 0 &&
            playerState.activeLyricIndex < playerState.lyrics.length
        ? playerState.lyrics[playerState.activeLyricIndex].text
        : 'The hook is on the way';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Prominent Scaled Album Artwork (Responsively fits vertical space)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ScaleTransition(
                  scale: _artworkScaleAnimation,
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 28,
                            offset: const Offset(0, 14),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: song.thumbnailUrl != null
                            ? Image.network(
                                song.thumbnailUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => _fallbackLargeArt(),
                              )
                            : _fallbackLargeArt(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Metadata Title Row + Star & Options
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                              fontSize: 22,
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
                        fontSize: 17,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              // Glass Star and More Buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _isFavorite = !_isFavorite),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        _isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                        color: _isFavorite ? appleRed : Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.12),
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
            ],
          ),

          // Real-time Synced Lyric Hook Preview Banner
          GestureDetector(
            onTap: () => setState(() => _currentMode = PlayerViewMode.lyrics),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                  width: 0.6,
                ),
              ),
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
        ],
      ),
    );
  }

  // =========================================================================
  // VIEW 2: REAL-TIME SYNCED LYRICS (Images 1 & 3)
  // =========================================================================
  Widget _buildLyricsView(PlayerStateModel playerState) {
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
        itemCount: lyrics.length,
        itemBuilder: (context, index) {
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

  // =========================================================================
  // VIEW 3: QUEUE VIEW (Image 2)
  // =========================================================================
  Widget _buildQueueView(PlayerStateModel playerState, SongItem song) {
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
                      song.thumbnailUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
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
          Text('Next from: ${song.artist}', style: const TextStyle(color: appleSecondaryText, fontSize: 13, fontWeight: FontWeight.w600)),
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
                                        item.thumbnailUrl!,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
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
  // BOTTOM SCRUBBER, CONTROLS & APPLE ACTION DOCK
  // =========================================================================
  Widget _buildBottomControlsSection(PlayerStateModel playerState) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 24, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Duration Scrubber Bar
          _buildDurationScrubber(playerState),
          const SizedBox(height: 14),

          // Transport Controls: Previous, Play/Pause, Next
          _buildTransportControls(playerState),
          const SizedBox(height: 20),

          // Apple Music Action Dock: Lyrics, Audio Route, Queue
          _buildActionDock(playerState),
          const SizedBox(height: 8),

          // Audio Output Route Label
          GestureDetector(
            onTap: _showAudioRouteModal,
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
    );
  }

  Widget _buildDurationScrubber(PlayerStateModel playerState) {
    final totalMs = playerState.duration.inMilliseconds > 0
        ? playerState.duration.inMilliseconds.toDouble()
        : 1.0;

    final currentMs = _isDraggingSlider
        ? _dragSliderValue
        : playerState.position.inMilliseconds.toDouble().clamp(0.0, totalMs);

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.5,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
            thumbColor: Colors.white,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            overlayColor: Colors.white.withValues(alpha: 0.12),
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
          padding: const EdgeInsets.symmetric(horizontal: 14),
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
    final showPauseIcon = playerState.isPlaying || playerState.isResolvingStream;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Previous Track
        IconButton(
          icon: const Icon(Icons.fast_rewind_rounded, color: Colors.white, size: 40),
          onPressed: () => notifier.skipPrevious(),
        ),

        // Main Large Play / Pause button
        GestureDetector(
          onTap: () => notifier.togglePlayPause(),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 68,
            height: 68,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Center(
              child: Icon(
                showPauseIcon ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.black,
                size: 42,
              ),
            ),
          ),
        ),

        // Next Track
        IconButton(
          icon: const Icon(Icons.fast_forward_rounded, color: Colors.white, size: 40),
          onPressed: () => notifier.skipNext(),
        ),
      ],
    );
  }

  Widget _buildActionDock(PlayerStateModel playerState) {
    final notifier = ref.read(playerProvider.notifier);

    if (_currentMode == PlayerViewMode.queue) {
      // In Queue mode, display: [Shuffle, Loop, Infinity, Queue Active] (matching Image 2)
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

  Widget _fallbackLargeArt() {
    return Container(
      color: const Color(0xFF2C2C2E),
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: Colors.white24, size: 84),
      ),
    );
  }
}

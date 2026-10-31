import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_item.dart';
import '../models/album_item.dart';
import '../models/video_item.dart';
import '../models/hero_card_item.dart';
import '../models/music_category.dart';
import '../models/home_data.dart';
import '../providers/music_service_provider.dart';
import '../providers/home_data_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/animated_cupertino_icon.dart';
import '../widgets/player_controls.dart';
import '../widgets/liquid_glass_bottom_bar.dart';
import '../widgets/wavify_logo.dart';
import 'player_screen.dart';

/// Main Home Screen featuring Apple Music-inspired dark theme UI,
/// multi-section home feed from YouTube Music, floating liquid glass dock,
/// and reactive Riverpod state management.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  // 4 tabs: 0: Home, 1: Explore, 2: Library, 3: Search
  int _currentTabIndex = 0;

  // Crawl / Minimization state for floating mini player and bottom bar
  bool _isMiniPlayerCrawled = false;
  double _accumulatedScrollDelta = 0.0;

  // Search tab state
  List<SongItem> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  bool _hasSearched = false;

  // Accent & Surface Colors
  static const Color appleRed = Color(0xFFFA243C);
  static const Color appleDarkSurface = Color(0xFF1C1C1E);
  static const Color appleDarkSurfaceHigh = Color(0xFF2C2C2E);
  static const Color appleSecondaryText = Color(0xFF8E8E93);

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final pixels = notification.metrics.pixels;
    if (pixels <= 25) {
      if (_isMiniPlayerCrawled) {
        setState(() => _isMiniPlayerCrawled = false);
      }
      _accumulatedScrollDelta = 0;
      return false;
    }

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.reverse && !_isMiniPlayerCrawled) {
        setState(() => _isMiniPlayerCrawled = true);
      } else if (notification.direction == ScrollDirection.forward && _isMiniPlayerCrawled) {
        setState(() => _isMiniPlayerCrawled = false);
      }
    } else if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;
      if (delta > 0) {
        _accumulatedScrollDelta = (_accumulatedScrollDelta > 0 ? _accumulatedScrollDelta : 0) + delta;
        if (_accumulatedScrollDelta > 20 && !_isMiniPlayerCrawled) {
          setState(() => _isMiniPlayerCrawled = true);
        }
      } else if (delta < 0) {
        _accumulatedScrollDelta = (_accumulatedScrollDelta < 0 ? _accumulatedScrollDelta : 0) + delta;
        if (_accumulatedScrollDelta < -12 && _isMiniPlayerCrawled) {
          setState(() => _isMiniPlayerCrawled = false);
        }
      }
    }

    return false;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSongSelected(SongItem song, {List<SongItem>? contextQueue}) {
    ref
        .read(playerProvider.notifier)
        .playSong(song, contextQueue: contextQueue);
  }

  void _openPlayerScreen() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea:
          false, // Extends player to whole screen up behind the status bar
      backgroundColor: Colors.transparent,
      builder: (context) => const PlayerScreen(),
    );
  }

  Future<void> _handleSearch([String? initialQuery]) async {
    final query = initialQuery ?? _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
      _hasSearched = true;
      _currentTabIndex = 3; // Switch to Search tab
    });

    try {
      final musicService = ref.read(musicServiceProvider);
      final results = await musicService.searchSongs(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = 'Network error. Please check your connection.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = 'Search failed: ${e.toString()}';
      });
    }
  }

  void _showTrackOptions(SongItem song) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: song.thumbnailUrl != null
                        ? Image.network(
                            song.thumbnailUrl!,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _fallbackSquareArt(),
                          )
                        : _fallbackSquareArt(),
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: appleSecondaryText,
                      fontSize: 13,
                    ),
                  ),
                ),
                const Divider(color: Color(0xFF2C2C2E)),
                ListTile(
                  leading: const Icon(
                    CupertinoIcons.text_badge_plus,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Play Next',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Added "${song.title}" to play next');
                  },
                ),
                ListTile(
                  leading: const Icon(
                    CupertinoIcons.list_bullet_indent,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Add to Queue',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Added "${song.title}" to queue');
                  },
                ),
                ListTile(
                  leading: const Icon(
                    CupertinoIcons.heart,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Add to Favorites',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Saved "${song.title}" to your favorites');
                  },
                ),
                ListTile(
                  leading: const Icon(CupertinoIcons.share, color: Colors.white),
                  title: const Text(
                    'Share Song',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Sharing link for "${song.title}"');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: appleDarkSurfaceHigh,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);

    // Listen for audio stream resolution errors
    ref.listen<String?>(playerProvider.select((s) => s.errorMessage), (
      prev,
      error,
    ) {
      if (error != null) {
        _showSnackBar(error);
        ref.read(playerProvider.notifier).clearErrorMessage();
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Active Tab Page View with Scroll-driven Crawl Observer
          SafeArea(
            bottom: false,
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: IndexedStack(
                index: _currentTabIndex,
                children: [
                  _buildHomeTab(),
                  _buildExploreTab(),
                  _buildLibraryTab(),
                  _buildSearchTab(),
                ],
              ),
            ),
          ),

          // Floating Player + Floating Liquid Glass Navigation Dock
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: LiquidGlassBottomBar(
                currentIndex: _currentTabIndex,
                isCrawled: _isMiniPlayerCrawled,
                onTabSelected: (index) {
                  setState(() {
                    _currentTabIndex = index;
                    _isMiniPlayerCrawled = false;
                  });
                },
                onExpand: () {
                  setState(() {
                    _isMiniPlayerCrawled = false;
                  });
                },
                bottomAccessory: playerState.currentSong != null
                    ? PlayerControls(onTap: _openPlayerScreen)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 1: HOME (Exact match with reference screenshots)
  // =========================================================================
  Widget _buildHomeTab() {
    final homeDataAsync = ref.watch(homeDataProvider);

    return homeDataAsync.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Loading music...',
              style: TextStyle(color: appleSecondaryText, fontSize: 14),
            ),
          ],
        ),
      ),
      error: (err, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_circle,
                size: 52,
                color: appleRed,
              ),
              const SizedBox(height: 12),
              Text(
                'Failed to load music: $err',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => ref.read(homeDataProvider.notifier).refresh(),
                style: FilledButton.styleFrom(
                  backgroundColor: appleDarkSurfaceHigh,
                ),
                child: const Text(
                  'Try Again',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
      data: (data) => _buildHomeContent(data),
    );
  }

  Widget _buildHomeContent(HomeData data) {
    final playerState = ref.watch(playerProvider);

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: appleDarkSurface,
      onRefresh: () => ref.read(homeDataProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 160),
        children: [
          // Top Header: 3-Wave Sound Logo on Left + Profile Avatar on Right
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Signature 3-wave sound logo
                const WavifyLogo(size: 32, color: Colors.white),

                // Circular profile avatar
                GestureDetector(
                  onTap: () {
                    _showSnackBar('Signed in as Utkarsh');
                  },
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.9),
                        width: 1.5,
                      ),
                    ),
                    child: const CircleAvatar(
                      radius: 18,
                      backgroundColor: appleDarkSurfaceHigh,
                      child: Icon(
                        CupertinoIcons.person_crop_circle_fill,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Section 1: "Top Picks for You" Hero Cards Carousel
          _buildTopPicksHeroSection(data.heroCards),
          const SizedBox(height: 28),

          // Section 2: "Recents" (4-item vertical column horizontal paging)
          _build4ItemColumnsSection(title: 'Recents', songs: data.recents),
          const SizedBox(height: 28),

          // Section 3: "Find Your Mood" with "Show all"
          _buildFindYourMoodSection(data.moods),
          const SizedBox(height: 28),

          // Section 4: "Albums & singles"
          _buildAlbumsAndSinglesSection(data.albumsAndSingles),
          const SizedBox(height: 28),

          // Section 5: "Music videos" (16:9 widescreen)
          _buildMusicVideosSection(data.musicVideos),
          const SizedBox(height: 28),

          // Section 6: "Listen again" (listening history from playerProvider)
          if (playerState.recentlyPlayed.isNotEmpty) ...[
            _build4ItemColumnsSection(
              title: 'Listen again',
              subtitle: 'UTKARSH',
              songs: playerState.recentlyPlayed,
            ),
            const SizedBox(height: 28),
          ],

          // Section 7: "Quick picks" (4-item vertical column horizontal paging)
          _build4ItemColumnsSection(
            title: 'Quick picks',
            songs: data.quickPicks,
          ),
          const SizedBox(height: 28),

          // Section 8: "Your daily discover"
          _buildHorizontalSongCarousel(
            title: 'Your daily discover',
            songs: data.dailyDiscover,
          ),
          const SizedBox(height: 28),

          // Section 9: "Trending songs for you"
          _buildHorizontalSongCarousel(
            title: 'Trending songs for you',
            songs: data.trendingSongs,
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // HOME SCREEN SECTION WIDGETS
  // =========================================================================

  /// Top Picks Hero Section with Karan Aujla, Shubh, The Weeknd cards
  Widget _buildTopPicksHeroSection(List<HeroCardItem> heroCards) {
    if (heroCards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Top Picks for You',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.6,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 290,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: heroCards.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final hero = heroCards[index];
              return _buildHeroCard(hero);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeroCard(HeroCardItem hero) {
    final isShubhCard = hero.id.contains('shubh');

    return GestureDetector(
      onTap: () {
        if (hero.playTrack != null) {
          _onSongSelected(hero.playTrack!);
        } else {
          _searchController.text = hero.title;
          _handleSearch(hero.title);
        }
      },
      child: Container(
        width: 236,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Color(hero.primaryColor ?? 0xFF1C1C1E),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              // Background Image or Solid/Gradient fill
              if (hero.imageUrl != null && !isShubhCard)
                Positioned.fill(
                  child: Image.network(
                    hero.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Color(hero.primaryColor ?? 0xFF2A2825),
                    ),
                  ),
                )
              else if (isShubhCard)
                // Shubh & Similar vibrant blue card with circular portraits
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF2575FC),
                          Color(0xFF1D64F2),
                          Color(0xFF0D47A1),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Overlapping circular artist avatars
                        Positioned(
                          top: 40,
                          left: 36,
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 2,
                              ),
                              image: hero.imageUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(hero.imageUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              color: const Color(0xFF333333),
                            ),
                            child: hero.imageUrl == null
                                ? const Icon(
                                    CupertinoIcons.person_crop_circle,
                                    color: Colors.white70,
                                    size: 50,
                                  )
                                : null,
                          ),
                        ),
                        Positioned(
                          top: 110,
                          right: 28,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 2,
                              ),
                              color: const Color(0xFF222222),
                            ),
                            child: const Icon(
                              CupertinoIcons.person_crop_circle,
                              color: Colors.white70,
                              size: 40,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Gradient shading overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.92),
                      ],
                      stops: const [0.35, 0.65, 1.0],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),

              // Bottom card typography
              Positioned(
                left: 14,
                right: 14,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hero.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hero.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hero.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 4-Item Vertical Column with Horizontal Swiping (Recents / Quick picks / Listen again)
  Widget _build4ItemColumnsSection({
    required String title,
    String? subtitle,
    required List<SongItem> songs,
  }) {
    if (songs.isEmpty) return const SizedBox.shrink();

    // Chunk songs into lists of 4
    final chunked = <List<SongItem>>[];
    for (var i = 0; i < songs.length; i += 4) {
      final end = (i + 4 < songs.length) ? i + 4 : songs.length;
      chunked.add(songs.sublist(i, end));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.6,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: appleSecondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 256, // 4 items * 64px each
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: chunked.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, columnIndex) {
              final columnSongs = chunked[columnIndex];
              return SizedBox(
                width: MediaQuery.of(context).size.width * 0.86,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: columnSongs
                      .map((song) => _build4ItemRow(song, contextQueue: songs))
                      .toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _build4ItemRow(SongItem song, {List<SongItem>? contextQueue}) {
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isSelected = currentSong?.id == song.id;

    return SizedBox(
      height: 64,
      child: InkWell(
        onTap: () => _onSongSelected(song, contextQueue: contextQueue),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              // Artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: song.thumbnailUrl != null
                    ? Image.network(
                        song.thumbnailUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _fallbackSquareArt(),
                      )
                    : _fallbackSquareArt(),
              ),
              const SizedBox(width: 12),

              // Title & Artist
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected ? appleRed : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
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

              // 3-dots Menu Icon
              IconButton(
                icon: const AnimatedCupertinoIcon(
                  icon: CupertinoIcons.ellipsis_vertical,
                  color: appleSecondaryText,
                  size: 18,
                ),
                onPressed: () => _showTrackOptions(song),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Find Your Mood Section with Line-Art Icons & 3-Wave Logo
  Widget _buildFindYourMoodSection(List<MusicCategory> moods) {
    final moodDefs = [
      (title: 'Energy', color: const Color(0xFF00D26A), icon: 'lightning'),
      (title: 'Relax', color: const Color(0xFF3FA9F5), icon: 'zen'),
      (title: 'Feeling Blue', color: const Color(0xFF2B4CDE), icon: 'vortex'),
      (title: 'Workout', color: const Color(0xFFFF453A), icon: 'workout'),
      (title: 'Focus', color: const Color(0xFF5E5CE6), icon: 'focus'),
      (title: 'Party', color: const Color(0xFFAF52DE), icon: 'party'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Find Your Mood',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.6,
                ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() => _currentTabIndex = 1);
                },
                child: const Text(
                  'Show all',
                  style: TextStyle(
                    color: appleSecondaryText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 175,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: moodDefs.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final mood = moodDefs[index];
              return GestureDetector(
                onTap: () {
                  _searchController.text = mood.title;
                  _handleSearch(mood.title);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 136,
                      height: 136,
                      decoration: BoxDecoration(
                        color: mood.color,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Stack(
                        children: [
                          const Positioned(
                            top: 10,
                            right: 10,
                            child: WavifyLogo(size: 16, color: Colors.white70),
                          ),
                          Center(child: _buildMoodIcon(mood.icon)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      mood.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMoodIcon(String iconType) {
    switch (iconType) {
      case 'lightning':
        return const Icon(CupertinoIcons.bolt_fill, size: 58, color: Colors.white);
      case 'zen':
        return const ZenStonesIcon(size: 56, color: Colors.white);
      case 'vortex':
        return const VortexRingsIcon(size: 56, color: Colors.white);
      case 'workout':
        return const Icon(
          CupertinoIcons.flame_fill,
          size: 48,
          color: Colors.white,
        );
      case 'focus':
        return const Icon(
          CupertinoIcons.scope,
          size: 48,
          color: Colors.white,
        );
      case 'party':
        return const Icon(
          CupertinoIcons.sparkles,
          size: 48,
          color: Colors.white,
        );
      default:
        return const Icon(
          CupertinoIcons.music_note,
          size: 48,
          color: Colors.white,
        );
    }
  }

  /// Albums & Singles Horizontal Carousel
  Widget _buildAlbumsAndSinglesSection(List<AlbumItem> albums) {
    if (albums.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Albums & singles',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.6,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 204,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: albums.length > 15 ? 15 : albums.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final album = albums[index];
              return GestureDetector(
                onTap: () {
                  _searchController.text = '${album.title} ${album.artist}';
                  _handleSearch('${album.title} ${album.artist}');
                },
                child: SizedBox(
                  width: 142,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: album.thumbnailUrl != null
                            ? Image.network(
                                album.thumbnailUrl!,
                                width: 142,
                                height: 142,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _fallbackSquareArt(),
                              )
                            : _fallbackSquareArt(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        album.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: appleSecondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 16:9 Music Videos Widescreen Carousel
  Widget _buildMusicVideosSection(List<VideoItem> videos) {
    if (videos.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Music videos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.6,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: videos.length > 10 ? 10 : videos.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final video = videos[index];
              return GestureDetector(
                onTap: () {
                  _onSongSelected(
                    SongItem(
                      id: video.id,
                      title: video.title,
                      artist: video.artist,
                      thumbnailUrl: video.thumbnailUrl,
                      durationSeconds: video.durationSeconds,
                    ),
                  );
                },
                child: SizedBox(
                  width: 250,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          children: [
                            video.thumbnailUrl != null
                                ? Image.network(
                                    video.thumbnailUrl!,
                                    width: 250,
                                    height: 140,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                              width: 250,
                                              height: 140,
                                              color: appleDarkSurfaceHigh,
                                              child: const Icon(
                                                CupertinoIcons.play_rectangle_fill,
                                                color: Colors.white24,
                                                size: 40,
                                              ),
                                            ),
                                  )
                                : Container(
                                    width: 250,
                                    height: 140,
                                    color: appleDarkSurfaceHigh,
                                    child: const Icon(
                                      CupertinoIcons.play_rectangle_fill,
                                      color: Colors.white24,
                                      size: 40,
                                    ),
                                  ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  CupertinoIcons.play_fill,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        video.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: appleSecondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Generic Horizontal Song Carousel
  Widget _buildHorizontalSongCarousel({
    required String title,
    required List<SongItem> songs,
  }) {
    if (songs.isEmpty) return const SizedBox.shrink();

    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.6,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: songs.length > 12 ? 12 : songs.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final song = songs[index];
              final isCurrent = currentSong?.id == song.id;

              return GestureDetector(
                onTap: () => _onSongSelected(song, contextQueue: songs),
                child: SizedBox(
                  width: 140,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: song.thumbnailUrl != null
                                ? Image.network(
                                    song.thumbnailUrl!,
                                    width: 140,
                                    height: 140,
                                    fit: BoxFit.cover,
                                    errorBuilder: (
                                      context,
                                      error,
                                      stackTrace,
                                    ) => _fallbackSquareArt(),
                                  )
                                : _fallbackSquareArt(),
                          ),
                          if (isCurrent)
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: appleRed,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(6),
                                child: const Icon(
                                  CupertinoIcons.waveform,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? appleRed : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: appleSecondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _fallbackSquareArt() {
    return Container(
      width: 48,
      height: 48,
      color: appleDarkSurfaceHigh,
      child: const Icon(
        CupertinoIcons.music_note,
        color: Colors.white30,
        size: 24,
      ),
    );
  }

  // =========================================================================
  // TAB 2: EXPLORE (Genres, Moods, Global Hits)
  // =========================================================================
  Widget _buildExploreTab() {
    final homeDataAsync = ref.watch(homeDataProvider);
    final genres = homeDataAsync.valueOrNull?.genres ?? [];
    final trending = homeDataAsync.valueOrNull?.trendingSongs ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 160),
      children: [
        const Text(
          'Explore',
          style: TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.bold,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Genres & Categories',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: genres.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.3,
          ),
          itemBuilder: (context, index) {
            final g = genres[index];
            final color = g.colorValue != null
                ? Color(g.colorValue!).withValues(alpha: 0.85)
                : appleDarkSurfaceHigh;

            return GestureDetector(
              onTap: () {
                _searchController.text = g.title;
                _handleSearch(g.title);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: color,
                ),
                alignment: Alignment.bottomLeft,
                child: Text(
                  g.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 24),
        const Text(
          'Global Hits & Charts',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...trending.take(10).map((track) => _buildSongRow(track)),
      ],
    );
  }

  // =========================================================================
  // TAB 3: LIBRARY
  // =========================================================================
  Widget _buildLibraryTab() {
    final recentlyPlayed = ref.watch(
      playerProvider.select((s) => s.recentlyPlayed),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 160),
      children: [
        const Text(
          'Library',
          style: TextStyle(
            color: Colors.white,
            fontSize: 34,
            fontWeight: FontWeight.bold,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 16),
        _buildLibraryActionTile(CupertinoIcons.music_note_list, 'Playlists'),
        _buildLibraryActionTile(CupertinoIcons.music_note, 'Songs'),
        _buildLibraryActionTile(CupertinoIcons.music_albums, 'Albums'),
        _buildLibraryActionTile(CupertinoIcons.person_2_fill, 'Artists'),
        _buildLibraryActionTile(CupertinoIcons.arrow_down_circle_fill, 'Downloaded'),
        const SizedBox(height: 24),
        const Text(
          'Recently Added',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        if (recentlyPlayed.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No songs played yet. Tap any track to begin listening.',
              style: TextStyle(color: appleSecondaryText),
            ),
          )
        else
          ...recentlyPlayed.map((song) => _buildSongRow(song)),
      ],
    );
  }

  Widget _buildLibraryActionTile(IconData icon, String title) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Colors.white, size: 26),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: const Icon(
        CupertinoIcons.chevron_right,
        color: appleSecondaryText,
        size: 16,
      ),
      onTap: () {},
    );
  }

  // =========================================================================
  // TAB 4: SEARCH
  // =========================================================================
  Widget _buildSearchTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Text(
            'Search',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
              letterSpacing: -1.2,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: appleDarkSurfaceHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.search,
                  color: appleSecondaryText,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      hintText: 'Artists, Songs, Lyrics, and More',
                      hintStyle: TextStyle(
                        color: appleSecondaryText,
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _handleSearch(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() {
                        _searchResults.clear();
                        _hasSearched = false;
                      });
                    },
                    child: const AnimatedCupertinoIcon(
                      icon: CupertinoIcons.clear_thick_circled,
                      color: appleSecondaryText,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _isSearching
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _hasSearched
              ? _buildSearchResultsList()
              : _buildSearchExploration(),
        ),
      ],
    );
  }

  Widget _buildSearchResultsList() {
    if (_searchError != null) {
      return Center(
        child: Text(_searchError!, style: const TextStyle(color: appleRed)),
      );
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Text(
          'No results found.',
          style: TextStyle(color: appleSecondaryText),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) =>
          const Divider(color: Color(0xFF2C2C2E), height: 1, indent: 62),
      itemBuilder: (context, index) {
        final song = _searchResults[index];
        return _buildSongRow(song);
      },
    );
  }

  Widget _buildSearchExploration() {
    final homeDataAsync = ref.watch(homeDataProvider);
    final genres = homeDataAsync.valueOrNull?.genres ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
      children: [
        const Text(
          'Browse Categories',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: genres.take(16).map((g) {
            return GestureDetector(
              onTap: () {
                _searchController.text = g.title;
                _handleSearch(g.title);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: appleDarkSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Text(
                  g.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSongRow(SongItem song) {
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isSelected = currentSong?.id == song.id;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: song.thumbnailUrl != null
            ? Image.network(
                song.thumbnailUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _fallbackSquareArt(),
              )
            : _fallbackSquareArt(),
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isSelected ? appleRed : Colors.white,
          fontSize: 16,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        song.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: appleSecondaryText, fontSize: 13),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelected)
            const Icon(CupertinoIcons.waveform, color: appleRed, size: 20),
          IconButton(
            icon: const AnimatedCupertinoIcon(
              icon: CupertinoIcons.ellipsis_vertical,
              color: appleSecondaryText,
              size: 18,
            ),
            onPressed: () => _showTrackOptions(song),
          ),
        ],
      ),
      onTap: () => _onSongSelected(song),
    );
  }
}

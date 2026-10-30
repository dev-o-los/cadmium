import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song_item.dart';
import '../models/music_category.dart';
import '../models/home_data.dart';
import '../services/music_service.dart';
import '../widgets/player_controls.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MusicService _musicService = MusicService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _searchController = TextEditingController();

  // 4 tabs: 0: Home, 1: Explore, 2: Library, 3: Search
  int _currentTabIndex = 0;

  HomeData? _homeData;
  bool _isLoadingHome = true;
  String? _homeError;

  // Search tab state
  List<SongItem> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  bool _hasSearched = false;

  // Current playing track
  SongItem? _currentSong;
  bool _isResolvingStream = false;

  // Play history
  final List<SongItem> _recentlyPlayed = [];

  // Apple Music accent colors
  static const Color appleRed = Color(0xFFFA243C);
  static const Color appleDarkSurface = Color(0xFF1C1C1E);
  static const Color appleDarkSurfaceHigh = Color(0xFF2C2C2E);
  static const Color appleSecondaryText = Color(0xFF8E8E93);

  @override
  void initState() {
    super.initState();
    _initServices();
    _setupAudioListeners();
    _loadHomeData();
  }

  void _setupAudioListeners() {
    _audioPlayer.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) {
        debugPrint('Playback stream error: $e');
        if (mounted) {
          setState(() {
            _isResolvingStream = false;
          });
          _showSnackBar('Playback error: Unable to buffer audio stream.');
        }
      },
    );
  }

  Future<void> _initServices() async {
    try {
      await _musicService.initialize();
    } catch (e) {
      debugPrint('MusicService pre-init warning: $e');
    }
  }

  Future<void> _loadHomeData({bool refresh = false}) async {
    setState(() {
      _isLoadingHome = true;
      _homeError = null;
    });

    try {
      final data = await _musicService.getHomeData(refresh: refresh);
      if (!mounted) return;
      setState(() {
        _homeData = data;
        _isLoadingHome = false;
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _isLoadingHome = false;
        _homeError = 'No internet connection. Please verify your network.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingHome = false;
        _homeError = 'Failed to load music: ${e.toString()}';
      });
    }
  }

  /// Handles song selection, stream resolution, and playback
  Future<void> _onSongSelected(SongItem song) async {
    if (_currentSong?.id == song.id) {
      _togglePlayPause();
      return;
    }

    setState(() {
      _currentSong = song;
      _isResolvingStream = true;
      if (!_recentlyPlayed.any((s) => s.id == song.id)) {
        _recentlyPlayed.insert(0, song);
        if (_recentlyPlayed.length > 25) _recentlyPlayed.removeLast();
      }
    });

    try {
      final streamInfo = await _musicService.resolveAudioStream(song.id);

      if (!mounted) return;

      final audioSource = AudioSource.uri(
        Uri.parse(streamInfo.url),
        headers: streamInfo.headers,
      );

      await _audioPlayer.setAudioSource(audioSource, preload: true);
      await _audioPlayer.play();

      if (!mounted) return;
      setState(() {
        _isResolvingStream = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isResolvingStream = false;
      });
      _showSnackBar('Unable to stream "${song.title}": Stream unavailable or restricted.');
      debugPrint('Stream extraction error: $e');
    }
  }

  Future<void> _togglePlayPause() async {
    if (_audioPlayer.processingState == ProcessingState.completed) {
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.play();
      return;
    }

    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }
  }

  void _skipNextTrack() {
    final trending = _homeData?.trendingTracks ?? [];
    if (trending.isNotEmpty && _currentSong != null) {
      final currentIndex = trending.indexWhere((s) => s.id == _currentSong!.id);
      final nextIndex = (currentIndex + 1) % trending.length;
      _onSongSelected(trending[nextIndex]);
    }
  }

  void _skipPreviousTrack() {
    final trending = _homeData?.trendingTracks ?? [];
    if (trending.isNotEmpty && _currentSong != null) {
      final currentIndex = trending.indexWhere((s) => s.id == _currentSong!.id);
      final prevIndex = (currentIndex - 1 + trending.length) % trending.length;
      _onSongSelected(trending[prevIndex]);
    }
  }

  void _openPlayerScreen() {
    if (_currentSong == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: false,
      builder: (context) {
        return PlayerScreen(
          song: _currentSong!,
          audioPlayer: _audioPlayer,
          isResolvingStream: _isResolvingStream,
          onTogglePlayPause: _togglePlayPause,
          onSkipNext: _skipNextTrack,
          onSkipPrevious: _skipPreviousTrack,
        );
      },
    );
  }

  Future<void> _handleSearch([String? customQuery]) async {
    final query = (customQuery ?? _searchController.text).trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = true;
      _searchError = null;
      _hasSearched = true;
      _currentTabIndex = 3; // Switch to Search tab
    });

    try {
      final results = await _musicService.searchSongs(query);
      if (!mounted) return;

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = 'No internet connection.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = 'Search failed: ${e.toString()}';
      });
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
  void dispose() {
    _searchController.dispose();
    _audioPlayer.dispose();
    _musicService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Active Tab Page View
          SafeArea(
            bottom: false,
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

          // Floating Player + Translucent Bottom Navigation Bar Dock
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Apple Music Floating Mini Player
                PlayerControls(
                  currentSong: _currentSong,
                  audioPlayer: _audioPlayer,
                  isResolvingStream: _isResolvingStream,
                  onTogglePlayPause: _togglePlayPause,
                  onSkipNext: _skipNextTrack,
                  onTap: _openPlayerScreen,
                ),

                // 4-Tab Frosted Bottom Navigation Bar (Home, Explore, Library, Search)
                _buildAppleBottomNavigationBar(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Apple Music 4-Tab Navigation Bar: Home, Explore, Library, Search
  Widget _buildAppleBottomNavigationBar() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xEB161618),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.12),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: BottomNavigationBar(
              currentIndex: _currentTabIndex,
              onTap: (index) {
                setState(() {
                  _currentTabIndex = index;
                });
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.explore_rounded),
                  label: 'Explore',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.library_music_rounded),
                  label: 'Library',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.search_rounded),
                  label: 'Search',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 1: HOME (Apple Music "Listen Now" Feed from screenshot)
  // =========================================================================
  Widget _buildHomeTab() {
    if (_isLoadingHome) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: appleRed),
            SizedBox(height: 16),
            Text(
              'Loading music...',
              style: TextStyle(color: appleSecondaryText, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_homeError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 52, color: appleRed),
              const SizedBox(height: 12),
              Text(
                _homeError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => _loadHomeData(refresh: true),
                style: FilledButton.styleFrom(backgroundColor: appleDarkSurfaceHigh),
                child: const Text('Try Again', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final trending = _homeData?.trendingTracks ?? [];
    final quickPicks = _homeData?.quickPicks ?? [];
    final moods = _homeData?.moods ?? [];
    final genres = _homeData?.genres ?? [];

    return RefreshIndicator(
      color: appleRed,
      backgroundColor: appleDarkSurface,
      onRefresh: () => _loadHomeData(refresh: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 140),
        children: [
          // Top Header: "Listen Now" + Profile Avatar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Listen Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -1.2,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    _showSnackBar('Signed in as Music Listener');
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                    ),
                    child: const CircleAvatar(
                      radius: 17,
                      backgroundColor: appleDarkSurfaceHigh,
                      child: Icon(Icons.person, color: Colors.white70, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Section 1: "Top Picks" (Hero Cards Carousel from the screenshot)
          _buildTopPicksHeroSection(trending),

          const SizedBox(height: 24),

          // Section 2: "Recently Played >"
          if (_recentlyPlayed.isNotEmpty) ...[
            _buildSectionHeaderWithChevron(
              title: 'Recently Played',
              onTap: () {},
            ),
            const SizedBox(height: 12),
            _buildHorizontalSquareCards(_recentlyPlayed),
            const SizedBox(height: 24),
          ],

          // Section 3: "Trending Songs >"
          _buildSectionHeaderWithChevron(
            title: 'Trending Tracks',
            onTap: () {},
          ),
          const SizedBox(height: 12),
          _buildHorizontalSquareCards(trending.skip(3).toList()),

          const SizedBox(height: 24),

          // Section 4: "Quick Picks >"
          if (quickPicks.isNotEmpty) ...[
            _buildSectionHeaderWithChevron(
              title: 'Quick Picks',
              onTap: () {},
            ),
            const SizedBox(height: 12),
            _buildHorizontalSquareCards(quickPicks),
            const SizedBox(height: 24),
          ],

          // Section 5: "Moods & Moments"
          if (moods.isNotEmpty) ...[
            _buildSectionHeaderWithChevron(
              title: 'Moods & Activities',
              onTap: () {},
            ),
            const SizedBox(height: 12),
            _buildMoodsGrid(moods),
            const SizedBox(height: 24),
          ],

          // Section 6: "Popular Genres"
          if (genres.isNotEmpty) ...[
            _buildSectionHeaderWithChevron(
              title: 'Browse by Genre',
              onTap: () {},
            ),
            const SizedBox(height: 12),
            _buildGenresList(genres),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeaderWithChevron({
    required String title,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              color: appleSecondaryText,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  /// Hero Carousel for "Top Picks"
  Widget _buildTopPicksHeroSection(List<SongItem> songs) {
    if (songs.isEmpty) return const SizedBox.shrink();

    final heroItems = songs.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Top Picks',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.6,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'JUST UPDATED',
                style: TextStyle(
                  color: appleSecondaryText,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        SizedBox(
          height: 340,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: heroItems.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final song = heroItems[index];
              final isCurrent = _currentSong?.id == song.id;

              final gradients = [
                const [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
                const [Color(0xFF8A2387), Color(0xFFE94057), Color(0xFFF27121)],
                const [Color(0xFF1F4037), Color(0xFF99F2C8)],
                const [Color(0xFF3A1C71), Color(0xFFD76D77), Color(0xFFFFAF7B)],
                const [Color(0xFF232526), Color(0xFF414345)],
              ];
              final gradient = gradients[index % gradients.length];

              return GestureDetector(
                onTap: () => _onSongSelected(song),
                child: Container(
                  width: 280,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: song.thumbnailUrl != null
                              ? Image.network(
                                  song.thumbnailUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _fallbackHeroArt(),
                                )
                              : _fallbackHeroArt(),
                        ),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withValues(alpha: 0.3),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.85),
                                ],
                                stops: const [0.0, 0.4, 1.0],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 14,
                          right: 14,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.apple, color: Colors.white70, size: 14),
                              const SizedBox(width: 2),
                              Text(
                                'Music',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 14,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'FEATURED',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 12,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xCC1C1C1E),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
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
                                          const SizedBox(height: 2),
                                          Text(
                                            song.artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFF8E8E93),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      decoration: BoxDecoration(
                                        color: isCurrent ? appleRed : Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(8),
                                      child: Icon(
                                        isCurrent ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        color: isCurrent ? Colors.white : Colors.black,
                                        size: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _fallbackHeroArt() {
    return Container(
      color: appleDarkSurfaceHigh,
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: Colors.white24, size: 64),
      ),
    );
  }

  Widget _buildHorizontalSquareCards(List<SongItem> songs) {
    if (songs.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: songs.length > 12 ? 12 : songs.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final song = songs[index];
          final isCurrent = _currentSong?.id == song.id;

          return GestureDetector(
            onTap: () => _onSongSelected(song),
            child: SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: song.thumbnailUrl != null
                            ? Image.network(
                                song.thumbnailUrl!,
                                width: 140,
                                height: 140,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _fallbackSquareArt(),
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
                              Icons.equalizer_rounded,
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
    );
  }

  Widget _fallbackSquareArt() {
    return Container(
      width: 140,
      height: 140,
      color: appleDarkSurfaceHigh,
      child: const Icon(Icons.music_note_rounded, color: Colors.white30, size: 36),
    );
  }

  Widget _buildMoodsGrid(List<MusicCategory> moods) {
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: moods.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final mood = moods[index];
          final color = mood.colorValue != null
              ? Color(mood.colorValue!).withValues(alpha: 0.85)
              : const Color(0xFF3A3A3C);

          return GestureDetector(
            onTap: () {
              _searchController.text = mood.title;
              _handleSearch(mood.title);
            },
            child: Container(
              width: 150,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [color, color.withValues(alpha: 0.6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Icon(Icons.bubble_chart_rounded, color: Colors.white70, size: 24),
                  Text(
                    mood.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGenresList(List<MusicCategory> genres) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: genres.take(12).map((genre) {
          return GestureDetector(
            onTap: () {
              _searchController.text = genre.title;
              _handleSearch(genre.title);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: appleDarkSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 0.6,
                ),
              ),
              child: Text(
                genre.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // =========================================================================
  // TAB 2: EXPLORE (Replaces Browse, holds genres, charts, releases)
  // =========================================================================
  Widget _buildExploreTab() {
    final genres = _homeData?.genres ?? [];
    final trending = _homeData?.trendingTracks ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
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
          'Global Charts & Hits',
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
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
        _buildLibraryActionTile(Icons.playlist_play_rounded, 'Playlists'),
        _buildLibraryActionTile(Icons.music_note_rounded, 'Songs'),
        _buildLibraryActionTile(Icons.album_rounded, 'Albums'),
        _buildLibraryActionTile(Icons.person_rounded, 'Artists'),
        _buildLibraryActionTile(Icons.download_done_rounded, 'Downloaded'),
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
        if (_recentlyPlayed.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No songs played yet. Tap any track to begin listening.',
              style: TextStyle(color: appleSecondaryText),
            ),
          )
        else
          ..._recentlyPlayed.map((song) => _buildSongRow(song)),
      ],
    );
  }

  Widget _buildLibraryActionTile(IconData icon, String title) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: appleRed, size: 26),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: appleSecondaryText),
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
            height: 42,
            decoration: BoxDecoration(
              color: appleDarkSurfaceHigh,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                const Icon(Icons.search_rounded, color: appleSecondaryText, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    cursorColor: appleRed,
                    decoration: const InputDecoration(
                      hintText: 'Artists, Songs, Lyrics, and More',
                      hintStyle: TextStyle(color: appleSecondaryText, fontSize: 15),
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
                    child: const Icon(Icons.cancel_rounded, color: appleSecondaryText, size: 18),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _isSearching
              ? const Center(
                  child: CircularProgressIndicator(color: appleRed),
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
        child: Text('No results found.', style: TextStyle(color: appleSecondaryText)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) => const Divider(
        color: Color(0xFF2C2C2E),
        height: 1,
        indent: 62,
      ),
      itemBuilder: (context, index) {
        final song = _searchResults[index];
        return _buildSongRow(song);
      },
    );
  }

  Widget _buildSearchExploration() {
    final genres = _homeData?.genres ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: appleDarkSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Text(
                  g.title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSongRow(SongItem song) {
    final isSelected = _currentSong?.id == song.id;

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
                errorBuilder: (context, error, stackTrace) => _fallbackSquareArt(),
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
      trailing: isSelected
          ? const Icon(Icons.equalizer_rounded, color: appleRed)
          : const Icon(Icons.more_horiz_rounded, color: appleSecondaryText),
      onTap: () => _onSongSelected(song),
    );
  }
}

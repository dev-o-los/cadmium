import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song_item.dart';
import '../models/music_category.dart';
import '../models/home_data.dart';
import '../services/music_service.dart';
import '../widgets/player_controls.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MusicService _musicService = MusicService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  HomeData? _homeData;
  bool _isLoadingHome = true;
  String? _homeError;

  String _selectedCategory = 'All';
  List<SongItem> _categoryTracks = [];
  bool _isLoadingCategory = false;

  List<SongItem> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  bool _hasSearched = false;

  SongItem? _currentSong;
  bool _isResolvingStream = false;

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
        _homeError = 'Failed to load trending music: ${e.toString()}';
      });
    }
  }

  Future<void> _selectCategory(String category) async {
    if (_selectedCategory == category && !_hasSearched) return;

    FocusScope.of(context).unfocus();
    _searchController.clear();

    setState(() {
      _selectedCategory = category;
      _hasSearched = false;
      _searchResults.clear();
      _isLoadingCategory = category != 'All';
    });

    if (category == 'All') {
      return;
    }

    try {
      final tracks = await _musicService.searchSongs('$category top songs');
      if (!mounted) return;
      setState(() {
        _categoryTracks = tracks;
        _isLoadingCategory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingCategory = false;
      });
      _showSnackBar('Could not load $category tracks.');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _audioPlayer.dispose();
    _musicService.dispose();
    super.dispose();
  }

  /// Executes search query
  Future<void> _handleSearch() async {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      _showSnackBar('Please enter a song title or artist name.');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = true;
      _searchError = null;
      _hasSearched = true;
      _selectedCategory = 'Search';
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
        _searchError = 'No internet connection. Please check your network.';
      });
      _showSnackBar('Network error: Unable to reach YouTube Music.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = 'Search failed: ${e.toString()}';
      });
      _showSnackBar('An error occurred during search. Please try again.');
    }
  }

  /// Handles song selection, resolves verified stream URL, and triggers playback
  Future<void> _onSongSelected(SongItem song) async {
    if (_currentSong?.id == song.id) {
      _togglePlayPause();
      return;
    }

    setState(() {
      _currentSong = song;
      _isResolvingStream = true;
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

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.graphic_eq_rounded, color: colorScheme.primary, size: 28),
            const SizedBox(width: 8),
            const Text(
              'Wavify',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Feed',
            onPressed: () => _loadHomeData(refresh: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search songs, artists, or genres...',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty || _hasSearched)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _hasSearched = false;
                        _searchResults.clear();
                        _selectedCategory = 'All';
                      });
                    },
                  ),
                IconButton(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  tooltip: 'Submit Search',
                  onPressed: _handleSearch,
                ),
              ],
              onSubmitted: (_) => _handleSearch(),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Horizontal Category Chips
          _buildCategoryFilterBar(colorScheme),

          const SizedBox(height: 6),

          // Main Scrollable Content
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadHomeData(refresh: true),
              child: _buildMainBody(theme, colorScheme),
            ),
          ),

          // Persistent Player Controls
          PlayerControls(
            currentSong: _currentSong,
            audioPlayer: _audioPlayer,
            isResolvingStream: _isResolvingStream,
            onTogglePlayPause: _togglePlayPause,
          ),
        ],
      ),
    );
  }

  /// Horizontal scrolling chips for quick genre/category selection
  Widget _buildCategoryFilterBar(ColorScheme colorScheme) {
    final quickCategories = [
      'All',
      'Trending',
      'Pop',
      'Chill',
      'Bollywood',
      'Hip-Hop',
      'Rock',
      'Electronic',
      'Workout',
      'Party',
    ];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: quickCategories.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = quickCategories[index];
          final isSelected = _selectedCategory == cat;

          return FilterChip(
            label: Text(cat),
            selected: isSelected,
            onSelected: (_) => _selectCategory(cat),
            showCheckmark: false,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMainBody(ThemeData theme, ColorScheme colorScheme) {
    // 1. If actively searching, show search results
    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Searching music...'),
          ],
        ),
      );
    }

    if (_hasSearched) {
      return _buildSearchResultsView(theme, colorScheme);
    }

    // 2. If a specific category filter is chosen (not 'All')
    if (_selectedCategory != 'All') {
      return _buildCategoryTracksView(theme, colorScheme);
    }

    // 3. Home Feed loading or error states
    if (_isLoadingHome) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading trending music & genres...'),
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
              Icon(Icons.error_outline_rounded, size: 52, color: colorScheme.error),
              const SizedBox(height: 12),
              Text(
                _homeError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () => _loadHomeData(refresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // 4. Default Rich Homepage UI
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Section: Trending Now
        _buildSectionHeader(
          title: '🔥 Trending Now',
          subtitle: 'Top charts & most played tracks',
          theme: theme,
          colorScheme: colorScheme,
        ),
        _buildTrendingList(theme, colorScheme),

        const SizedBox(height: 20),

        // Section: Quick Picks / Highlights
        if (_homeData?.quickPicks.isNotEmpty ?? false) ...[
          _buildSectionHeader(
            title: '✨ Quick Picks',
            subtitle: 'Recommended hits for you',
            theme: theme,
            colorScheme: colorScheme,
          ),
          _buildHorizontalSongCards(_homeData!.quickPicks, theme, colorScheme),
          const SizedBox(height: 20),
        ],

        // Section: Moods & Moments
        if (_homeData?.moods.isNotEmpty ?? false) ...[
          _buildSectionHeader(
            title: '🌈 Moods & Moments',
            subtitle: 'Music for how you feel',
            theme: theme,
            colorScheme: colorScheme,
          ),
          _buildCategoryGrid(_homeData!.moods, theme, colorScheme),
          const SizedBox(height: 20),
        ],

        // Section: Explore Genres
        if (_homeData?.genres.isNotEmpty ?? false) ...[
          _buildSectionHeader(
            title: '🎸 Popular Genres',
            subtitle: 'Explore sounds by genre',
            theme: theme,
            colorScheme: colorScheme,
          ),
          _buildCategoryGrid(_homeData!.genres.take(16).toList(), theme, colorScheme),
        ],
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Trending ranked tracks list
  Widget _buildTrendingList(ThemeData theme, ColorScheme colorScheme) {
    final trending = _homeData?.trendingTracks ?? [];
    if (trending.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text('No trending tracks available right now.'),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: trending.length > 10 ? 10 : trending.length,
      itemBuilder: (context, index) {
        final song = trending[index];
        final rank = index + 1;
        final isSelected = _currentSong?.id == song.id;

        return ListTile(
          selected: isSelected,
          selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.25),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '$rank',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: rank <= 3 ? colorScheme.primary : colorScheme.outline,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: song.thumbnailUrl != null
                    ? Image.network(
                        song.thumbnailUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _fallbackThumbnail(colorScheme),
                      )
                    : _fallbackThumbnail(colorScheme),
              ),
            ],
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? colorScheme.primary : null,
            ),
          ),
          subtitle: Text(
            song.durationSeconds != null && song.durationSeconds! > 0
                ? '${song.artist} • ${song.formattedDuration}'
                : song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isSelected
              ? Icon(Icons.equalizer_rounded, color: colorScheme.primary)
              : IconButton(
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  tooltip: 'Play',
                  onPressed: () => _onSongSelected(song),
                ),
          onTap: () => _onSongSelected(song),
        );
      },
    );
  }

  /// Horizontal scrolling card list for Quick Picks
  Widget _buildHorizontalSongCards(List<SongItem> songs, ThemeData theme, ColorScheme colorScheme) {
    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: songs.length > 10 ? 10 : songs.length,
        separatorBuilder: (_, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final song = songs[index];
          final isSelected = _currentSong?.id == song.id;

          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _onSongSelected(song),
            child: SizedBox(
              width: 130,
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
                                width: 130,
                                height: 130,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => _fallbackThumbnail(colorScheme, size: 130),
                              )
                            : _fallbackThumbnail(colorScheme, size: 130),
                      ),
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            isSelected ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                            color: isSelected ? colorScheme.primary : Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      color: isSelected ? colorScheme.primary : null,
                    ),
                  ),
                  Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
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

  /// Colorful grid for Moods & Genres
  Widget _buildCategoryGrid(List<MusicCategory> categories, ThemeData theme, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: categories.map((cat) {
          final color = cat.colorValue != null
              ? Color(cat.colorValue!).withValues(alpha: 0.85)
              : colorScheme.primaryContainer;

          return Material(
            color: color,
            borderRadius: BorderRadius.circular(10),
            elevation: 0.5,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _selectCategory(cat.title),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      cat.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.white70),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// View when a category is selected (e.g. Chill, Pop, Bollywood)
  Widget _buildCategoryTracksView(ThemeData theme, ColorScheme colorScheme) {
    if (_isLoadingCategory) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading $_selectedCategory tracks...'),
          ],
        ),
      );
    }

    if (_categoryTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.music_off_rounded, size: 52, color: colorScheme.outline),
            const SizedBox(height: 12),
            Text('No tracks found for "$_selectedCategory"'),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => _selectCategory('All'),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_selectedCategory Tracks',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton(
                onPressed: () => _selectCategory('All'),
                child: const Text('View All'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _categoryTracks.length,
            separatorBuilder: (_, index) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, index) {
              final song = _categoryTracks[index];
              return _buildSongListTile(song, theme, colorScheme);
            },
          ),
        ),
      ],
    );
  }

  /// View for search results
  Widget _buildSearchResultsView(ThemeData theme, ColorScheme colorScheme) {
    if (_searchError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
              const SizedBox(height: 12),
              Text(
                _searchError!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _handleSearch,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 56, color: colorScheme.outline),
            const SizedBox(height: 12),
            const Text('No results found'),
            const SizedBox(height: 4),
            Text(
              'Try searching with different keywords.',
              style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.outline),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _searchResults.length,
      separatorBuilder: (_, index) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final song = _searchResults[index];
        return _buildSongListTile(song, theme, colorScheme);
      },
    );
  }

  Widget _buildSongListTile(SongItem song, ThemeData theme, ColorScheme colorScheme) {
    final isSelected = _currentSong?.id == song.id;

    return ListTile(
      selected: isSelected,
      selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.25),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: song.thumbnailUrl != null
            ? Image.network(
                song.thumbnailUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _fallbackThumbnail(colorScheme),
              )
            : _fallbackThumbnail(colorScheme),
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isSelected ? colorScheme.primary : null,
        ),
      ),
      subtitle: Text(
        song.durationSeconds != null && song.durationSeconds! > 0
            ? '${song.artist} • ${song.formattedDuration}'
            : song.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isSelected
          ? Icon(Icons.equalizer_rounded, color: colorScheme.primary)
          : null,
      onTap: () => _onSongSelected(song),
    );
  }

  Widget _fallbackThumbnail(ColorScheme colorScheme, {double size = 48}) {
    return Container(
      width: size,
      height: size,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        color: colorScheme.onSurfaceVariant,
        size: size * 0.5,
      ),
    );
  }
}

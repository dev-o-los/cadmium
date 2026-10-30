import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/song_item.dart';
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

  List<SongItem> _searchResults = [];
  SongItem? _currentSong;
  bool _isSearching = false;
  bool _isResolvingStream = false;
  String? _errorMessage;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    _initServices();
    _setupAudioListeners();
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
      // Non-fatal initialization error; will retry on search
      debugPrint('MusicService pre-init warning: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _audioPlayer.dispose();
    _musicService.dispose();
    super.dispose();
  }

  /// Executes search query with comprehensive error validation
  Future<void> _handleSearch() async {
    final query = _searchController.text.trim();

    // 1. Validation for empty query
    if (query.isEmpty) {
      _showSnackBar('Please enter a song title or artist name.');
      return;
    }

    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _hasSearched = true;
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
        _errorMessage = 'No internet connection. Please check your network.';
      });
      _showSnackBar('Network error: Unable to reach YouTube Music.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _errorMessage = 'Search failed: ${e.toString()}';
      });
      _showSnackBar('An error occurred during search. Please try again.');
    }
  }

  /// Handles song selection, resolves stream URL, and triggers playback
  Future<void> _onSongSelected(SongItem song) async {
    // If the tapped song is already playing or loaded, toggle playback
    if (_currentSong?.id == song.id) {
      _togglePlayPause();
      return;
    }

    setState(() {
      _currentSong = song;
      _isResolvingStream = true;
    });

    try {
      // 1. Extract direct audio stream with verified client profile and matching headers
      final streamInfo = await _musicService.resolveAudioStream(song.id);

      if (!mounted) return;

      // 2. Load into just_audio with matching streaming headers & progressive buffering
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

  /// Toggles play/pause on the AudioPlayer
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
        title: const Text('Wavify'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // Search Input Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search songs, artists, or tracks...',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
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

          // Main Content (List, Loading, or Status Messages)
          Expanded(
            child: _buildBody(theme, colorScheme),
          ),

          // Persistent Bottom Player Controls
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

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Searching YouTube Music...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.error,
                ),
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

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.music_note_rounded,
              size: 64,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Discover and stream music',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Type a song name or artist above to begin.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 56,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No results found',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Try searching with different keywords.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final song = _searchResults[index];
        final isSelected = _currentSong?.id == song.id;

        return ListTile(
          selected: isSelected,
          selectedTileColor: colorScheme.primaryContainer.withValues(alpha: 0.3),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
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
              ? Icon(
                  Icons.equalizer_rounded,
                  color: colorScheme.primary,
                )
              : null,
          onTap: () => _onSongSelected(song),
        );
      },
    );
  }

  Widget _fallbackThumbnail(ColorScheme colorScheme) {
    return Container(
      width: 48,
      height: 48,
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}


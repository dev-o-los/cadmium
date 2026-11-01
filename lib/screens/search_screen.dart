import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/song_item.dart';
import '../providers/home_data_provider.dart';
import '../providers/music_service_provider.dart';
import '../providers/player_provider.dart';
import '../utils/playback_utils.dart';
import '../widgets/animated_cupertino_icon.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/track_options_sheet.dart';

/// The Search Tab screen allowing searching for tracks, artists, and albums on YouTube Music,
/// or exploring genres and categories.
class SearchScreen extends ConsumerStatefulWidget {
  final TextEditingController? searchController;

  const SearchScreen({
    super.key,
    this.searchController,
  });

  @override
  ConsumerState<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;
  bool _isInternalController = false;

  List<SongItem> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  bool _hasSearched = false;

  @override
  void initState() {
    super.initState();
    if (widget.searchController != null) {
      _controller = widget.searchController!;
    } else {
      _controller = TextEditingController();
      _isInternalController = true;
    }
  }

  @override
  void dispose() {
    if (_isInternalController) {
      _controller.dispose();
    }
    super.dispose();
  }

  /// Programmatically triggers a search with the given query.
  Future<void> search([String? query]) async {
    final q = query ?? _controller.text.trim();
    if (q.isEmpty) return;

    if (query != null && _controller.text != query) {
      _controller.text = query;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
      _hasSearched = true;
    });

    try {
      final musicService = ref.read(musicServiceProvider);
      final results = await musicService.searchSongs(q);
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

  @override
  Widget build(BuildContext context) {
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
              color: AppColors.appleDarkSurfaceHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.search,
                  color: AppColors.appleSecondaryText,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      hintText: 'Artists, Songs, Lyrics, and More',
                      hintStyle: TextStyle(
                        color: AppColors.appleSecondaryText,
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => search(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (_controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _controller.clear();
                      setState(() {
                        _searchResults.clear();
                        _hasSearched = false;
                      });
                    },
                    child: const AnimatedCupertinoIcon(
                      icon: CupertinoIcons.clear_thick_circled,
                      color: AppColors.appleSecondaryText,
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
        child: Text(_searchError!, style: const TextStyle(color: AppColors.appleRed)),
      );
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Text(
          'No results found.',
          style: TextStyle(color: AppColors.appleSecondaryText),
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
                _controller.text = g.title;
                search(g.title);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.appleDarkSurface,
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

    return ApplePressable(
      onTap: () => playSong(context, ref, song),
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected ? AppColors.appleRed : Colors.white,
                        fontSize: 15,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                        letterSpacing: -0.3,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    ApplePressable(
                      onTap: () => openArtistScreen(context, artistName: song.artist),
                      child: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.appleSecondaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected) ...[
                const Icon(CupertinoIcons.waveform, color: AppColors.appleRed, size: 20),
                const SizedBox(width: 6),
              ],
              IconButton(
                icon: const AnimatedCupertinoIcon(
                  icon: CupertinoIcons.ellipsis_vertical,
                  color: AppColors.appleSecondaryText,
                  size: 18,
                ),
                onPressed: () => showTrackOptionsModal(context, ref, song),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fallbackSquareArt({
    double size = 48,
    IconData icon = CupertinoIcons.music_note,
  }) {
    return Container(
      width: size,
      height: size,
      color: AppColors.appleDarkSurfaceHigh,
      child: Icon(
        icon,
        color: Colors.white30,
        size: (size * 0.5).clamp(20.0, 48.0),
      ),
    );
  }
}


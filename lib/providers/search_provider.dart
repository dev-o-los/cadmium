import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recent_search_item.dart';
import '../models/search_result_set.dart';
import '../services/artwork_cache_service.dart';
import 'music_service_provider.dart';

/// Available search filter capsules matching Apple Music layout.
const List<String> kSearchFilterCategories = [
  'All',
  'Songs',
  'Videos',
  'Albums',
  'Artists',
  'Playlists',
];

/// StateNotifier that persists and manages the user's recent searches.
class RecentSearchNotifier extends StateNotifier<List<RecentSearchItem>> {
  static const _storageKey = 'wavify_recent_searches_v1';
  static const int _maxHistoryItems = 30;

  RecentSearchNotifier() : super(const []) {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_storageKey);
      if (list != null && list.isNotEmpty) {
        final loaded = list
            .map((item) {
              try {
                return RecentSearchItem.fromJson(
                    jsonDecode(item) as Map<String, dynamic>);
              } catch (_) {
                return null;
              }
            })
            .whereType<RecentSearchItem>()
            .toList();
        state = loaded;
      }
    } catch (e) {
      debugPrint('Error loading recent searches: $e');
    }
  }

  Future<void> addRecent(RecentSearchItem item) async {
    final titleLower = item.title.trim().toLowerCase();
    // Remove duplicate by id or case-insensitive title
    final filtered = state.where((s) {
      return s.id != item.id && s.title.trim().toLowerCase() != titleLower;
    }).toList();

    final updated = [item, ...filtered];
    if (updated.length > _maxHistoryItems) {
      updated.removeRange(_maxHistoryItems, updated.length);
    }
    state = updated;

    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = state.map((s) => jsonEncode(s.toJson())).toList();
      await prefs.setStringList(_storageKey, encoded);
    } catch (e) {
      debugPrint('Error saving recent searches: $e');
    }
  }

  Future<void> removeRecent(String id) async {
    final updated = state.where((s) => s.id != id).toList();
    state = updated;

    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = state.map((s) => jsonEncode(s.toJson())).toList();
      await prefs.setStringList(_storageKey, encoded);
    } catch (e) {
      debugPrint('Error removing recent search: $e');
    }
  }

  Future<void> clearAll() async {
    state = const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (e) {
      debugPrint('Error clearing recent searches: $e');
    }
  }
}

final recentSearchProvider =
    StateNotifierProvider<RecentSearchNotifier, List<RecentSearchItem>>((ref) {
  return RecentSearchNotifier();
});

/// Immutable state holding active search query, category, loading, and result data.
class SearchState {
  final String query;
  final String selectedCategory;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? errorMessage;
  final SearchResultSet results;
  final bool hasSearched;
  final List<String> relatedQueries;

  const SearchState({
    this.query = '',
    this.selectedCategory = 'All',
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.errorMessage,
    this.results = const SearchResultSet(),
    this.hasSearched = false,
    this.relatedQueries = const [],
  });

  SearchState copyWith({
    String? query,
    String? selectedCategory,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? errorMessage,
    SearchResultSet? results,
    bool? hasSearched,
    List<String>? relatedQueries,
  }) {
    return SearchState(
      query: query ?? this.query,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      errorMessage: errorMessage,
      results: results ?? this.results,
      hasSearched: hasSearched ?? this.hasSearched,
      relatedQueries: relatedQueries ?? this.relatedQueries,
    );
  }
}

/// SearchNotifier orchestrating search queries, debouncing, multi-category filtering,
/// and smooth infinite-scroll loading of related queries.
class SearchNotifier extends StateNotifier<SearchState> {
  final Ref _ref;
  int _searchRequestId = 0;
  final Map<String, SearchResultSet> _memoryCache = {};
  List<String> _relatedQueries = [];
  int _relatedQueryIndex = 0;
  final Set<String> _queriedTerms = {};

  SearchNotifier(this._ref) : super(const SearchState());

  void setCategory(String category) {
    if (state.selectedCategory == category) return;
    state = state.copyWith(selectedCategory: category);
  }

  void clearQuery() {
    _searchRequestId++;
    _relatedQueries = [];
    _relatedQueryIndex = 0;
    _queriedTerms.clear();
    state = const SearchState();
  }

  Future<void> search(String query, {bool force = false}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      clearQuery();
      return;
    }

    if (!force && trimmed == state.query && state.hasSearched) {
      return;
    }

    final requestId = ++_searchRequestId;
    _relatedQueries = [];
    _relatedQueryIndex = 0;
    _queriedTerms.clear();
    _queriedTerms.add(trimmed.toLowerCase());

    // Check memory cache for instant response
    final cacheKey = trimmed.toLowerCase();
    if (!force && _memoryCache.containsKey(cacheKey)) {
      final cachedResults = _memoryCache[cacheKey]!;
      state = state.copyWith(
        query: trimmed,
        results: cachedResults,
        isLoading: false,
        isLoadingMore: false,
        hasMore: true,
        errorMessage: null,
        hasSearched: true,
      );
      _fetchRelatedSuggestions(trimmed, requestId);
      return;
    }

    state = state.copyWith(
      query: trimmed,
      isLoading: true,
      isLoadingMore: false,
      hasMore: true,
      errorMessage: null,
      hasSearched: true,
    );

    try {
      final musicService = _ref.read(musicServiceProvider);
      final resultSet = await musicService.searchAll(trimmed);

      // Verify request freshness (discard stale debounced responses)
      if (requestId != _searchRequestId) return;

      _memoryCache[cacheKey] = resultSet;
      state = state.copyWith(
        results: resultSet,
        isLoading: false,
        isLoadingMore: false,
        hasMore: true,
        errorMessage: null,
      );

      _fetchRelatedSuggestions(trimmed, requestId);
    } on SocketException {
      if (requestId != _searchRequestId) return;
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        errorMessage: 'Network error. Please check your connection.',
      );
    } catch (e) {
      if (requestId != _searchRequestId) return;
      state = state.copyWith(
        isLoading: false,
        isLoadingMore: false,
        errorMessage: 'Search failed: ${e.toString()}',
      );
    }
  }

  /// Asynchronously gathers related queries from YouTube Music search suggestions
  /// to fuel infinite scroll loading as the user scrolls down.
  Future<void> _fetchRelatedSuggestions(String query, int requestId) async {
    try {
      final musicService = _ref.read(musicServiceProvider);
      final suggestions = await musicService.getSearchSuggestions(query);
      if (requestId != _searchRequestId) return;

      final normalizedQuery = query.toLowerCase();
      final filtered = suggestions.where((s) {
        final lower = s.trim().toLowerCase();
        return lower.isNotEmpty &&
            lower != normalizedQuery &&
            !_queriedTerms.contains(lower);
      }).toList();

      // If suggestions are sparse, augment with contextual music queries
      if (filtered.length < 3) {
        if (state.results.artists.isNotEmpty) {
          final artistName = state.results.artists.first.name;
          if (artistName.toLowerCase() != normalizedQuery &&
              !filtered.contains(artistName)) {
            filtered.add(artistName);
          }
        }
        if (state.results.songs.isNotEmpty) {
          final topSong = state.results.songs.first;
          final artistSong = '${topSong.artist} ${topSong.title}';
          if (!filtered.contains(artistSong) &&
              artistSong.toLowerCase() != normalizedQuery) {
            filtered.add(artistSong);
          }
        }
      }

      _relatedQueries = filtered;
      state = state.copyWith(relatedQueries: filtered);
    } catch (_) {
      // Safe fallback if suggestions are unavailable
    }
  }

  /// Called as the user slides down to load more queries related to the searched term.
  Future<void> loadMore() async {
    if (state.isLoading ||
        state.isLoadingMore ||
        !state.hasMore ||
        state.query.trim().isEmpty) {
      return;
    }

    state = state.copyWith(isLoadingMore: true);

    try {
      final musicService = _ref.read(musicServiceProvider);
      String? nextQuery;

      // 1. Pick from search suggestions if available
      while (_relatedQueryIndex < _relatedQueries.length) {
        final candidate = _relatedQueries[_relatedQueryIndex++];
        final lower = candidate.trim().toLowerCase();
        if (!_queriedTerms.contains(lower)) {
          nextQuery = candidate.trim();
          _queriedTerms.add(lower);
          break;
        }
      }

      // 2. Fallback to related artist or track queries if suggestions exhausted
      if (nextQuery == null) {
        for (final song in state.results.songs) {
          final artistLower = song.artist.trim().toLowerCase();
          if (artistLower.isNotEmpty &&
              artistLower != 'unknown artist' &&
              !_queriedTerms.contains(artistLower)) {
            nextQuery = song.artist.trim();
            _queriedTerms.add(artistLower);
            break;
          }
        }
      }

      // 3. Fallback to modifier terms if still no query
      if (nextQuery == null) {
        final base = state.query.trim();
        final modifiers = ['remix', 'live', 'hits', 'acoustic', 'album'];
        for (final mod in modifiers) {
          final candidate = '$base $mod'.toLowerCase();
          if (!_queriedTerms.contains(candidate)) {
            nextQuery = '$base $mod';
            _queriedTerms.add(candidate);
            break;
          }
        }
      }

      if (nextQuery == null) {
        state = state.copyWith(isLoadingMore: false, hasMore: false);
        return;
      }

      // Fetch according to active category
      final category = state.selectedCategory;
      if (category == 'Songs') {
        final newSongs = await musicService.searchSongs(nextQuery);
        final existingIds = state.results.songs.map((s) => s.id).toSet();
        final uniqueSongs = newSongs.where((s) => !existingIds.contains(s.id)).toList();
        if (uniqueSongs.isNotEmpty) {
          unawaited(ArtworkCacheService.instance.prefetchArtworks(uniqueSongs));
        }
        final updatedResults = state.results.copyWith(
          songs: [...state.results.songs, ...uniqueSongs],
        );
        state = state.copyWith(
          results: updatedResults,
          isLoadingMore: false,
          hasMore: uniqueSongs.isNotEmpty || _relatedQueryIndex < _relatedQueries.length,
        );
      } else if (category == 'Videos') {
        final newVideos = await musicService.searchVideos(nextQuery);
        final existingIds = state.results.videos.map((v) => v.id).toSet();
        final uniqueVideos = newVideos.where((v) => !existingIds.contains(v.id)).toList();
        if (uniqueVideos.isNotEmpty) {
          unawaited(ArtworkCacheService.instance.prefetchImageUrls(
            uniqueVideos.map((v) => v.thumbnailUrl).toList(),
          ));
        }
        final updatedResults = state.results.copyWith(
          videos: [...state.results.videos, ...uniqueVideos],
        );
        state = state.copyWith(
          results: updatedResults,
          isLoadingMore: false,
          hasMore: uniqueVideos.isNotEmpty || _relatedQueryIndex < _relatedQueries.length,
        );
      } else if (category == 'Albums') {
        final newAlbums = await musicService.searchAlbums(nextQuery);
        final existingIds = state.results.albums.map((a) => a.id).toSet();
        final uniqueAlbums = newAlbums.where((a) => !existingIds.contains(a.id)).toList();
        if (uniqueAlbums.isNotEmpty) {
          unawaited(ArtworkCacheService.instance.prefetchImageUrls(
            uniqueAlbums.map((a) => a.thumbnailUrl).toList(),
          ));
        }
        final updatedResults = state.results.copyWith(
          albums: [...state.results.albums, ...uniqueAlbums],
        );
        state = state.copyWith(
          results: updatedResults,
          isLoadingMore: false,
          hasMore: uniqueAlbums.isNotEmpty || _relatedQueryIndex < _relatedQueries.length,
        );
      } else if (category == 'Artists') {
        final newArtists = await musicService.searchArtists(nextQuery);
        final existingIds = state.results.artists.map((a) => a.id).toSet();
        final uniqueArtists = newArtists.where((a) => !existingIds.contains(a.id)).toList();
        if (uniqueArtists.isNotEmpty) {
          unawaited(ArtworkCacheService.instance.prefetchImageUrls(
            uniqueArtists.map((a) => a.thumbnailUrl).toList(),
          ));
        }
        final updatedResults = state.results.copyWith(
          artists: [...state.results.artists, ...uniqueArtists],
        );
        state = state.copyWith(
          results: updatedResults,
          isLoadingMore: false,
          hasMore: uniqueArtists.isNotEmpty || _relatedQueryIndex < _relatedQueries.length,
        );
      } else if (category == 'Playlists') {
        final newPlaylists = await musicService.searchPlaylists(nextQuery);
        final existingIds = state.results.playlists.map((p) => p.id).toSet();
        final uniquePlaylists = newPlaylists.where((p) => !existingIds.contains(p.id)).toList();
        if (uniquePlaylists.isNotEmpty) {
          unawaited(ArtworkCacheService.instance.prefetchImageUrls(
            uniquePlaylists.map((p) => p.thumbnailUrl).toList(),
          ));
        }
        final updatedResults = state.results.copyWith(
          playlists: [...state.results.playlists, ...uniquePlaylists],
        );
        state = state.copyWith(
          results: updatedResults,
          isLoadingMore: false,
          hasMore: uniquePlaylists.isNotEmpty || _relatedQueryIndex < _relatedQueries.length,
        );
      } else {
        // 'All' category: fetch multi-category and merge
        final moreResultSet = await musicService.searchAll(nextQuery);
        final merged = state.results.merge(moreResultSet);
        state = state.copyWith(
          results: merged,
          isLoadingMore: false,
          hasMore: moreResultSet.isNotEmpty || _relatedQueryIndex < _relatedQueries.length,
        );
      }
    } catch (e) {
      debugPrint('Error loading more search items: $e');
      state = state.copyWith(isLoadingMore: false);
    }
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref);
});


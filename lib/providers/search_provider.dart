import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recent_search_item.dart';
import '../models/search_result_set.dart';
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
  final String? errorMessage;
  final SearchResultSet results;
  final bool hasSearched;

  const SearchState({
    this.query = '',
    this.selectedCategory = 'All',
    this.isLoading = false,
    this.errorMessage,
    this.results = const SearchResultSet(),
    this.hasSearched = false,
  });

  SearchState copyWith({
    String? query,
    String? selectedCategory,
    bool? isLoading,
    String? errorMessage,
    SearchResultSet? results,
    bool? hasSearched,
  }) {
    return SearchState(
      query: query ?? this.query,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      results: results ?? this.results,
      hasSearched: hasSearched ?? this.hasSearched,
    );
  }
}

/// SearchNotifier orchestrating search queries, debouncing, and multi-category filtering.
class SearchNotifier extends StateNotifier<SearchState> {
  final Ref _ref;
  int _searchRequestId = 0;
  final Map<String, SearchResultSet> _memoryCache = {};

  SearchNotifier(this._ref) : super(const SearchState());

  void setCategory(String category) {
    if (state.selectedCategory == category) return;
    state = state.copyWith(selectedCategory: category);
  }

  void clearQuery() {
    _searchRequestId++;
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

    // Check memory cache for instant response
    final cacheKey = trimmed.toLowerCase();
    if (!force && _memoryCache.containsKey(cacheKey)) {
      state = state.copyWith(
        query: trimmed,
        results: _memoryCache[cacheKey]!,
        isLoading: false,
        errorMessage: null,
        hasSearched: true,
      );
      return;
    }

    state = state.copyWith(
      query: trimmed,
      isLoading: true,
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
        errorMessage: null,
      );
    } on SocketException {
      if (requestId != _searchRequestId) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Network error. Please check your connection.',
      );
    } catch (e) {
      if (requestId != _searchRequestId) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Search failed: ${e.toString()}',
      );
    }
  }
}

final searchProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref);
});


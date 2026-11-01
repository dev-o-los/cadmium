import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/home_data.dart';
import '../services/home_cache_service.dart';
import '../services/music_service.dart';
import 'music_service_provider.dart';

/// Notifier providing the aggregated HomeData state with instant cache display
/// and silent background revalidation (stale-while-revalidate).
class HomeDataNotifier extends AsyncNotifier<HomeData> {
  @override
  Future<HomeData> build() async {
    final musicService = ref.watch(musicServiceProvider);

    // 1. Check persistent disk cache first for instant (< 5ms) home screen load
    final cached = await HomeCacheService.instance.loadHomeData();
    if (cached != null && !cached.isEmpty) {
      // Revalidate in background if stale and not running inside test harness
      final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
      if (!isTest && !HomeCacheService.instance.isFresh()) {
        _revalidateInBackground(musicService);
      }
      return cached;
    }

    // 2. Cold start without cache: fetch from service (which caches the result)
    return musicService.getHomeData();
  }

  void _revalidateInBackground(MusicService musicService) {
    Future.microtask(() async {
      try {
        final fresh = await musicService.getHomeData(refresh: true);
        if (!fresh.isEmpty) {
          state = AsyncValue.data(fresh);
        }
      } catch (_) {
        // Silently preserve cached content on network failure
      }
    });
  }

  /// Forces a fresh fetch from YouTube Music.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final musicService = ref.read(musicServiceProvider);
      return musicService.getHomeData(refresh: true);
    });
  }
}

final homeDataProvider = AsyncNotifierProvider<HomeDataNotifier, HomeData>(() {
  return HomeDataNotifier();
});


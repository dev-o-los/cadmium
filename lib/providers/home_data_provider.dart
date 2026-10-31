import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/home_data.dart';
import 'music_service_provider.dart';

/// Notifier providing the aggregated HomeData state with pull-to-refresh.
class HomeDataNotifier extends AsyncNotifier<HomeData> {
  @override
  Future<HomeData> build() async {
    final musicService = ref.watch(musicServiceProvider);
    return musicService.getHomeData();
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


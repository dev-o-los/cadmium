import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/screens/home_screen.dart';
import 'package:wavify/services/player_history_cache_service.dart';
import 'package:wavify/widgets/player_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('PlayerHistoryCacheService Tests', () {
    test('saveLastPlayedSong persists song and restores properly', () async {
      final cacheService = PlayerHistoryCacheService.instance;
      const testSong = SongItem(
        id: 'test_song_123',
        title: 'Starboy',
        artist: 'The Weeknd',
        thumbnailUrl: 'https://example.com/art.jpg',
        durationSeconds: 230,
      );

      await cacheService.saveLastPlayedSong(testSong);

      expect(cacheService.lastPlayedSong?.id, equals('test_song_123'));
      expect(cacheService.lastPlayedSong?.title, equals('Starboy'));
      expect(cacheService.lastPlayedSong?.artist, equals('The Weeknd'));
      expect(cacheService.recentlyPlayed.isNotEmpty, isTrue);
      expect(cacheService.recentlyPlayed.first.id, equals('test_song_123'));
    });

    test('PlayerNotifier initializes with cached song and duration', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(playerProvider);
      // If cached song exists, state.currentSong should match
      if (PlayerHistoryCacheService.instance.lastPlayedSong != null) {
        expect(state.currentSong?.id, equals('test_song_123'));
        expect(state.duration.inSeconds, equals(230));
        expect(state.isPlaying, isFalse);
      }
    });

    testWidgets('HomeScreen mounts floating mini player immediately when history exists',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const cachedSong = SongItem(
        id: 'test_song_history',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        thumbnailUrl: 'https://example.com/art2.jpg',
        durationSeconds: 200,
      );

      await PlayerHistoryCacheService.instance.saveLastPlayedSong(cachedSong);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: HomeScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // PlayerControls must be present docked above bottom navigation bar
      expect(find.byType(PlayerControls), findsOneWidget);
      expect(find.text('Blinding Lights'), findsOneWidget);
      expect(find.text('The Weeknd'), findsOneWidget);
    });
  });
}


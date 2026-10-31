import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/favorites_provider.dart';
import 'package:wavify/screens/player_screen.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/widgets/apple_pressable.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FavoritesNotifier local persistence tests', () {
    const testSong1 = SongItem(
      id: 'fav_song_1',
      title: 'Me Too',
      artist: 'SoFaygo',
      album: 'Pink Heartz',
      durationSeconds: 210,
    );

    const testSong2 = SongItem(
      id: 'fav_song_2',
      title: 'Hell Yeah',
      artist: 'SoFaygo',
      album: 'Pink Heartz',
      durationSeconds: 195,
    );

    test('toggleFavorite adds and removes songs and persists locally', () async {
      final notifier = FavoritesNotifier();
      expect(notifier.state, isEmpty);

      // Add testSong1
      final added = await notifier.toggleFavorite(testSong1);
      expect(added, isTrue);
      expect(notifier.state.length, 1);
      expect(notifier.isFavorite('fav_song_1'), isTrue);
      expect(notifier.isFavorite('fav_song_2'), isFalse);

      // Add testSong2
      await notifier.toggleFavorite(testSong2);
      expect(notifier.state.length, 2);
      expect(notifier.state.first.id, 'fav_song_2');

      // Re-load from SharedPreferences to verify persistence
      final reloadedNotifier = FavoritesNotifier();
      // Allow async _loadFavorites to complete
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reloadedNotifier.state.length, 2);
      expect(reloadedNotifier.isFavorite('fav_song_1'), isTrue);

      // Toggle testSong1 again (should remove it)
      final removed = await notifier.toggleFavorite(testSong1);
      expect(removed, isFalse);
      expect(notifier.state.length, 1);
      expect(notifier.isFavorite('fav_song_1'), isFalse);
    });

    test('removeFavorite removes track directly by id', () async {
      final notifier = FavoritesNotifier();
      await notifier.toggleFavorite(testSong1);
      expect(notifier.isFavorite('fav_song_1'), isTrue);

      await notifier.removeFavorite('fav_song_1');
      expect(notifier.isFavorite('fav_song_1'), isFalse);
      expect(notifier.state, isEmpty);
    });
  });

  group('ApplePressable widget test', () {
    testWidgets('ApplePressable animates scale and triggers onTap without splash',
        (WidgetTester tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ApplePressable(
                onTap: () => tapped = true,
                child: const Text('Apple Music Tile'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Apple Music Tile'), findsOneWidget);

      // Press down (touch down)
      final gesture = await tester.startGesture(tester.getCenter(find.text('Apple Music Tile')));
      await tester.pump(const Duration(milliseconds: 50));

      // AnimatedScale has transformed scale < 1.0
      final animatedScale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(animatedScale.scale, lessThan(1.0));

      // Release (touch up)
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
      final resetScale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(resetScale.scale, 1.0);
    });
  });

  group('PlayerScreen local favorites integration test', () {
    const testSong = SongItem(
      id: 'player_fav_test',
      title: 'Me Too',
      artist: 'SoFaygo',
      durationSeconds: 180,
    );

    testWidgets('Tapping star button in PlayerScreen toggles local favorite',
        (WidgetTester tester) async {
      final container = ProviderContainer();
      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: testSong,
        isPlaying: true,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: PlayerScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Initial state: song is not favorited
      expect(container.read(favoritesProvider.notifier).isFavorite(testSong.id), isFalse);

      // Tap the star button
      final starFinder = find.byIcon(CupertinoIcons.star);
      expect(starFinder, findsOneWidget);
      await tester.tap(starFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Now song is favorited locally
      expect(container.read(favoritesProvider.notifier).isFavorite(testSong.id), isTrue);
      expect(find.byIcon(CupertinoIcons.star_fill), findsOneWidget);

      // Tap star button again to remove
      await tester.tap(find.byIcon(CupertinoIcons.star_fill));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(favoritesProvider.notifier).isFavorite(testSong.id), isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });
}


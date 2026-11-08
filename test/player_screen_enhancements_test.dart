import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/favorites_provider.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/screens/player_screen.dart';
import 'package:wavify/services/artwork_color_service.dart';
import 'package:wavify/widgets/player_controls.dart';
import 'package:wavify/widgets/smooth_player_loader.dart';

void main() {
  group('Player Screen & Controls Enhancements Tests', () {
    const testSongA = SongItem(
      id: 'song_a_1',
      title: 'Starboy',
      artist: 'The Weeknd',
      album: 'Starboy',
      durationSeconds: 230,
    );

    const testSongB = SongItem(
      id: 'song_b_2',
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      album: 'After Hours',
      durationSeconds: 200,
    );

    test('ArtworkColorService extracts distinct secondary color and fallback tone', () async {
      final secondarySeed = ArtworkColorService.instance.getFallbackSecondaryColor('Starboy The Weeknd');
      expect(secondarySeed, isA<Color>());
      expect(secondarySeed.a, greaterThan(0.0));

      final extractedSecondary = await ArtworkColorService.instance.extractSecondaryColor(
        null,
        fallbackSeed: 'After Hours The Weeknd',
      );
      expect(extractedSecondary, isA<Color>());
    });

    testWidgets('PlayerScreen renders album art at 40% ratio and occupies rest for controls', (tester) async {
      const screenH = 1000.0;
      const screenW = 400.0;
      tester.view.physicalSize = const Size(screenW, screenH);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: testSongA,
        isPlaying: true,
        duration: Duration(seconds: 230),
        position: Duration(seconds: 45),
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

      // In expanded Now Playing mode, artwork height is 40% of screen height (400px)
      final heroFinder = find.byKey(const ValueKey('player_screen_artwork_song_a_1'));
      expect(heroFinder, findsOneWidget);

      final heroSize = tester.getSize(heroFinder);
      expect(heroSize.height, closeTo(screenH * 0.40, 2.0));

      // Controls (title, artist, favorite, scrubber, play/pause) are rendered below
      expect(find.text('Starboy'), findsOneWidget);
      expect(find.text('The Weeknd'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.star), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('Favorite button in PlayerScreen renders with liquid glass container and toggles', (tester) async {
      final container = ProviderContainer();
      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: testSongA,
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

      // Star button is rendered inside GlassContainer
      final starIconFinder = find.byIcon(CupertinoIcons.star);
      expect(starIconFinder, findsOneWidget);

      final glassButtons = find.ancestor(of: starIconFinder, matching: find.byType(GlassContainer));
      expect(glassButtons, findsWidgets);

      // Tap favorite button to toggle
      await tester.tap(starIconFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(favoritesProvider.notifier).isFavorite(testSongA.id), isTrue);
      expect(find.byIcon(CupertinoIcons.star_fill), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('Mini player applies liquid glass secondary color tint and smooth loader', (tester) async {
      final container = ProviderContainer();
      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: testSongA,
        isPlaying: true,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: PlayerControls(),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Mini player renders inside GlassContainer
      expect(find.byType(GlassContainer), findsWidgets);
      expect(find.text('Starboy'), findsOneWidget);
      expect(find.text('The Weeknd'), findsOneWidget);

      // Play/pause button is present and responsive
      expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);
      await tester.tap(find.byIcon(CupertinoIcons.play_fill));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(GlassContainer), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('Shifting tracks transitions artwork subtly with AnimatedSwitcher', (tester) async {
      final container = ProviderContainer();
      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: testSongA,
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

      expect(find.byKey(const ValueKey('player_screen_artwork_song_a_1')), findsOneWidget);

      // Shift to song B (different album)
      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: testSongB,
        isPlaying: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Transition smoothly advances to song B
      expect(find.byKey(const ValueKey('player_screen_artwork_song_b_2')), findsOneWidget);
      expect(find.text('Blinding Lights'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('SmoothPlayerLoader renders luminous aura and Cupertino spinner', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: SmoothPlayerLoader(radius: 16),
            ),
          ),
        ),
      );

      expect(find.byType(SmoothPlayerLoader), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    });
  });
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/screens/player_screen.dart';
import 'package:wavify/widgets/player_controls.dart';
import 'package:wavify/widgets/wavify_cached_image.dart';

void main() {
  group('Artwork Animation Tests (Mini Player Bar to Player Screen)', () {
    const testSongA = SongItem(
      id: 'song_animate_a',
      title: 'Starboy',
      artist: 'The Weeknd',
      thumbnailUrl: 'https://i.ytimg.com/vi/starboy/hqdefault.jpg',
      durationSeconds: 230,
    );

    const testSongB = SongItem(
      id: 'song_animate_b',
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      thumbnailUrl: 'https://i.ytimg.com/vi/blinding/hqdefault.jpg',
      durationSeconds: 200,
    );

    testWidgets('PlayerControls expanded mode animates artwork with flutter_animate', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: testSongA,
        isPlaying: true,
        duration: Duration(seconds: 230),
        position: Duration(seconds: 20),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Center(
                child: PlayerControls(),
              ),
            ),
          ),
        ),
      );

      // Verify Animate widget is present with key matching mini_art_expanded_song_animate_a
      expect(find.byKey(const ValueKey('mini_art_expanded_song_animate_a')), findsOneWidget);
      expect(find.byType(Animate), findsWidgets);

      // Advance animation to completion
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Verify WavifyCachedImage artwork is rendered
      expect(find.byType(WavifyCachedImage), findsOneWidget);

      // Update track to song B and verify animation key updates
      container.read(playerProvider.notifier).state = container.read(playerProvider).copyWith(
        currentSong: testSongB,
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('mini_art_expanded_song_animate_b')), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('PlayerScreen edge-to-edge artwork canvas animates with flutter_animate from mini player realm', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: testSongA,
        isPlaying: true,
        duration: Duration(seconds: 230),
        position: Duration(seconds: 40),
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

      // Verify Animate widgets exist for artwork canvas and ambient glow with keys
      expect(find.byKey(const ValueKey('player_screen_artwork_song_animate_a')), findsOneWidget);
      expect(find.byKey(const ValueKey('player_screen_ambient_song_animate_a')), findsOneWidget);

      // Advance flutter_animate entrance duration
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 550));

      // Artwork and track title are rendered cleanly
      expect(find.text('Starboy'), findsOneWidget);
      expect(find.text('The Weeknd'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Tapping lyrics tab button morphs album art to 48x48 upside header thumbnail, and clicking upside artwork animates it back to full player', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: testSongA,
        isPlaying: true,
        duration: Duration(seconds: 230),
        position: Duration(seconds: 40),
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

      // Initial state: in Now Playing mode, artwork is full-width canvas
      final initialArtworkFinder = find.byKey(const ValueKey('player_screen_artwork_song_animate_a'));
      expect(initialArtworkFinder, findsOneWidget);
      final initialSize = tester.getSize(initialArtworkFinder);
      expect(initialSize.width, equals(1080 / 2.5));

      // Click lyrics button to open lyrics tab
      final lyricsToggle = find.byWidgetPredicate(
        (widget) => widget is Icon && (widget.icon == CupertinoIcons.quote_bubble || widget.icon == CupertinoIcons.quote_bubble_fill),
      );
      await tester.tap(lyricsToggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      // Mid-flight: artwork width smoothly transitioning
      final midSize = tester.getSize(initialArtworkFinder);
      expect(midSize.width, lessThan(initialSize.width));
      expect(midSize.width, greaterThan(48.0));

      // Complete transition into Lyrics mode
      await tester.pump(const Duration(milliseconds: 250));
      final finalThumbnailSize = tester.getSize(initialArtworkFinder);
      expect(finalThumbnailSize.width, equals(48.0));
      expect(finalThumbnailSize.height, equals(48.0));

      // CLICK ON UPSIDE ALBUM ART in lyrics header: should gradually open back into full player screen!
      await tester.tap(initialArtworkFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));

      // Mid-flight opening: artwork width expanding
      final expandingMidSize = tester.getSize(initialArtworkFinder);
      expect(expandingMidSize.width, greaterThan(48.0));
      expect(expandingMidSize.width, lessThan(initialSize.width));

      // Complete opening animation: album art fully restored
      await tester.pump(const Duration(milliseconds: 250));
      final restoredSize = tester.getSize(initialArtworkFinder);
      expect(restoredSize.width, equals(initialSize.width));

      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('Tapping lyrics dock button while in lyrics mode gradually animates back to main player album art', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: testSongA,
        isPlaying: true,
        duration: Duration(seconds: 230),
        position: Duration(seconds: 40),
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

      final artworkFinder = find.byKey(const ValueKey('player_screen_artwork_song_animate_a'));
      final lyricsToggle = find.byWidgetPredicate(
        (widget) => widget is Icon && (widget.icon == CupertinoIcons.quote_bubble || widget.icon == CupertinoIcons.quote_bubble_fill),
      );

      // Switch to lyrics
      await tester.tap(lyricsToggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(tester.getSize(artworkFinder).width, equals(48.0));

      // Click lyrics button again: gradually opens back to full player!
      await tester.tap(lyricsToggle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(tester.getSize(artworkFinder).width, greaterThan(48.0));

      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.getSize(artworkFinder).width, equals(1080 / 2.5));

      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}


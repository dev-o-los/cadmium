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
  });
}

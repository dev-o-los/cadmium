import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:wavify/models/lyric_line.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/favorites_provider.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/screens/player_screen.dart';
import 'package:wavify/services/artwork_color_service.dart';
import 'package:wavify/widgets/app_shimmer.dart';
import 'package:wavify/widgets/apple_lyrics_view.dart';
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

    testWidgets('PlayerScreen renders album art at 60% ratio and occupies rest for controls', (tester) async {
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

      // In expanded Now Playing mode, artwork height is fixed at 60% of screen height (600px)
      final heroFinder = find.byKey(const ValueKey('player_screen_artwork_song_a_1'));
      expect(heroFinder, findsOneWidget);

      final heroSize = tester.getSize(heroFinder);
      expect(heroSize.height, closeTo(screenH * 0.60, 2.0));

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

    testWidgets('Now Playing keeps 60/40 layout locked over time and after tap', (tester) async {
      const screenH = 1000.0;
      const screenW = 450.0;
      tester.view.physicalSize = const Size(screenW, screenH);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const animatedSong = SongItem(
        id: 'song_anim_60_40',
        title: 'Save Your Tears',
        artist: 'The Weeknd',
        album: 'After Hours',
        durationSeconds: 215,
        animatedArtworkUrl: 'https://example.com/loop.webp',
      );

      final container = ProviderContainer();
      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: animatedSong,
        animatedArtworkUrl: 'https://example.com/loop.webp',
        isPlaying: true,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: PlayerScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));

      final heroFinder = find.byKey(const ValueKey('player_screen_artwork_song_anim_60_40'));
      expect(tester.getSize(heroFinder).height, closeTo(screenH * 0.60, 2.0));

      // Tapping background or artwork in Now Playing never collapses controls to fullscreen
      await tester.tap(heroFinder);
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getSize(heroFinder).height, closeTo(screenH * 0.60, 2.0));
      expect(find.byIcon(CupertinoIcons.forward_fill), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('Queue stays docked and clear of bottom controls when 3-dots is opened', (tester) async {
      const screenH = 900.0;
      const screenW = 430.0;
      tester.view.physicalSize = const Size(screenW, screenH);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: testSongA,
        isPlaying: false,
        isAutoplay: true,
        isLoadingAutoplay: true,
        queue: [testSongB],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: PlayerScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // Switch to Queue tab
      await tester.tap(find.byIcon(CupertinoIcons.list_bullet));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Queue shimmer uses translucent white instead of opaque dark gray
      final shimmerFinder = find.byType(AppShimmer);
      expect(shimmerFinder, findsWidgets);
      final appShimmer = tester.widget<AppShimmer>(shimmerFinder.first);
      expect(appShimmer.baseColor, isNotNull);
      expect(appShimmer.baseColor!.a, lessThan(0.5));

      // Verify Queue area stops above bottom transport controls (no overlap)
      final queueRect = tester.getRect(find.byKey(const ValueKey('queue_mode')));
      final transportRect = tester.getRect(find.byIcon(CupertinoIcons.forward_fill));
      expect(queueRect.bottom, lessThanOrEqualTo(transportRect.top));

      // Open 3-dots menu from Queue header and verify bottom transport stays in place
      await tester.tap(find.byIcon(CupertinoIcons.ellipsis).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.text('Autoplay: On'), findsOneWidget);
      final transportRectAfter = tester.getRect(find.byIcon(CupertinoIcons.forward_fill));
      expect(transportRectAfter.top, closeTo(transportRect.top, 2.0));

      // Dismiss modal cleanly
      await tester.tapAt(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('AppleLyricsView renders AppleInstrumentalDots in intro, breaks, and instrumental lines', (tester) async {
      final lyrics = [
        const LyricLine(text: 'Opening verse', startTimeMs: 4000, endTimeMs: 7000),
        const LyricLine(text: '(Instrumental)', startTimeMs: 7500, endTimeMs: 12000),
        const LyricLine(text: 'Final chorus', startTimeMs: 17000, endTimeMs: 21000),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: AppleLyricsView(
                lyrics: lyrics,
                activeLyricIndex: 0,
                currentPositionMs: 1000,
                isPlaying: false,
                onSeekToLyric: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // At 1000ms (<4000ms opening verse): intro AppleInstrumentalDots + marker line AppleInstrumentalDots
      expect(find.byType(AppleInstrumentalDots), findsAtLeastNWidgets(2));
      expect(find.text('(Instrumental)'), findsNothing);

      // Update position into 4.5s break between marker (12000) and chorus (17000)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: AppleLyricsView(
                lyrics: lyrics,
                activeLyricIndex: 1,
                currentPositionMs: 13500,
                isPlaying: false,
                onSeekToLyric: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(AppleInstrumentalDots), findsAtLeastNWidgets(2));
    });

    test('PlayerNotifier setAutoplay(false) cancels loading and clears autoplayQueue', () {
      final container = ProviderContainer();
      final notifier = container.read(playerProvider.notifier);

      notifier.state = const PlayerStateModel(
        currentSong: testSongA,
        isAutoplay: true,
        isLoadingAutoplay: true,
        autoplayQueue: [testSongB],
      );

      notifier.setAutoplay(false);
      final updated = container.read(playerProvider);
      expect(updated.isAutoplay, isFalse);
      expect(updated.isLoadingAutoplay, isFalse);
      expect(updated.autoplayQueue, isEmpty);

      container.dispose();
    });

    testWidgets('Audio Output sheet has no Android Cast card and PlayerScreen blends video blur into colored bottom player', (tester) async {
      const screenH = 900.0;
      const screenW = 430.0;
      tester.view.physicalSize = const Size(screenW, screenH);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const songWithArt = SongItem(
        id: 'song_blend_art',
        title: 'Midnight City',
        artist: 'M83',
        album: 'Hurry Up, Were Dreaming',
        thumbnailUrl: 'https://example.com/art.jpg',
      );

      final container = ProviderContainer();
      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: songWithArt,
        isPlaying: false,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: PlayerScreen()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify downward ShaderMask mix and BackdropFilter blur band are present
      expect(find.byType(ShaderMask), findsAtLeastNWidgets(1));
      expect(find.byType(BackdropFilter), findsAtLeastNWidgets(1));

      // Open Audio Output sheet and confirm Android Cast option was removed
      await tester.tap(find.byIcon(CupertinoIcons.speaker_2_fill));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Audio Output'), findsOneWidget);
      expect(find.text('Cast'), findsNothing);
      expect(find.text('Chromecast and Google Cast speakers'), findsNothing);
      expect(find.byIcon(Icons.cast_rounded), findsNothing);

      Navigator.of(tester.element(find.text('Audio Output'))).pop();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    test('ArtworkColorService ignores YouTube video thumbnails/streams and refreshes when album artwork resolves', () async {
      expect(
        ArtworkColorService.isVideoOrNonArtworkUrl(
          'https://i.ytimg.com/vi/abc123/maxresdefault.jpg',
        ),
        isTrue,
      );
      expect(
        ArtworkColorService.isVideoOrNonArtworkUrl(
          'https://example.com/loop.mp4',
        ),
        isTrue,
      );
      expect(
        ArtworkColorService.isVideoOrNonArtworkUrl(
          'https://lh3.googleusercontent.com/cover=w800-h800-l95-rj',
        ),
        isFalse,
      );

      const videoThumbSong = SongItem(
        id: 'same_id_1',
        title: 'Starboy',
        artist: 'The Weeknd',
        thumbnailUrl: 'https://i.ytimg.com/vi/same_id_1/hqdefault.jpg',
        animatedArtworkUrl: 'https://example.com/video.mp4',
      );
      expect(
        ArtworkColorService.extractableArtworkUrl(
          highResUrl: videoThumbSong.highResThumbnailUrl,
          resolvedUrl: videoThumbSong.resolvedThumbnailUrl,
          thumbnailUrl: videoThumbSong.thumbnailUrl,
        ),
        isNull,
      );

      final albumArtSong = videoThumbSong.copyWith(
        thumbnailUrl: 'https://lh3.googleusercontent.com/starboy=w544-h544-l90-rj',
      );
      expect(
        ArtworkColorService.extractableArtworkUrl(
          highResUrl: albumArtSong.highResThumbnailUrl,
          resolvedUrl: albumArtSong.resolvedThumbnailUrl,
          thumbnailUrl: albumArtSong.thumbnailUrl,
        ),
        'https://lh3.googleusercontent.com/starboy=w800-h800-l95-rj',
      );

      final container = ProviderContainer();
      container.read(playerProvider.notifier).state = const PlayerStateModel(
        currentSong: videoThumbSong,
      );
      await container.read(currentSongPrimaryColorProvider.future);

      int providerBuilds = 0;
      final sub = container.listen(currentSongPrimaryColorProvider, (_, _) {
        providerBuilds++;
      });

      // Updating thumbnailUrl on same SongItem id must trigger color provider recomputation
      container.read(playerProvider.notifier).state = PlayerStateModel(
        currentSong: albumArtSong,
      );
      await container.read(currentSongPrimaryColorProvider.future);
      expect(providerBuilds, greaterThan(0));

      sub.close();
      container.dispose();
    });
  });
}

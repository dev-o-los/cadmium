import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavify/models/album_item.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/library_provider.dart';
import 'package:wavify/providers/music_service_provider.dart';
import 'package:wavify/providers/navigation_provider.dart';
import 'package:wavify/screens/album_screen.dart';
import 'package:wavify/screens/player_screen.dart';
import 'package:wavify/services/artwork_color_service.dart';
import 'package:wavify/services/music_service.dart';
import 'package:wavify/services/song_metrics_cache_service.dart';
import 'package:wavify/widgets/app_shimmer.dart';
import 'package:wavify/widgets/liquid_glass_bottom_bar.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const testAlbum = AlbumItem(
    id: 'test_pink_heartz',
    title: 'Pink Heartz',
    artist: 'SoFaygo',
    type: 'Album',
    year: 2022,
    thumbnailUrl: 'https://example.com/pink_heartz.jpg',
  );

  Widget createAlbumScreen() {
    return const ProviderScope(
      child: MaterialApp(
        home: AlbumScreen(album: testAlbum),
      ),
    );
  }

  testWidgets('AlbumScreen renders ambient header, metadata, action buttons, and about section',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(createAlbumScreen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 1. Verify Album Title & Artist
    expect(find.text('Pink Heartz'), findsWidgets);
    expect(find.text('SoFaygo'), findsWidgets);

    // 2. Verify Action Buttons: Shuffle, Play, Bookmark
    expect(find.byIcon(CupertinoIcons.shuffle), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);

    // 3. Verify Top Navigation Bar & Action Pill
    expect(find.byIcon(CupertinoIcons.chevron_back), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.search), findsNWidgets(2)); // top action dock + bottom bar trailing search
    expect(find.byIcon(CupertinoIcons.slider_horizontal_3), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.ellipsis), findsOneWidget);

    // Verify Liquid Glass integration: 3 circular GlassIconButtons (back, shuffle, bookmark) and 1 GlassButtonGroup
    expect(find.byType(GlassIconButton), findsNWidgets(3));
    expect(find.byType(GlassButtonGroup), findsOneWidget);

    // Verify Persistent Bottom Navigation Bar is present on AlbumScreen
    expect(find.byType(LiquidGlassBottomBar), findsOneWidget);

    // 4. Verify "About the album" and "More" button
    expect(find.text('About the album'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);

    // 5. Tap "More" to expand description
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Less'), findsOneWidget);
  });

  testWidgets('Tapping Bookmark on AlbumScreen toggles album saved in library',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AlbumScreen(album: testAlbum),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Initially not saved
    expect(container.read(savedAlbumsProvider).any((a) => a.id == testAlbum.id), isFalse);

    // Tap bookmark button (plus icon)
    final plusFinder = find.byIcon(CupertinoIcons.plus);
    expect(plusFinder, findsOneWidget);
    await tester.tap(plusFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Now saved!
    expect(container.read(savedAlbumsProvider).any((a) => a.id == testAlbum.id), isTrue);
  });

  testWidgets('Tapping Play on AlbumScreen launches PlayerScreen',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(createAlbumScreen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Tap Play button
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Player screen mounts
    expect(find.byType(PlayerScreen), findsOneWidget);
  });

  testWidgets('Scrolling album content dynamically renders progressive blur and shader at top',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(createAlbumScreen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Initially at top (offset 0), blur is idle (SizedBox.shrink)
    expect(find.byType(ProgressiveBlur), findsNothing);

    // Scroll content up by dragging
    await tester.drag(find.text('Pink Heartz').first, const Offset(0, -250));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Progressive blur is mounted behind floating buttons
    expect(find.byType(ProgressiveBlur), findsOneWidget);
  });

  testWidgets('Tapping tab in bottom bar on AlbumScreen switches active tab index',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: AlbumScreen(album: testAlbum),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Initially tab is 0 (Home)
    expect(container.read(currentTabProvider), 0);

    // Tap Explore tab (index 1) in the bottom navigation bar
    await tester.tap(find.byIcon(CupertinoIcons.square_grid_2x2_fill).first);
    await tester.pump();

    // currentTabProvider is updated to 1
    expect(container.read(currentTabProvider), 1);
  });

  testWidgets('AlbumScreen shows shimmer widgets while loading without broken placeholder text',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    const noArtAlbum = AlbumItem(
      id: 'loading_album',
      title: 'Loading Album',
      artist: 'Test Artist',
      type: 'Album',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicServiceProvider.overrideWithValue(_DelayedAlbumMusicService()),
        ],
        child: const MaterialApp(
          home: AlbumScreen(album: noArtAlbum),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TrackListSkeleton), findsOneWidget);
    expect(find.byType(AppShimmer), findsWidgets);
    expect(find.textContaining('0 Tracks'), findsNothing);
    expect(find.textContaining('total runtime of .'), findsNothing);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('AlbumScreen hydrates missing song durations from SongMetricsCacheService and displays timestamps',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await SongMetricsCacheService.instance.setDuration('track_cached_dur', 222);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          musicServiceProvider.overrideWithValue(_AlbumWithMissingDurMusicService()),
        ],
        child: const MaterialApp(
          home: AlbumScreen(album: testAlbum),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Track One'), findsOneWidget);
    expect(find.text('Track Two'), findsOneWidget);
    expect(find.text('3:42'), findsOneWidget);
    expect(find.text('4:05'), findsOneWidget);
  });

  test('MusicService duration parsers and ArtworkColorService fallback tone work across edge formats', () {
    expect(MusicService.parseDurationString('3:42'), 222);
    expect(MusicService.parseDurationString('1:02:05'), 3725);
    expect(MusicService.parseDurationString('Song • 4:05'), 245);
    expect(MusicService.parseDurationString('3 minutes, 42 seconds'), 222);
    expect(MusicService.parseDurationString('abc:def'), isNull);

    final flexItem = <String, dynamic>{
      'flexColumns': [
        {
          'musicResponsiveListItemFlexColumnRenderer': {
            'text': {
              'runs': [
                {'text': 'Track Title'},
              ],
            },
          },
        },
        {
          'musicResponsiveListItemFlexColumnRenderer': {
            'text': {
              'runs': [
                {'text': 'Artist'},
                {'text': ' • '},
                {'text': '3:42'},
              ],
            },
          },
        },
      ],
    };
    expect(MusicService.extractDurationFromRenderer(flexItem), 222);

    final a11yItem = <String, dynamic>{
      'fixedColumns': [
        {
          'musicResponsiveListItemFixedColumnRenderer': {
            'text': {
              'accessibility': {
                'accessibilityData': {'label': '4 minutes, 5 seconds'},
              },
            },
          },
        },
      ],
    };
    expect(MusicService.extractDurationFromRenderer(a11yItem), 245);

    final fallbackTone = ArtworkColorService.instance.getFallbackAttractiveColor('SoFaygo');
    expect(HSLColor.fromColor(fallbackTone).lightness, lessThanOrEqualTo(0.30));
  });
}

class _DelayedAlbumMusicService extends MusicService {
  @override
  Future<AlbumDetails> getAlbumDetails(
    AlbumItem initialAlbum, {
    String? queryFallback,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return AlbumDetails(album: initialAlbum, tracks: const [], totalDurationSeconds: 0);
  }
}

class _AlbumWithMissingDurMusicService extends MusicService {
  @override
  Future<AlbumDetails> getAlbumDetails(
    AlbumItem initialAlbum, {
    String? queryFallback,
  }) async {
    return AlbumDetails(
      album: initialAlbum.copyWith(trackCount: 2),
      tracks: const [
        SongItem(
          id: 'track_cached_dur',
          title: 'Track One',
          artist: 'SoFaygo',
          durationSeconds: null,
        ),
        SongItem(
          id: 'track_explicit_dur',
          title: 'Track Two',
          artist: 'SoFaygo',
          durationSeconds: 245,
        ),
      ],
      totalDurationSeconds: 467,
    );
  }
}

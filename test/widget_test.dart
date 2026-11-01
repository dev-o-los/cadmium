import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/main.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/models/album_item.dart';
import 'package:wavify/models/home_data.dart';
import 'package:wavify/providers/home_data_provider.dart';
import 'package:wavify/screens/home_screen.dart';
import 'package:wavify/screens/player_screen.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/widgets/liquid_glass_bottom_bar.dart';
import 'package:wavify/widgets/player_controls.dart';

class _MockHomeDataNotifier extends HomeDataNotifier {
  final HomeData mockData;
  _MockHomeDataNotifier(this.mockData);

  @override
  Future<HomeData> build() async => mockData;
}

void main() {
  testWidgets('WavifyApp Liquid Glass Navigation Bar UI smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: WavifyApp(),
      ),
    );

    // Verify Liquid Glass navigation bar dock with Home, Explore, Library, and Search
    expect(find.byType(LiquidGlassBottomBar), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Explore'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
    expect(find.byIcon(CupertinoIcons.search), findsWidgets);
    expect(find.text('Radio'), findsNothing);
  });

  testWidgets('LiquidGlassBottomBar & PlayerControls morph between expanded and minimized states',
      (WidgetTester tester) async {
    const testSong = SongItem(
      id: 'test_song_1',
      title: 'Me Too',
      artist: 'SoFaygo',
      album: 'Pink Heartz',
      durationSeconds: 180,
    );

    bool expandedTapped = false;
    int selectedTab = 0;

    Widget buildTestWidget({required bool isCrawled}) {
      return ProviderScope(
        overrides: [
          playerProvider.overrideWith((ref) {
            final notifier = PlayerNotifier(ref);
            notifier.state = notifier.state.copyWith(
              currentSong: testSong,
              isPlaying: true,
              duration: const Duration(seconds: 180),
              position: const Duration(seconds: 45),
            );
            return notifier;
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LiquidGlassBottomBar(
                    currentIndex: selectedTab,
                    isCrawled: isCrawled,
                    onTabSelected: (index) => selectedTab = index,
                    onExpand: () => expandedTapped = true,
                    bottomAccessory: const PlayerControls(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 1. Expanded State (isCrawled: false)
    await tester.pumpWidget(buildTestWidget(isCrawled: false));
    await tester.pumpAndSettle();

    expect(find.text('Me Too'), findsOneWidget);
    expect(find.text('SoFaygo'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.play_fill), findsWidgets);
    expect(find.byIcon(CupertinoIcons.forward_fill), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // 2. Minimized State (isCrawled: true)
    await tester.pumpWidget(buildTestWidget(isCrawled: true));
    await tester.pumpAndSettle();

    // Verify inline compact player is rendered
    expect(find.text('Me Too'), findsOneWidget);
    expect(find.text('SoFaygo'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.play_fill), findsWidgets);
    expect(find.byIcon(CupertinoIcons.forward_fill), findsWidgets);
    // In inline mode, the hairline progress bar is omitted for a clean minimal dock
    expect(find.byType(LinearProgressIndicator), findsNothing);

    // Verify tapping on the search button calls onTabSelected
    await tester.tap(find.byIcon(CupertinoIcons.search).first);
    expect(selectedTab, 3);

    // Verify tapping the collapsed active tab calls onExpand
    await tester.tap(find.byIcon(CupertinoIcons.house_fill).first);
    expect(expandedTapped, isTrue);
  });

  testWidgets('Tapping album art single directly launches player and does not redirect to search',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const testAlbum = AlbumItem(
      id: 'album_test_1',
      title: 'Starboy',
      artist: 'The Weeknd',
      type: 'Single',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeDataProvider.overrideWith(
            () => _MockHomeDataNotifier(
              const HomeData(
                heroCards: [],
                recents: [],
                quickPicks: [],
                moods: [],
                albumsAndSingles: [testAlbum],
                musicVideos: [],
                dailyDiscover: [],
                genres: [],
                trendingSongs: [],
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    // Initial pump
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify 'Starboy' album tile is displayed under 'Albums & singles'
    expect(find.text('Starboy'), findsOneWidget);
    expect(find.text('Albums & singles'), findsOneWidget);

    // Tap on the album card
    await tester.tap(find.text('Starboy'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Dedicated AlbumScreen should now be mounted!
    expect(find.byType(AlbumScreen), findsOneWidget);

    // Tapping Play on AlbumScreen launches the full player
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PlayerScreen), findsOneWidget);
  });

  testWidgets('List with 2 elements dynamically calculates responsive height instead of fixed 256px',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const song1 = SongItem(
      id: 'song_1',
      title: 'Track One',
      artist: 'Artist One',
    );
    const song2 = SongItem(
      id: 'song_2',
      title: 'Track Two',
      artist: 'Artist Two',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeDataProvider.overrideWith(
            () => _MockHomeDataNotifier(
              const HomeData(
                heroCards: [],
                recents: [song1, song2], // Only 2 elements
                quickPicks: [],
                moods: [],
                albumsAndSingles: [],
                musicVideos: [],
                dailyDiscover: [],
                genres: [],
                trendingSongs: [],
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: HomeScreen(),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Both songs should be displayed
    expect(find.text('Track One'), findsOneWidget);
    expect(find.text('Track Two'), findsOneWidget);

    // Verify the section container height for 2 elements is dynamically 128px (2 * 64px),
    // instead of the previous hardcoded 256px
    final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
    final sectionBox = sizedBoxes.firstWhere(
      (b) => b.height == 128.0,
      orElse: () => const SizedBox(),
    );
    expect(sectionBox.height, 128.0);
  });
}

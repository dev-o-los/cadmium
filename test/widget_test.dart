import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/main.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/widgets/liquid_glass_bottom_bar.dart';
import 'package:wavify/widgets/player_controls.dart';

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
}

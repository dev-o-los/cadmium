import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wavify/models/album_item.dart';
import 'package:wavify/providers/library_provider.dart';
import 'package:wavify/providers/navigation_provider.dart';
import 'package:wavify/screens/album_screen.dart';
import 'package:wavify/screens/player_screen.dart';
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
}

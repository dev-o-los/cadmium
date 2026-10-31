import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/screens/player_screen.dart';

void main() {
  testWidgets('PlayerScreen mounts and transitions modes with Riverpod without setState errors', (WidgetTester tester) async {
    // Set standard phone aspect ratio for widget tester
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const testSong = SongItem(
      id: 'test_123',
      title: 'Me Too',
      artist: 'SoFaygo',
      durationSeconds: 210,
    );

    const testQueue = [
      SongItem(id: 'q1', title: 'Goin Back', artist: 'SoFaygo'),
      SongItem(id: 'q2', title: 'Another One', artist: 'SoFaygo'),
    ];

    final container = ProviderContainer();

    // Seed player with current track, duration, and queue
    container.read(playerProvider.notifier).state = PlayerStateModel(
      currentSong: testSong,
      isPlaying: true,
      queue: testQueue,
      duration: const Duration(seconds: 210),
      position: const Duration(seconds: 20),
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

    // Initial render in Now Playing mode
    expect(find.text('Me Too'), findsOneWidget);
    expect(find.text('SoFaygo'), findsOneWidget);
    expect(find.text('Playing from SoFaygo'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);

    // Switch to Lyrics View
    final lyricsButton = find.byIcon(Icons.chat_bubble_outline_rounded);
    expect(lyricsButton, findsOneWidget);
    await tester.tap(lyricsButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // Verify "No lyrics available right now" requirement is met when lyrics are empty
    expect(find.text('No lyrics available right now'), findsOneWidget);

    // Switch to Queue View
    final queueButton = find.byIcon(Icons.format_list_bulleted_rounded);
    expect(queueButton, findsOneWidget);
    await tester.tap(queueButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // Verify Queue view rendered with upcoming tracks
    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Goin Back'), findsOneWidget);
    expect(find.text('Another One'), findsOneWidget);

    // Clean unmount
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}

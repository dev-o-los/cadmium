import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/models/audio_device_item.dart';
import 'package:wavify/models/lyric_line.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/music_service_provider.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/screens/player_screen.dart';
import 'package:wavify/services/music_service.dart';
import 'package:wavify/widgets/player_controls.dart';

class MockMusicService extends MusicService {
  @override
  Future<AudioStreamInfo> resolveAudioStream(String videoId) async {
    return const AudioStreamInfo(
      url: 'https://example.com/audio.mp3',
      headers: {},
      bitrate: 128000,
      mimeType: 'audio/mp4',
    );
  }

  @override
  Future<List<LyricLine>> getLyrics(String videoId) async => const [];
}

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
    final lyricsButton = find.byIcon(CupertinoIcons.quote_bubble);
    expect(lyricsButton, findsOneWidget);
    await tester.tap(lyricsButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    // Verify "No lyrics available right now" requirement is met when lyrics are empty
    expect(find.text('No lyrics available right now'), findsOneWidget);

    // Switch to Queue View
    final queueButton = find.byIcon(CupertinoIcons.list_bullet);
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

  testWidgets('Play/Pause button responds immediately on first render', (tester) async {
    final container = ProviderContainer(
      overrides: [
        musicServiceProvider.overrideWithValue(MockMusicService()),
      ],
    );
    const testSong = SongItem(
      id: 'test_song_first_render',
      title: 'Me Too',
      artist: 'SoFaygo',
      album: 'Pink Heartz',
      thumbnailUrl: 'https://yt3.googleusercontent.com/test=w120-h120',
      durationSeconds: 192,
    );

    // Seed state directly to simulate active track resolving/playing on first render
    container.read(playerProvider.notifier).state = const PlayerStateModel(
      currentSong: testSong,
      isPlaying: true,
      isResolvingStream: true,
      duration: Duration(seconds: 192),
      position: Duration(seconds: 10),
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

    // Initial render: playing state active, pause icon shown
    expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);

    // Tap pause button on first render
    await tester.tap(find.byIcon(CupertinoIcons.pause_fill));
    await tester.pump();
    await tester.pumpAndSettle();

    // Verify it responds instantly on first render to show play icon
    expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);

    // Tap play button
    await tester.tap(find.byIcon(CupertinoIcons.play_fill));
    await tester.pump();
    await tester.pumpAndSettle();

    // Verify it responds instantly to show pause icon
    expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('PlayerScreen dynamically displays the actual connected audio output device',
      (WidgetTester tester) async {
    const testSong = SongItem(
      id: 'test_dev_1',
      title: 'Me Too',
      artist: 'SoFaygo',
      durationSeconds: 200,
    );

    const bluetoothDevice = AudioDeviceItem(
      id: 'bt_headphones',
      name: 'AirPods Pro',
      category: OutputDeviceCategory.bluetooth,
      isSelected: true,
    );

    const speakerDevice = AudioDeviceItem(
      id: 'speaker',
      name: 'Phone Speaker',
      category: OutputDeviceCategory.speaker,
      isSelected: false,
    );

    final container = ProviderContainer();

    // 1. Seed player with active Bluetooth headphones device
    container.read(playerProvider.notifier).state = PlayerStateModel(
      currentSong: testSong,
      isPlaying: true,
      connectedDevice: bluetoothDevice,
      availableAudioDevices: const [bluetoothDevice, speakerDevice],
      duration: const Duration(seconds: 200),
      position: const Duration(seconds: 15),
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

    // Verify the actual connected Bluetooth device name is displayed
    expect(find.text('AirPods Pro'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.headphones), findsWidgets);

    // 2. Simulate switching to Phone Speaker
    container.read(playerProvider.notifier).state = container.read(playerProvider).copyWith(
          connectedDevice: speakerDevice.copyWith(isSelected: true),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify the label now displays Phone Speaker
    expect(find.text('Phone Speaker'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.speaker_2_fill), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}

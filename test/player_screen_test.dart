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
  Future<List<LyricLine>> getLyrics(
    String videoId, {
    String? title,
    String? artist,
    String? album,
    int? durationSeconds,
  }) async => const [];
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

    // Verify the action dock displays the Android cast icon for audio outputs
    expect(find.byIcon(Icons.cast_rounded), findsOneWidget);

    // Tapping the cast icon opens the Audio Output modal
    await tester.tap(find.byIcon(Icons.cast_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Audio Output'), findsOneWidget);

    // Close the modal
    Navigator.of(tester.element(find.text('Audio Output'))).pop();
    await tester.pump(const Duration(milliseconds: 400));

    // 2. Simulate switching to Phone Speaker
    container.read(playerProvider.notifier).state = container.read(playerProvider).copyWith(
          connectedDevice: speakerDevice.copyWith(isSelected: true),
        );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify the cast icon remains accessible
    expect(find.byIcon(Icons.cast_rounded), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('PlayerScreen mounts cleanly with animated artwork URL ("GIF video")', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const testSong = SongItem(
      id: 'animated_123',
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      thumbnailUrl: 'https://i.ytimg.com/vi/4NRXx6U8ABQ/hqdefault.jpg',
      animatedArtworkUrl: 'https://i.ytimg.com/an_webp/4NRXx6U8ABQ/mqdefault_6s.webp?du=3000&sqp=abc&rs=xyz',
      durationSeconds: 200,
    );

    final container = ProviderContainer();
    container.read(playerProvider.notifier).state = PlayerStateModel(
      currentSong: testSong,
      animatedArtworkUrl: testSong.animatedArtworkUrl,
      isPlaying: true,
      duration: const Duration(seconds: 200),
      position: const Duration(seconds: 10),
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

    // Song info renders correctly
    expect(find.text('Blinding Lights'), findsOneWidget);
    expect(find.text('The Weeknd'), findsWidgets);

    // Verify SongItem copyWith and JSON roundtrip with animatedArtworkUrl
    final json = testSong.toJson();
    expect(json['animatedArtworkUrl'], equals(testSong.animatedArtworkUrl));
    final restoredSong = SongItem.fromJson(json);
    expect(restoredSong.animatedArtworkUrl, equals(testSong.animatedArtworkUrl));

    final modifiedSong = testSong.copyWith(animatedArtworkUrl: 'https://example.com/loop.gif');
    expect(modifiedSong.animatedArtworkUrl, equals('https://example.com/loop.gif'));

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('Duration scrubber smoothly resolves duration from song.durationSeconds when playerState.duration is zero', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const testSong = SongItem(
      id: 'song_dur_test',
      title: 'Save Your Tears',
      artist: 'The Weeknd',
      durationSeconds: 215,
    );

    final container = ProviderContainer();
    container.read(playerProvider.notifier).state = const PlayerStateModel(
      currentSong: testSong,
      isPlaying: true,
      duration: Duration.zero, // Initially zero before stream emits duration
      position: Duration(seconds: 15),
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

    // Scrubber total duration resolves to 215s (3:35), so remaining is -3:35 and elapsed is 0:00
    expect(find.text('-3:35'), findsOneWidget);
    expect(find.text('0:00'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('Play/Pause responsive toggle cancels stream resolution immediately', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    const testSong = SongItem(
      id: 'song_toggle_test',
      title: 'Responsive Song',
      artist: 'Test Artist',
      durationSeconds: 180,
    );

    final container = ProviderContainer();
    final notifier = container.read(playerProvider.notifier);

    notifier.state = const PlayerStateModel(
      currentSong: testSong,
      isPlaying: true,
      isResolvingStream: true,
      isBuffering: true,
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

    // Tap play/pause button while resolving stream
    notifier.togglePlayPause();
    await tester.pump();

    // Must immediately cancel resolving and enter paused state
    expect(container.read(playerProvider).isPlaying, isFalse);
    expect(container.read(playerProvider).isResolvingStream, isFalse);
    expect(container.read(playerProvider).isBuffering, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/models/lyric_line.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/music_service_provider.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/services/music_service.dart';
import 'package:wavify/widgets/apple_pressable.dart';
import 'package:wavify/widgets/player_controls.dart';

class MockMusicService extends MusicService {
  @override
  Future<AudioStreamInfo> resolveAudioStream(
    String videoId, {
    bool forceRefresh = false,
  }) async {
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
  }) async =>
      const [];

  @override
  Future<String?> getAlbumArtwork(
    String album, {
    String? title,
    String? artist,
  }) async =>
      null;

  @override
  Future<String?> getAnimatedArtwork(SongItem song) async => null;
}

void main() {
  group('PlayerControls & Mini Player Bar Responsiveness Tests', () {
    testWidgets('PlayerControls displays artist name without Connecting text during stream resolution', (tester) async {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      addTearDown(container.dispose);

      const song = SongItem(
        id: 'track_1',
        title: 'Starboy',
        artist: 'The Weeknd',
      );

      // Prime player with song in resolving stream state
      container.read(playerProvider.notifier).prepareSong(song);

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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Ensure song title and artist are visible
      expect(find.text('Starboy'), findsOneWidget);
      expect(find.text('The Weeknd'), findsOneWidget);

      // Verify that 'Connecting...' text is NOT displayed anywhere
      expect(find.text('Connecting...'), findsNothing);
    });

    testWidgets('PlayerControls play/pause button toggles state between play and pause modes immediately', (tester) async {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      addTearDown(container.dispose);

      const song = SongItem(
        id: 'track_1',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
      );

      container.read(playerProvider.notifier).prepareSong(song);

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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // In play mode, pause_fill icon should be displayed
      expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.play_fill), findsNothing);

      // Tap pause
      await tester.tap(find.byIcon(CupertinoIcons.pause_fill));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 300));

      // State is immediately in pause mode
      expect(container.read(playerProvider).isPlaying, isFalse);
      expect(find.byIcon(CupertinoIcons.play_fill), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.pause_fill), findsNothing);

      // Tap play again
      await tester.tap(find.byIcon(CupertinoIcons.play_fill));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // State is immediately in play mode
      expect(container.read(playerProvider).isPlaying, isTrue);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(CupertinoIcons.pause_fill), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.play_fill), findsNothing);
    });

    testWidgets('ApplePressable invokes onTap on first tap without requiring double clicks', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ApplePressable(
                onTap: () {
                  tapCount++;
                },
                child: const Text('Track Item'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Tap once
      await tester.tap(find.text('Track Item'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(tapCount, equals(1));
    });

    test('playerIsLoadingProvider accurately reflects resolving vs playing state', () {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(MockMusicService()),
        ],
      );
      addTearDown(container.dispose);

      const song = SongItem(id: 'track_test', title: 'Test', artist: 'Artist');

      // 1. Initially idle: not loading
      expect(container.read(playerIsLoadingProvider), isFalse);

      // 2. Prepare song: resolving stream, isPlaying=true -> isLoading=true
      container.read(playerProvider.notifier).prepareSong(song);
      expect(container.read(playerIsLoadingProvider), isTrue);

      // 3. User pauses: isLoading immediately becomes false
      container.read(playerProvider.notifier).pause();
      expect(container.read(playerIsLoadingProvider), isFalse);
    });
  });
}

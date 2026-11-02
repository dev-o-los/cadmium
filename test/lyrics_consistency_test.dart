import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/models/lyric_line.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/music_service_provider.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/services/lyrics_service.dart';
import 'package:wavify/services/music_service.dart';
import 'package:wavify/widgets/apple_lyrics_view.dart';

class ConsistencyMockMusicService extends MusicService {
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
  Future<LyricsResult> getLyricsWithMetadata({
    required String videoId,
    required String title,
    required String artist,
    String? album,
    String? isrc,
    int? durationSeconds,
    LyricsProviderType provider = LyricsProviderType.lrcRed,
  }) async {
    if (provider == LyricsProviderType.lrcRed) {
      return LyricsResult(
        lines: [
          const LyricLine(text: '', startTimeMs: 0, endTimeMs: 4000), // Intro dots
          const LyricLine(text: 'LRC Line 1', startTimeMs: 4000, endTimeMs: 8000),
          const LyricLine(text: 'LRC Line 2', startTimeMs: 8000, endTimeMs: 12000),
          const LyricLine(text: 'LRC Line 3', startTimeMs: 12000, endTimeMs: 16000),
        ],
        source: 'lrc.red',
        hasWordSync: true,
      );
    } else {
      return LyricsResult(
        lines: [
          const LyricLine(text: '', startTimeMs: 0, endTimeMs: 4000), // Intro dots
          const LyricLine(text: 'YT Line 1', startTimeMs: 4000, endTimeMs: 8000),
          const LyricLine(text: 'YT Line 2', startTimeMs: 8000, endTimeMs: 12000),
          const LyricLine(text: 'YT Line 3', startTimeMs: 12000, endTimeMs: 16000),
        ],
        source: 'YouTube Music',
        hasWordSync: false,
      );
    }
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.ryanheise.just_audio.methods'),
      (MethodCall methodCall) async {
        return null;
      },
    );
  });

  group('Lyrics Consistency and Responsiveness Tests', () {
    testWidgets('tapping lyric line bounces immediately to timestamp and active index', (tester) async {
      final lines = [
        const LyricLine(text: 'Verse 1', startTimeMs: 5000, endTimeMs: 10000),
        const LyricLine(text: 'Verse 2', startTimeMs: 10000, endTimeMs: 15000),
        const LyricLine(text: 'Chorus', startTimeMs: 15000, endTimeMs: 20000),
      ];

      LyricLine? tappedLine;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppleLyricsView(
              lyrics: lines,
              activeLyricIndex: 0,
              currentPositionMs: 5500,
              onSeekToLyric: (line) {
                tappedLine = line;
              },
            ),
          ),
        ),
      );

      // Tap 'Chorus' (15000ms)
      await tester.tap(find.text('Chorus'));
      await tester.pump();

      expect(tappedLine, isNotNull);
      expect(tappedLine!.text, 'Chorus');
      expect(tappedLine!.startTimeMs, 15000);
    });

    test('PlayerNotifier seekToLyric updates position and activeLyricIndex synchronously', () {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(ConsistencyMockMusicService()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playerProvider.notifier);
      final song = const SongItem(id: 'test_1', title: 'Test Song', artist: 'Artist');

      // Populate lyrics in state
      notifier.prepareSong(song);
      final lines = [
        const LyricLine(text: '', startTimeMs: 0, endTimeMs: 3000),
        const LyricLine(text: 'Line 1', startTimeMs: 3000, endTimeMs: 7000),
        const LyricLine(text: 'Line 2', startTimeMs: 7000, endTimeMs: 12000),
      ];
      container.read(playerProvider.notifier).state = container.read(playerProvider).copyWith(
        lyrics: lines,
        activeLyricIndex: 0,
        position: Duration.zero,
      );

      // Tap Line 2
      notifier.seekToLyric(lines[2]);

      final stateAfterTap = container.read(playerProvider);
      expect(stateAfterTap.position.inMilliseconds, equals(7000));
      expect(stateAfterTap.activeLyricIndex, equals(2));
    });

    test('sliding / seeking track updates position and active lyric synchronously', () {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(ConsistencyMockMusicService()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playerProvider.notifier);
      final song = const SongItem(id: 'test_2', title: 'Test Song 2', artist: 'Artist 2');

      notifier.prepareSong(song);
      final lines = [
        const LyricLine(text: '', startTimeMs: 0, endTimeMs: 4000),
        const LyricLine(text: 'Line 1', startTimeMs: 4000, endTimeMs: 8000),
        const LyricLine(text: 'Line 2', startTimeMs: 8000, endTimeMs: 12000),
      ];
      container.read(playerProvider.notifier).state = container.read(playerProvider).copyWith(
        lyrics: lines,
        activeLyricIndex: 0,
        position: Duration.zero,
      );

      // Slide to 9.5 seconds (middle of Line 2)
      notifier.seek(const Duration(milliseconds: 9500));

      final state = container.read(playerProvider);
      expect(state.position.inMilliseconds, equals(9500));
      expect(state.activeLyricIndex, equals(2));

      // Slide back to 2 seconds (in intro gap)
      notifier.seek(const Duration(milliseconds: 2000));

      final stateBack = container.read(playerProvider);
      expect(stateBack.position.inMilliseconds, equals(2000));
      expect(stateBack.activeLyricIndex, equals(0)); // Intro gap line
    });

    test('switching between YouTube and lrc.red maintains correct activeLyricIndex', () async {
      final container = ProviderContainer(
        overrides: [
          musicServiceProvider.overrideWithValue(ConsistencyMockMusicService()),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(playerProvider.notifier);
      final song = const SongItem(id: 'test_3', title: 'Test Song 3', artist: 'Artist 3');

      // Seed state with current song and seek to 9000ms
      notifier.prepareSong(song);
      notifier.seek(const Duration(milliseconds: 9000));

      // Switch to YouTube at 9 seconds
      notifier.setLyricsProvider(LyricsProviderType.youTube);
      await Future.delayed(const Duration(milliseconds: 50));

      final ytState = container.read(playerProvider);
      expect(ytState.selectedLyricsProvider, equals(LyricsProviderType.youTube));
      expect(ytState.lyrics, isNotEmpty);
      expect(ytState.lyrics.first.text, equals('')); // Intro gap
      expect(ytState.activeLyricIndex, equals(2)); // At 9000ms, YT Line 2 (8000-12000)

      // Switch back to lrc.red
      notifier.setLyricsProvider(LyricsProviderType.lrcRed);
      await Future.delayed(const Duration(milliseconds: 50));

      final lrcState = container.read(playerProvider);
      expect(lrcState.selectedLyricsProvider, equals(LyricsProviderType.lrcRed));
      expect(lrcState.lyrics, isNotEmpty);
      expect(lrcState.lyrics.first.text, equals('')); // Intro gap
      expect(lrcState.activeLyricIndex, equals(2)); // At 9000ms, LRC Line 2 (8000-12000)
    });
  });
}

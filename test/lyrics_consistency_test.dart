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

    test('jumping into overlapping duet/backing vocal section prioritizes lead vocal line', () {
      final lines = [
        const LyricLine(text: '', startTimeMs: 0, endTimeMs: 4000),
        const LyricLine(text: 'Lead Line 1', startTimeMs: 4000, endTimeMs: 10000, isBackground: false),
        const LyricLine(text: 'Backing Echo', startTimeMs: 6000, endTimeMs: 9000, isBackground: true),
        const LyricLine(text: 'Lead Line 2', startTimeMs: 9500, endTimeMs: 14000, isBackground: false),
      ];

      // At 7000ms, both Lead Line 1 (4-10s) and Backing Echo (6-9s) are singing.
      // Lead line must take precedence.
      final idxAt7000 = LyricsService.computeActiveLyricIndex(7000, lines);
      expect(idxAt7000, equals(1)); // Lead Line 1

      // At 9800ms, Lead Line 2 has started while Backing Echo ended and Lead Line 1 is ending.
      // Lead Line 2 (newest) must be active.
      final idxAt9800 = LyricsService.computeActiveLyricIndex(9800, lines);
      expect(idxAt9800, equals(3)); // Lead Line 2
    });

    test('jumping into instrumental break or natural pause resolves closest section for scrolling', () {
      final lines = [
        const LyricLine(text: '', startTimeMs: 0, endTimeMs: 5000),
        const LyricLine(text: 'Verse 1', startTimeMs: 5000, endTimeMs: 10000),
        const LyricLine(text: '', startTimeMs: 10000, endTimeMs: 20000), // 10s guitar solo
        const LyricLine(text: 'Chorus', startTimeMs: 20000, endTimeMs: 28000),
      ];

      // Seeking to 15s (middle of guitar solo)
      final activeSolo = LyricsService.computeActiveLyricIndex(15000, lines);
      expect(activeSolo, equals(2)); // Instrumental dots gap

      // Closest line for scrolling at 15s targets the solo gap (index 2)
      final closestSolo = LyricsService.findClosestLineIndex(15000, lines);
      expect(closestSolo, equals(2));

      // Closest line for scrolling before song (at 2s) targets intro
      final closestIntro = LyricsService.findClosestLineIndex(2000, lines);
      expect(closestIntro, equals(0));
    });

    test('withInstrumentalGaps prevents duplicate gaps and handles missing endTimeMs cleanly', () {
      final rawLines = [
        const LyricLine(text: 'Line 1', startTimeMs: 5000), // No endTimeMs provided
        const LyricLine(text: 'Line 2', startTimeMs: 16000), // 11s gap from Line 1 start
      ];

      final processed = LyricsService.withInstrumentalGaps(rawLines);

      // Intro gap (0-5s) should be inserted
      expect(processed.first.text, equals(''));
      expect(processed.first.startTimeMs, equals(0));
      expect(processed.first.endTimeMs, equals(5000));

      // Line 1 should be present
      expect(processed[1].text, equals('Line 1'));

      // Instrumental gap between Line 1 (estimated 5s + 3.5s = 8.5s) and Line 2 (16s)
      expect(processed[2].text, equals(''));
      expect(processed[2].startTimeMs, equals(8500));
      expect(processed[2].endTimeMs, equals(16000));

      // Line 2 present
      expect(processed[3].text, equals('Line 2'));

      // Running withInstrumentalGaps again on already processed list should not duplicate gaps
      final reprocessed = LyricsService.withInstrumentalGaps(processed);
      expect(reprocessed.length, equals(processed.length));
    });
  });
}

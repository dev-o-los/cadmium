import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/models/lyric_line.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/providers/player_provider.dart';
import 'package:wavify/services/lyrics_service.dart';
import 'package:wavify/widgets/apple_lyrics_view.dart';
import 'package:wavify/widgets/track_options_sheet.dart';

void main() {
  group('LyricsService Unit Tests', () {
    test('cleanTrackTitle strips video, audio, and visualizer noise', () {
      expect(
        LyricsService.cleanTrackTitle('Blinding Lights (Official Music Video)'),
        'Blinding Lights',
      );
      expect(
        LyricsService.cleanTrackTitle('Levitating (feat. DaBaby)'),
        'Levitating',
      );
      expect(
        LyricsService.cleanTrackTitle('Stay [Official Audio]'),
        'Stay',
      );
      expect(
        LyricsService.cleanTrackTitle('Shape of You (Visualizer)'),
        'Shape of You',
      );
    });

    test('cleanArtistName extracts primary artist', () {
      expect(LyricsService.cleanArtistName('The Weeknd, Daft Punk'), 'The Weeknd');
      expect(LyricsService.cleanArtistName('Ed Sheeran & Justin Bieber'), 'Ed Sheeran');
      expect(LyricsService.cleanArtistName('Drake feat. 21 Savage'), 'Drake');
    });

    test('LyricSyllable progress calculation matches timeline', () {
      const syllable = LyricSyllable(
        text: 'Light ',
        startTimeMs: 1000,
        endTimeMs: 2000,
      );

      expect(syllable.getProgress(500), 0.0);
      expect(syllable.getProgress(1000), 0.0);
      expect(syllable.getProgress(1500), 0.5);
      expect(syllable.getProgress(2000), 1.0);
      expect(syllable.getProgress(2500), 1.0);
    });
  });

  group('AppleLyricsView Widget Tests', () {
    testWidgets('renders word-by-word synced syllables and attribution footer', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final testLyrics = [
        const LyricLine(
          text: 'I been tryna call',
          startTimeMs: 1000,
          endTimeMs: 3000,
          isWordSynced: true,
          syllables: [
            LyricSyllable(text: 'I ', startTimeMs: 1000, endTimeMs: 1300),
            LyricSyllable(text: 'been ', startTimeMs: 1300, endTimeMs: 1700),
            LyricSyllable(text: 'tryna ', startTimeMs: 1700, endTimeMs: 2200),
            LyricSyllable(text: 'call', startTimeMs: 2200, endTimeMs: 3000),
          ],
        ),
        const LyricLine(
          text: "(Can't you hear me?)",
          startTimeMs: 3100,
          endTimeMs: 4500,
          isBackground: true,
          isOppositeTurn: true,
        ),
      ];

      LyricLine? tappedLine;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: AppleLyricsView(
              lyrics: testLyrics,
              activeLyricIndex: 0,
              currentPositionMs: 1500, // Inside 'been '
              selectedProvider: LyricsProviderType.lrcRed,
              lyricsSource: 'Apple Music (via lrc.red)',
              lyricsSongwriters: 'Abel Tesfaye, Max Martin',
              onSeekToLyric: (line) {
                tappedLine = line;
              },
            ),
          ),
        ),
      );

      // Verify syllables rendered
      expect(find.text('I '), findsOneWidget);
      expect(find.text('tryna '), findsOneWidget);
      expect(find.text('call'), findsOneWidget);

      // Verify background vocal rendered
      expect(find.text("(Can't you hear me?)"), findsOneWidget);

      // Verify attribution footer
      expect(find.text('Lyrics provided by Apple Music (via lrc.red)'), findsOneWidget);
      expect(find.text('Written by Abel Tesfaye, Max Martin'), findsOneWidget);

      // Verify tap on second line triggers seek callback
      await tester.tap(find.text("(Can't you hear me?)"));
      await tester.pump();
      expect(tappedLine, isNotNull);
      expect(tappedLine!.text, "(Can't you hear me?)");
    });

    testWidgets('renders loading state cleanly with selected provider name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppleLyricsView(
              lyrics: const [],
              activeLyricIndex: -1,
              currentPositionMs: 0,
              isLoading: true,
              selectedProvider: LyricsProviderType.lrcRed,
              onSeekToLyric: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Connecting lrc.red lyrics...'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsWidgets);
    });

    testWidgets('renders empty state with quick switch action button', (tester) async {
      LyricsProviderType? switchedProvider;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppleLyricsView(
              lyrics: const [],
              activeLyricIndex: -1,
              currentPositionMs: 0,
              isLoading: false,
              selectedProvider: LyricsProviderType.lrcRed,
              onProviderChanged: (p) => switchedProvider = p,
              onSeekToLyric: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('No lyrics available right now'), findsOneWidget);
      expect(find.text('Switch to YouTube'), findsOneWidget);

      await tester.tap(find.text('Switch to YouTube'));
      await tester.pump();
      expect(switchedProvider, LyricsProviderType.youTube);
    });

    testWidgets('renders opening lyric line at top during instrumental music intro', (tester) async {
      final testLyrics = [
        const LyricLine(
          text: 'Hello from the other side',
          startTimeMs: 6000,
          endTimeMs: 9000,
          isWordSynced: true,
        ),
      ];

      LyricLine? soughtLine;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: AppleLyricsView(
              lyrics: testLyrics,
              activeLyricIndex: 0,
              currentPositionMs: 1500, // In intro: 1.5s < 6.0s
              isPlaying: true,
              selectedProvider: LyricsProviderType.lrcRed,
              onSeekToLyric: (line) {
                soughtLine = line;
              },
            ),
          ),
        ),
      );

      // Verify the opening line is rendered cleanly at top of lyrics without intro gap pushing it down
      expect(find.text('Hello from the other side'), findsOneWidget);

      // Verify tapping opening line seeks to it
      await tester.tap(find.text('Hello from the other side'));
      await tester.pump();
      expect(soughtLine, isNotNull);
      expect(soughtLine!.text, 'Hello from the other side');
      expect(soughtLine!.startTimeMs, 6000);
    });

    testWidgets('track options sheet renders lyrics provider switcher and allows switching', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const testSong = SongItem(
        id: 'test_song_123',
        title: 'Starboy',
        artist: 'The Weeknd',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return Consumer(
                    builder: (context, ref, _) {
                      return ElevatedButton(
                        onPressed: () => showTrackOptionsModal(context, ref, testSong),
                        child: const Text('Open Menu'),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

      // Open the track options 3-dots sheet
      await tester.tap(find.text('Open Menu'));
      await tester.pumpAndSettle();

      // Verify Lyrics Provider title and toggle buttons are present
      expect(find.text('Lyrics Provider'), findsOneWidget);
      expect(find.text('lrc.red'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);

      // Default provider is lrcRed
      expect(container.read(playerProvider).selectedLyricsProvider, LyricsProviderType.lrcRed);

      // Tap YouTube in the options sheet
      await tester.tap(find.text('YouTube'));
      await tester.pumpAndSettle();

      // Verify provider updated in state
      expect(container.read(playerProvider).selectedLyricsProvider, LyricsProviderType.youTube);
    });
  });
}

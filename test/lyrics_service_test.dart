import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/models/lyric_line.dart';
import 'package:wavify/services/lyrics_service.dart';
import 'package:wavify/widgets/apple_lyrics_view.dart';

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
    testWidgets('renders word-by-word synced syllables and provider toggle', (tester) async {
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
      LyricsProviderType? switchedProvider;

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
              onProviderChanged: (p) => switchedProvider = p,
              onSeekToLyric: (line) {
                tappedLine = line;
              },
            ),
          ),
        ),
      );

      // Verify provider toggle pills are rendered
      expect(find.text('lrc.red'), findsWidgets);
      expect(find.text('YouTube'), findsWidgets);

      // Verify syllables rendered
      expect(find.text('I '), findsOneWidget);
      expect(find.text('tryna '), findsOneWidget);
      expect(find.text('call'), findsOneWidget);

      // Verify background vocal rendered
      expect(find.text("(Can't you hear me?)"), findsOneWidget);

      // Verify attribution footer
      expect(find.text('Lyrics provided by Apple Music (via lrc.red)'), findsOneWidget);
      expect(find.text('Written by Abel Tesfaye, Max Martin'), findsOneWidget);

      // Verify tap on YouTube capsule triggers onProviderChanged
      await tester.tap(find.text('YouTube').first);
      await tester.pump();
      expect(switchedProvider, LyricsProviderType.youTube);

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
  });
}

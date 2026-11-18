import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/models/lyric_line.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/services/lyrics_service.dart';
import 'package:wavify/widgets/apple_lyrics_view.dart';
import 'package:wavify/widgets/apple_pressable.dart';
import 'package:wavify/widgets/track_options_sheet.dart';

void main() {
  group('All 13 Lyrics Providers Metadata & Parsing Tests', () {
    test('all 13 requested providers are defined with display names and attribution', () {
      final providers = LyricsProviderType.values;
      expect(providers.length, equals(13));

      final expectedNames = [
        'lrc.red',
        'YouTube',
        'BiniLyrics',
        'BetterLyrics',
        'PaxSenix',
        'LyricsPlus',
        'SimpMusic',
        'Unison',
        'Megalobiz',
        'KuGou',
        'LRCLIB',
        'Musixmatch',
        'Genius',
      ];

      for (final p in providers) {
        expect(expectedNames.contains(p.displayName), isTrue,
            reason: 'Unexpected or missing displayName for $p');
        expect(p.attributionName, isNotEmpty);
        expect(p.creditUrl, isNotEmpty);
        expect(p.formatDescription, isNotEmpty);
      }
    });

    test('parseLrc parses standard LRC strings into timed LyricLines', () {
      const lrcContent = '''
[ti:Yellow]
[ar:Coldplay]
[al:Parachutes]
[00:35.66]Look at the stars
[00:38.46]Look how they shine for you
[00:44.17]And everything you do
[00:49.66](Yeah, they were all yellow)
''';

      final res = LyricsService.parseLrc(
        lrcContent,
        provider: LyricsProviderType.lrcLib,
        songwriters: 'Guy Berryman, Chris Martin',
      );

      expect(res.lines.length, equals(4));
      expect(res.provider, equals(LyricsProviderType.lrcLib));
      expect(res.source, equals(LyricsProviderType.lrcLib.attributionName));
      expect(res.songwriters, equals('Guy Berryman, Chris Martin'));

      expect(res.lines[0].text, equals('Look at the stars'));
      expect(res.lines[0].startTimeMs, equals(35660));
      expect(res.lines[0].endTimeMs, equals(38460));
      expect(res.lines[0].isBackground, isFalse);

      expect(res.lines[3].text, equals('(Yeah, they were all yellow)'));
      expect(res.lines[3].isBackground, isTrue);
    });

    test('parseSyllableJson parses LyricsPlus syllable timeline with word sync', () {
      final syllableJson = {
        'type': 'syllable',
        'metadata': {
          'songWriters': ['Chris Martin', 'Guy Berryman'],
        },
        'lyrics': [
          {'time': 33640, 'duration': 320, 'text': 'Look ', 'isLineEnding': 0},
          {'time': 33960, 'duration': 320, 'text': 'at ', 'isLineEnding': 0},
          {'time': 34280, 'duration': 400, 'text': 'the ', 'isLineEnding': 0},
          {'time': 34680, 'duration': 900, 'text': 'stars', 'isLineEnding': 1},
          {'time': 38000, 'duration': 500, 'text': 'Shine ', 'isLineEnding': 1},
        ],
      };

      final res = LyricsService.parseSyllableJson(
        syllableJson,
        provider: LyricsProviderType.lyricsPlus,
      );

      expect(res.lines.length, equals(2));
      expect(res.hasWordSync, isTrue);
      expect(res.provider, equals(LyricsProviderType.lyricsPlus));
      expect(res.songwriters, equals('Chris Martin, Guy Berryman'));

      expect(res.lines[0].text, equals('Look at the stars'));
      expect(res.lines[0].startTimeMs, equals(33640));
      expect(res.lines[0].endTimeMs, equals(35580));
      expect(res.lines[0].syllables.length, equals(4));
      expect(res.lines[0].isWordSynced, isTrue);
    });

    test('LyricsService in-memory caching stores and retrieves provider results', () {
      final service = LyricsService();
      addTearDown(service.dispose);

      const trackKey = 'yellow::coldplay';
      const resultA = LyricsResult(
        lines: [LyricLine(text: 'Line A', startTimeMs: 1000)],
        source: 'LRCLIB',
        provider: LyricsProviderType.lrcLib,
      );
      const resultB = LyricsResult(
        lines: [LyricLine(text: 'Line B', startTimeMs: 2000)],
        source: 'KuGou',
        provider: LyricsProviderType.kuGou,
      );

      service.cacheLyrics(trackKey, LyricsProviderType.lrcLib, resultA);
      service.cacheLyrics(trackKey, LyricsProviderType.kuGou, resultB);

      expect(service.getCachedLyrics(trackKey, LyricsProviderType.lrcLib), equals(resultA));
      expect(service.getCachedLyrics(trackKey, LyricsProviderType.kuGou), equals(resultB));
      expect(service.getCachedLyrics(trackKey, LyricsProviderType.genius), isNull);

      final available = service.getAvailableProviders(trackKey);
      expect(available.contains(LyricsProviderType.lrcLib), isTrue);
      expect(available.contains(LyricsProviderType.kuGou), isTrue);
      expect(available.contains(LyricsProviderType.genius), isFalse);
    });
  });

  group('Player Screen & Track Options All Sources UI Tests', () {
    testWidgets('TrackOptionsSheet does not contain lyrics provider and AppleLyricsView opens sources sheet on tapping Lyrics by provider', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      const testSong = SongItem(
        id: 'test_song_1',
        title: 'Fix You',
        artist: 'Coldplay',
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
                        child: const Text('Open Modal'),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Check "Lyrics Provider" header and "All (13)" shortcut are removed from 3-dots sheet
      expect(find.text('Lyrics Provider'), findsNothing);
      expect(find.text('All (13)'), findsNothing);

      // Now test AppleLyricsView: tapping "Lyrics by lrc.red" opens sources sheet
      LyricsProviderType? switchedProvider;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppleLyricsView(
              lyrics: const [
                LyricLine(text: 'Lights will guide you home', startTimeMs: 1000, endTimeMs: 3000),
              ],
              activeLyricIndex: 0,
              currentPositionMs: 1500,
              isPlaying: false,
              selectedProvider: LyricsProviderType.lrcRed,
              onProviderChanged: (p) => switchedProvider = p,
              onSeekToLyric: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify "Lyrics by lrc.red" is displayed
      expect(find.text('Lyrics by lrc.red'), findsWidgets);

      // Tap on the top "Lyrics by lrc.red"
      await tester.tap(find.text('Lyrics by lrc.red').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify all sources modal sheet opened
      expect(find.text('Lyrics Sources'), findsOneWidget);
      expect(find.text('BetterLyrics'), findsWidgets);

      // Tap on BetterLyrics in the modal sheet
      final betterLyricsTile = find.widgetWithText(ApplePressable, 'BetterLyrics').last;
      expect(betterLyricsTile, findsOneWidget);
      await tester.tap(betterLyricsTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify switched provider
      expect(switchedProvider, LyricsProviderType.betterLyrics);
    });

    testWidgets('AppleLyricsView empty state shows all sources and allows switching', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      LyricsProviderType? switched;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppleLyricsView(
              lyrics: const [],
              activeLyricIndex: -1,
              currentPositionMs: 0,
              isPlaying: false,
              selectedProvider: LyricsProviderType.betterLyrics,
              availableProviders: const [
                LyricsProviderType.betterLyrics,
                LyricsProviderType.lrcLib,
                LyricsProviderType.kuGou,
              ],
              onProviderChanged: (p) => switched = p,
              onSeekToLyric: (_) {},
            ),
          ),
        ),
      );

      // Check empty state headline and sources button
      expect(find.text('No lyrics available right now'), findsOneWidget);
      expect(find.text('View All 13 Sources'), findsOneWidget);

      // Tap on View All 13 Sources button to open sources sheet
      await tester.tap(find.text('View All 13 Sources'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Lyrics Sources'), findsOneWidget);

      final biniTile = find.widgetWithText(ApplePressable, 'BiniLyrics').last;
      expect(biniTile, findsOneWidget);

      // Tap BiniLyrics in sources sheet
      await tester.tap(biniTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(switched, equals(LyricsProviderType.biniLyrics));
    });
  });
}

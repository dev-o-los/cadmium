import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/services/lyrics_service.dart';

void main() {
  group('TTML and lrc.red parser tests', () {
    test('ttmlTime parses clock formats correctly', () {
      expect(LyricsService.ttmlTimeToMs('27.395'), 27395);
      expect(LyricsService.ttmlTimeToMs('1:05.20'), 65200);
      expect(LyricsService.ttmlTimeToMs('1:02:03.4'), 3723400);
      expect(LyricsService.ttmlTimeToMs('500ms'), 500);
      expect(LyricsService.ttmlTimeToMs('30s'), 30000);
      expect(LyricsService.ttmlTimeToMs(null), isNull);
      expect(LyricsService.ttmlTimeToMs(''), isNull);
    });

    test('parseTtml parses Apple Music syllables, words, and background vocals', () {
      const appleTtml = '''<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
<head><metadata><ttm:agent type="person" xml:id="v1"/><ttm:agent type="person" xml:id="v2"/></metadata></head>
<body><div>
<p begin="27.395" end="29.0" ttm:agent="v1"><span begin="27.395" end="27.549">I</span> <span begin="27.549" end="27.740">been</span> <span begin="27.8" end="28.0">e</span><span begin="28.0" end="28.6">nough</span><span ttm:role="x-bg"><span begin="28.6" end="29.0">(ooh)</span></span></p>
<p begin="31.0" end="32.0" ttm:agent="v2"><span begin="31.0" end="32.0">Hey</span></p>
</div></body></tt>''';

      final result = LyricsService.parseTtml(appleTtml);
      expect(result.lines.length, greaterThanOrEqualTo(2));

      // First line is right at the top ready for vocal delivery
      final firstLine = result.lines.first;
      expect(firstLine.text, contains('I been enough'));
      expect(firstLine.isWordSynced, isTrue);
      expect(firstLine.syllables.isNotEmpty, isTrue);
      expect(firstLine.isOppositeTurn, isFalse);

      // Check syllable decomposition of "enough" ("e" + "nough")
      final syllables = firstLine.syllables;
      final eSyl = syllables.firstWhere((s) => s.text.trim() == 'e');
      expect(eSyl.startTimeMs, 27800);
      expect(eSyl.endTimeMs, 28000);
      expect(eSyl.isPartOfWord, isTrue);

      final noughSyl = syllables.firstWhere((s) => s.text.trim() == 'nough');
      expect(noughSyl.startTimeMs, 28000);
      expect(noughSyl.endTimeMs, 28600);
      expect(noughSyl.isPartOfWord, isFalse);

      // Background vocal check
      final bgLine = result.lines.firstWhere((l) => l.isBackground, orElse: () => result.lines[0]);
      expect(bgLine.text, contains('(ooh)'));

      // Second line with agent v2 is opposite duet turn
      final secondLine = result.lines.firstWhere((l) => l.text.trim() == 'Hey');
      expect(secondLine.isOppositeTurn, isTrue);
    });

    test('bestLrcRedHit picks the closest matching hit by title, version, and duration', () {
      final hits = [
        LrcRedHit(
          isrc: 'GBBKS1500214',
          title: 'Hello',
          artist: 'Adele',
          duration: 295.5,
        ),
        LrcRedHit(
          isrc: 'BXCSI1900002',
          title: 'Hello (Live)',
          artist: 'Hello Adele Tribute',
          duration: 294.1,
        ),
        LrcRedHit(
          isrc: 'AEA2L2658148',
          title: 'HELLO',
          artist: 'Adele',
          duration: 153.7,
        ),
      ];

      final best = LyricsService.bestLrcRedHit(
        hits: hits,
        title: 'Hello',
        artist: 'Adele',
        durationMs: 295000,
      );

      expect(best, isNotNull);
      expect(best!.isrc, 'GBBKS1500214');
    });

    test('bestLrcRedHit avoids live versions if main song is not live', () {
      final hits = [
        LrcRedHit(
          isrc: 'BXCSI1900002',
          title: 'Hello (Live)',
          artist: 'Adele',
          duration: 295.0,
        ),
        LrcRedHit(
          isrc: 'GBBKS1500214',
          title: 'Hello',
          artist: 'Adele',
          duration: 296.0,
        ),
      ];

      final best = LyricsService.bestLrcRedHit(
        hits: hits,
        title: 'Hello',
        artist: 'Adele',
        durationMs: 295500,
      );

      expect(best, isNotNull);
      expect(best!.isrc, 'GBBKS1500214');
    });
  });
}


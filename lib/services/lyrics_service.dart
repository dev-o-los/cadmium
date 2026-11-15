import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:xml/xml.dart';
import '../models/lyric_line.dart';

/// Supported lyrics providers in Wavify.
enum LyricsProviderType {
  lrcRed,
  youTube,
  biniLyrics,
  betterLyrics,
  paxSenix,
  lyricsPlus,
  simpMusic,
  unison,
  megalobiz,
  kuGou,
  lrcLib,
  musixmatch,
  genius,
}

extension LyricsProviderTypeExt on LyricsProviderType {
  String get displayName {
    switch (this) {
      case LyricsProviderType.lrcRed:
        return 'lrc.red';
      case LyricsProviderType.biniLyrics:
        return 'BiniLyrics';
      case LyricsProviderType.betterLyrics:
        return 'BetterLyrics';
      case LyricsProviderType.paxSenix:
        return 'PaxSenix';
      case LyricsProviderType.lyricsPlus:
        return 'LyricsPlus';
      case LyricsProviderType.simpMusic:
        return 'SimpMusic';
      case LyricsProviderType.unison:
        return 'Unison';
      case LyricsProviderType.megalobiz:
        return 'Megalobiz';
      case LyricsProviderType.kuGou:
        return 'KuGou';
      case LyricsProviderType.lrcLib:
        return 'LRCLIB';
      case LyricsProviderType.musixmatch:
        return 'Musixmatch';
      case LyricsProviderType.genius:
        return 'Genius';
      case LyricsProviderType.youTube:
        return 'YouTube';
    }
  }

  String get attributionName {
    switch (this) {
      case LyricsProviderType.lrcRed:
        return 'Apple Music (via lrc.red)';
      case LyricsProviderType.biniLyrics:
        return 'BiniLyrics (binimum)';
      case LyricsProviderType.betterLyrics:
        return 'BetterLyrics';
      case LyricsProviderType.paxSenix:
        return 'PaxSenix';
      case LyricsProviderType.lyricsPlus:
        return 'LyricsPlus (YouLy+)';
      case LyricsProviderType.simpMusic:
        return 'SimpMusic';
      case LyricsProviderType.unison:
        return 'Unison (BetterLyrics)';
      case LyricsProviderType.megalobiz:
        return 'Megalobiz';
      case LyricsProviderType.kuGou:
        return 'KuGou (酷狗音乐)';
      case LyricsProviderType.lrcLib:
        return 'LRCLIB';
      case LyricsProviderType.musixmatch:
        return 'Musixmatch';
      case LyricsProviderType.genius:
        return 'Genius';
      case LyricsProviderType.youTube:
        return 'YouTube Music';
    }
  }

  String get creditUrl {
    switch (this) {
      case LyricsProviderType.lrcRed:
        return 'https://lrc.red/';
      case LyricsProviderType.biniLyrics:
        return 'https://github.com/binimum';
      case LyricsProviderType.betterLyrics:
        return 'https://github.com/better-lyrics/better-lyrics';
      case LyricsProviderType.paxSenix:
        return 'https://lyrics.paxsenix.org/';
      case LyricsProviderType.lyricsPlus:
        return 'https://github.com/ibratabian17/YouLyPlus';
      case LyricsProviderType.simpMusic:
        return 'https://github.com/maxrave-dev/SimpMusic';
      case LyricsProviderType.unison:
        return 'https://unison.boidu.dev/';
      case LyricsProviderType.megalobiz:
        return 'https://www.megalobiz.com/';
      case LyricsProviderType.kuGou:
        return 'https://www.kugou.com/';
      case LyricsProviderType.lrcLib:
        return 'https://lrclib.net/';
      case LyricsProviderType.musixmatch:
        return 'https://www.musixmatch.com/';
      case LyricsProviderType.genius:
        return 'https://genius.com/';
      case LyricsProviderType.youTube:
        return 'https://music.youtube.com/';
    }
  }

  String get formatDescription {
    switch (this) {
      case LyricsProviderType.lrcRed:
      case LyricsProviderType.biniLyrics:
      case LyricsProviderType.betterLyrics:
      case LyricsProviderType.unison:
        return 'TTML • Word-by-Word';
      case LyricsProviderType.lyricsPlus:
        return 'Syllables • Word-by-Word';
      case LyricsProviderType.kuGou:
      case LyricsProviderType.lrcLib:
      case LyricsProviderType.megalobiz:
      case LyricsProviderType.musixmatch:
        return 'LRC • Line Synced';
      case LyricsProviderType.genius:
        return 'Full Text • Plain';
      case LyricsProviderType.paxSenix:
      case LyricsProviderType.simpMusic:
      case LyricsProviderType.youTube:
        return 'Timed Lyrics';
    }
  }
}

/// A hit returned by the lrc.red search endpoint.
class LrcRedHit {
  final String? isrc;
  final String? title;
  final String? artist;
  final double? duration;

  const LrcRedHit({
    this.isrc,
    this.title,
    this.artist,
    this.duration,
  });

  factory LrcRedHit.fromJson(Map<String, dynamic> json) {
    return LrcRedHit(
      isrc: json['isrc'] as String?,
      title: json['title'] as String?,
      artist: json['artist'] as String?,
      duration: (json['duration'] as num?)?.toDouble(),
    );
  }
}

/// Result object holding parsed lyrics, provider source attribution, and metadata.
class LyricsResult {
  final List<LyricLine> lines;
  final String source;
  final String? songwriters;
  final bool hasWordSync;
  final LyricsProviderType provider;

  const LyricsResult({
    required this.lines,
    required this.source,
    this.songwriters,
    this.hasWordSync = false,
    this.provider = LyricsProviderType.lrcRed,
  });

  static const empty = LyricsResult(
    lines: [],
    source: 'None',
    hasWordSync: false,
    provider: LyricsProviderType.lrcRed,
  );
}

/// Helper model for TTML syllable parsing.
class _TtmlPiece {
  final String text;
  final bool isTimed;
  final int startMs;
  final int endMs;

  const _TtmlPiece({
    required this.text,
    required this.isTimed,
    this.startMs = 0,
    this.endMs = 0,
  });
}

class _TtmlWord {
  final int startMs;
  final int endMs;
  final String text;
  final List<LyricSyllable> syllables;

  const _TtmlWord({
    required this.startMs,
    required this.endMs,
    required this.text,
    required this.syllables,
  });
}

/// Universal Lyrics Service supporting:
/// - lrc.red (Apple Music TTML / Word-Synced)
/// - BiniLyrics (binimum)
/// - BetterLyrics (TTML)
/// - PaxSenix
/// - LyricsPlus (YouLy+ syllable synced)
/// - SimpMusic
/// - Unison (TTML / LRC)
/// - Megalobiz (LRC)
/// - KuGou (酷狗音乐 LRC)
/// - LRCLIB (LRC / Plain)
/// - Musixmatch (LRC subtitles)
/// - Genius (Full text)
/// - YouTube Music
class LyricsService {
  final HttpClient _httpClient;
  // Multi-provider memory cache: trackKey -> (provider -> LyricsResult)
  final Map<String, Map<LyricsProviderType, LyricsResult>> _lyricsMemoryCache = {};

  LyricsService({HttpClient? httpClient})
      : _httpClient = httpClient ?? (HttpClient()..connectionTimeout = const Duration(seconds: 4));

  static const String lrcRedBaseUrl = 'https://lrc.red';
  static final RegExp _isrcRegex = RegExp(r'^[A-Z]{2}[A-Z0-9]{3}\d{7}$', caseSensitive: false);
  static final RegExp _bracketedRegex = RegExp(r'[\(\[][^\)\]]*[\)\]]');
  static final RegExp _artistSeparators = RegExp(
    r'\s*(?:,|&|;|\/|\s+and\s+|\s+x\s+|\s+with\s+|\s+feat\.?\s+|\s+ft\.?\s+)\s*',
    caseSensitive: false,
  );
  static final RegExp _nonAlphaNum = RegExp(r'[^a-zA-Z0-9\s]');
  static final RegExp _multiSpace = RegExp(r'\s+');

  static const Set<String> _versionWords = {
    'live', 'remix', 'remixed', 'mix', 'acoustic', 'unplugged', 'instrumental',
    'karaoke', 'cappella', 'acapella', 'demo', 'edit', 'version', 'cover',
    'sped', 'slowed', 'reverb', 'nightcore', 'lofi', 'orchestral', 'extended',
  };

  /// Cleans track title by stripping visualizer, official video, and featured artist tags.
  static String cleanTrackTitle(String rawTitle) {
    var title = rawTitle;
    title = title.replaceAll(
      RegExp(r'\s*[\(\[](?:official\s*)?(?:music\s*)?(?:video|audio|visualizer|lyric\s*video|official|hd|4k)[\)\]]',
          caseSensitive: false),
      '',
    );
    title = title.replaceAll(
      RegExp(r'\s*[\(\[](?:feat|ft)\.?\s+[^\)\]]+[\)\]]', caseSensitive: false),
      '',
    );
    return title.trim();
  }

  /// Cleans artist name by extracting the primary artist name.
  static String cleanArtistName(String rawArtist) {
    final parts = rawArtist.split(_artistSeparators);
    return parts.first.trim();
  }

  static String _stripDiacritics(String text) {
    const withDia = 'ÀÁÂÃÄÅàáâãäåÒÓÔÕÖØòóôõöøÈÉÊËèéêëÌÍÎÏìíîïÙÚÛÜùúûüÑñÇçÿýÝ';
    const withoutDia = 'AAAAAAaaaaaaOOOOOOooooooEEEEeeeeIIIIiiiiUUUUuuuuNnCcyyY';
    var result = text;
    for (int i = 0; i < withDia.length; i++) {
      result = result.replaceAll(withDia[i], withoutDia[i]);
    }
    return result;
  }

  /// Lower case, accents off, letters and digits only.
  static String normalize(String value) {
    final stripped = _stripDiacritics(value).toLowerCase();
    return stripped.replaceAll(_nonAlphaNum, ' ').replaceAll(_multiSpace, ' ').trim();
  }

  static String coreOf(String title) {
    final withoutBrackets = title.replaceAll(_bracketedRegex, ' ');
    final beforeDash = withoutBrackets.split(' - ').first;
    final norm = normalize(beforeDash);
    return norm.isNotEmpty ? norm : normalize(title);
  }

  static Set<String> versionOf(String title) {
    final bracketMatches = _bracketedRegex.allMatches(title).map((m) => m.group(0)!).join(' ');
    final dashSuffix = title.contains(' - ') ? title.substring(title.indexOf(' - ') + 3) : '';
    final words = normalize('$bracketMatches $dashSuffix').split(' ');
    return words.where((w) => _versionWords.contains(w)).toSet();
  }

  static Set<String> artistsOf(String artist) {
    return artist
        .split(_artistSeparators)
        .map(normalize)
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  static bool _sameSet(Set<String> a, Set<String> b) {
    return a.length == b.length && a.every((element) => b.contains(element));
  }

  static bool isValidIsrc(String? isrc) {
    if (isrc == null) return false;
    return _isrcRegex.hasMatch(isrc.trim());
  }

  /// Ported from lrc.red / web bestLrcRedHit:
  /// Evaluates title core, version tags, artist matches, and duration within 3s.
  static LrcRedHit? bestLrcRedHit({
    required List<LrcRedHit> hits,
    required String title,
    required String artist,
    required int durationMs,
  }) {
    final wantedTitle = coreOf(title);
    final wantedVersion = versionOf(title);
    final wantedArtists = artistsOf(artist);
    final secs = durationMs / 1000.0;

    double distance(LrcRedHit hit) {
      if (durationMs > 0 && hit.duration != null) {
        return (hit.duration! - secs).abs();
      }
      return 0.0;
    }

    final passing = hits.where((hit) {
      if (hit.title == null || !isValidIsrc(hit.isrc)) return false;
      if (coreOf(hit.title!) != wantedTitle) return false;
      if (!_sameSet(versionOf(hit.title!), wantedVersion)) return false;
      if (wantedArtists.isNotEmpty) {
        final hitArtists = artistsOf(hit.artist ?? '');
        if (!hitArtists.any((a) => wantedArtists.contains(a))) return false;
      }
      if (durationMs > 0 && distance(hit) > 3.0) return false;
      return true;
    }).toList();

    if (passing.isEmpty) return null;
    passing.sort((a, b) => distance(a).compareTo(distance(b)));
    return passing.first;
  }

  /// TTML clock values: 27.395, 1:05.20, 1:02:03.4, or a number with s/ms.
  static int? ttmlTimeToMs(String? value) {
    if (value == null) return null;
    final raw = value.trim();
    if (raw.isEmpty) return null;
    if (raw.endsWith('ms')) {
      final ms = double.tryParse(raw.substring(0, raw.length - 2));
      return ms?.round();
    }
    final stripped = raw.endsWith('s') ? raw.substring(0, raw.length - 1) : raw;
    final parts = stripped.split(':');
    if (parts.length > 3) return null;

    double totalSeconds = 0;
    for (final part in parts) {
      final numVal = double.tryParse(part);
      if (numVal == null) return null;
      totalSeconds = totalSeconds * 60 + numVal;
    }
    return (totalSeconds * 1000).round();
  }

  // =========================================================================
  // PARSERS: TTML, LRC, and SYLLABLE JSON
  // =========================================================================

  /// Parses a TTML XML string (lrc.red, BetterLyrics, BiniLyrics, Unison) into structured LyricLines.
  static LyricsResult parseTtml(
    String ttmlContent, {
    LyricsProviderType provider = LyricsProviderType.lrcRed,
  }) {
    try {
      final document = XmlDocument.parse(ttmlContent);

      // Extract songwriters from <sourceMetadata><songwriters><songwriter>
      final songwritersList = <String>[];
      for (final sw in document.findAllElements('songwriter')) {
        final name = sw.innerText.trim();
        if (name.isNotEmpty && !songwritersList.contains(name)) {
          songwritersList.add(name);
        }
      }
      final songwriters = songwritersList.isNotEmpty ? songwritersList.join(', ') : null;

      final parsedLines = <LyricLine>[];
      bool anyWordSync = false;

      final paragraphs = document.findAllElements('p').toList();

      for (final p in paragraphs) {
        final pBegin = ttmlTimeToMs(p.getAttribute('begin'));
        final pEnd = ttmlTimeToMs(p.getAttribute('end'));
        final agent = p.getAttribute('ttm:agent') ?? p.getAttribute('agent');
        final isOpposite = agent != null && agent.toLowerCase() != 'v1' && agent.toLowerCase() != 'a';

        final leadPieces = <_TtmlPiece>[];
        final backingPieces = <_TtmlPiece>[];
        _collectPieces(p, leadPieces, backingPieces);

        final leadWords = _mergeIntoWords(leadPieces);
        final backingWords = _mergeIntoWords(backingPieces);

        if (leadWords.isNotEmpty) {
          anyWordSync = true;
          final leadSyllables = <LyricSyllable>[];
          for (int wIdx = 0; wIdx < leadWords.length; wIdx++) {
            final w = leadWords[wIdx];
            final isLastWord = wIdx == leadWords.length - 1;

            if (w.syllables.isEmpty) {
              leadSyllables.add(LyricSyllable(
                text: isLastWord ? w.text : '${w.text} ',
                startTimeMs: w.startMs,
                endTimeMs: w.endMs,
                isPartOfWord: false,
              ));
            } else {
              for (int sIdx = 0; sIdx < w.syllables.length; sIdx++) {
                final s = w.syllables[sIdx];
                final isLastSyl = sIdx == w.syllables.length - 1;
                final space = (isLastSyl && !isLastWord) ? ' ' : '';
                leadSyllables.add(LyricSyllable(
                  text: '${s.text}$space',
                  startTimeMs: s.startTimeMs,
                  endTimeMs: s.endTimeMs,
                  isPartOfWord: !isLastSyl,
                ));
              }
            }
          }

          final lineStart = pBegin ?? (leadWords.isNotEmpty ? leadWords.first.startMs : 0);
          final lineEnd = pEnd ?? (leadWords.isNotEmpty ? leadWords.last.endMs : lineStart + 3500);

          parsedLines.add(LyricLine(
            text: leadWords.map((w) => w.text).join(' '),
            startTimeMs: math.min(lineStart, leadWords.first.startMs),
            endTimeMs: math.max(lineEnd, leadWords.last.endMs),
            syllables: leadSyllables,
            isWordSynced: leadSyllables.isNotEmpty,
            isBackground: false,
            isOppositeTurn: isOpposite,
            singer: agent,
          ));
        } else {
          // Line without timed span children (line-timed or untimed)
          final text = p.innerText.trim();
          if (text.isNotEmpty) {
            final lineStart = pBegin ?? 0;
            final lineEnd = pEnd ?? (lineStart + 3500);
            parsedLines.add(LyricLine(
              text: text,
              startTimeMs: lineStart,
              endTimeMs: lineEnd,
              syllables: const [],
              isWordSynced: false,
              isBackground: text.startsWith('(') && text.endsWith(')'),
              isOppositeTurn: isOpposite,
              singer: agent,
            ));
          }
        }

        // Add backing vocals if separate
        if (backingWords.isNotEmpty) {
          final backingSyllables = <LyricSyllable>[];
          for (int wIdx = 0; wIdx < backingWords.length; wIdx++) {
            final w = backingWords[wIdx];
            final isLastWord = wIdx == backingWords.length - 1;

            if (w.syllables.isEmpty) {
              backingSyllables.add(LyricSyllable(
                text: isLastWord ? w.text : '${w.text} ',
                startTimeMs: w.startMs,
                endTimeMs: w.endMs,
                isPartOfWord: false,
              ));
            } else {
              for (int sIdx = 0; sIdx < w.syllables.length; sIdx++) {
                final s = w.syllables[sIdx];
                final isLastSyl = sIdx == w.syllables.length - 1;
                final space = (isLastSyl && !isLastWord) ? ' ' : '';
                backingSyllables.add(LyricSyllable(
                  text: '${s.text}$space',
                  startTimeMs: s.startTimeMs,
                  endTimeMs: s.endTimeMs,
                  isPartOfWord: !isLastSyl,
                ));
              }
            }
          }

          final bgText = backingWords.map((w) => w.text).join(' ');
          parsedLines.add(LyricLine(
            text: bgText.startsWith('(') ? bgText : '($bgText)',
            startTimeMs: backingWords.first.startMs,
            endTimeMs: backingWords.last.endMs,
            syllables: backingSyllables,
            isWordSynced: backingSyllables.isNotEmpty,
            isBackground: true,
            isOppositeTurn: isOpposite,
            singer: agent,
          ));
        }
      }

      parsedLines.sort((a, b) => (a.startTimeMs ?? 0).compareTo(b.startTimeMs ?? 0));
      final linesWithGaps = withInstrumentalGaps(parsedLines);

      return LyricsResult(
        lines: linesWithGaps,
        source: provider.attributionName,
        songwriters: songwriters,
        hasWordSync: anyWordSync,
        provider: provider,
      );
    } catch (e) {
      debugPrint('[LyricsService] Error parsing TTML: $e');
      return LyricsResult.empty;
    }
  }

  /// Parses standard LRC content ([mm:ss.xx] / [mm:ss.xxx]) into sorted LyricLines.
  static LyricsResult parseLrc(
    String lrcContent, {
    required LyricsProviderType provider,
    String? songwriters,
  }) {
    try {
      final lines = <LyricLine>[];
      final timeTagRegex = RegExp(r'\[(\d{1,2}):(\d{2})(?:\.(\d{1,3}))?\]');
      final rawLines = lrcContent.split('\n');

      for (final raw in rawLines) {
        final trimmed = raw.trim();
        if (trimmed.isEmpty) continue;
        // Skip metadata tags like [ar: ], [ti: ], [al: ], [by: ], [offset: ]
        if (RegExp(r'^\[[a-zA-Z_]+:').hasMatch(trimmed)) continue;

        final matches = timeTagRegex.allMatches(trimmed).toList();
        if (matches.isEmpty) continue;

        final text = trimmed.replaceAll(timeTagRegex, '').trim();
        if (text.isEmpty) continue;

        final isBg = (text.startsWith('(') && text.endsWith(')')) ||
                     (text.startsWith('[') && text.endsWith(']'));

        for (final match in matches) {
          final min = int.tryParse(match.group(1) ?? '0') ?? 0;
          final sec = int.tryParse(match.group(2) ?? '0') ?? 0;
          final fracStr = match.group(3) ?? '0';
          int ms = 0;
          if (fracStr.length == 1) {
            ms = (int.tryParse(fracStr) ?? 0) * 100;
          } else if (fracStr.length == 2) {
            ms = (int.tryParse(fracStr) ?? 0) * 10;
          } else {
            ms = int.tryParse(fracStr) ?? 0;
          }
          final totalMs = min * 60000 + sec * 1000 + ms;

          lines.add(LyricLine(
            text: text,
            startTimeMs: totalMs,
            isBackground: isBg,
            isWordSynced: false,
          ));
        }
      }

      if (lines.isEmpty) return LyricsResult.empty;
      lines.sort((a, b) => (a.startTimeMs ?? 0).compareTo(b.startTimeMs ?? 0));

      // Calculate endTimeMs for each line based on start of next line
      for (int i = 0; i < lines.length; i++) {
        final current = lines[i];
        final next = i < lines.length - 1 ? lines[i + 1] : null;
        final start = current.startTimeMs ?? 0;
        final nextStart = next?.startTimeMs;
        final end = (nextStart != null && nextStart > start)
            ? math.min(start + 7000, nextStart)
            : start + 3500;
        lines[i] = current.copyWith(endTimeMs: end);
      }

      final filtered = withInstrumentalGaps(lines);
      return LyricsResult(
        lines: filtered,
        source: provider.attributionName,
        songwriters: songwriters,
        hasWordSync: false,
        provider: provider,
      );
    } catch (e) {
      debugPrint('[LyricsService] Error parsing LRC: $e');
      return LyricsResult.empty;
    }
  }

  /// Parses Syllable JSON formatted lyrics (LyricsPlus / YouLy+).
  static LyricsResult parseSyllableJson(
    Map<String, dynamic> json, {
    required LyricsProviderType provider,
  }) {
    try {
      final lyricsList = json['lyrics'] as List<dynamic>?;
      if (lyricsList == null || lyricsList.isEmpty) return LyricsResult.empty;

      final metadata = json['metadata'] as Map<String, dynamic>?;
      final songwritersList = (metadata?['songWriters'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList();
      final songwriters = songwritersList?.isNotEmpty == true ? songwritersList!.join(', ') : null;

      final lines = <LyricLine>[];
      final currentSyllables = <LyricSyllable>[];
      String currentLineText = '';

      for (final item in lyricsList) {
        if (item is! Map<String, dynamic>) continue;
        final text = item['text']?.toString() ?? '';
        final time = (item['time'] as num?)?.toInt() ?? 0;
        final duration = (item['duration'] as num?)?.toInt() ?? 0;
        final isLineEnding = item['isLineEnding'] == 1 || item['isLineEnding'] == true;
        final singer = (item['element'] as Map<String, dynamic>?)?['singer']?.toString();

        final syl = LyricSyllable(
          text: text,
          startTimeMs: time,
          endTimeMs: time + duration,
          isPartOfWord: !text.endsWith(' '),
        );
        currentSyllables.add(syl);
        currentLineText += text;

        if (isLineEnding || text.endsWith('\n')) {
          final trimmed = currentLineText.trim();
          if (trimmed.isNotEmpty && currentSyllables.isNotEmpty) {
            final lineStart = currentSyllables.first.startTimeMs;
            final lineEnd = currentSyllables.last.endTimeMs;
            lines.add(LyricLine(
              text: trimmed,
              startTimeMs: lineStart,
              endTimeMs: lineEnd,
              syllables: List.from(currentSyllables),
              isWordSynced: true,
              singer: singer,
            ));
          }
          currentSyllables.clear();
          currentLineText = '';
        }
      }

      if (currentLineText.trim().isNotEmpty && currentSyllables.isNotEmpty) {
        lines.add(LyricLine(
          text: currentLineText.trim(),
          startTimeMs: currentSyllables.first.startTimeMs,
          endTimeMs: currentSyllables.last.endTimeMs,
          syllables: List.from(currentSyllables),
          isWordSynced: true,
        ));
      }

      lines.sort((a, b) => (a.startTimeMs ?? 0).compareTo(b.startTimeMs ?? 0));
      return LyricsResult(
        lines: withInstrumentalGaps(lines),
        source: provider.attributionName,
        songwriters: songwriters,
        hasWordSync: lines.any((l) => l.isWordSynced),
        provider: provider,
      );
    } catch (e) {
      debugPrint('[LyricsService] Error parsing Syllable JSON: $e');
      return LyricsResult.empty;
    }
  }

  static const int minGapMs = 4000;

  /// Inserts blank instrumental gap lines for musical intros or breaks >= 4s.
  /// Returns clean, trimmed lyric lines with non-empty text.
  static List<LyricLine> withInstrumentalGaps(List<LyricLine> lines) {
    if (lines.isEmpty) return lines;
    return lines.where((l) => l.text.trim().isNotEmpty).toList();
  }

  /// Computes the exact active lyric line index for [currentMs] within [lyrics].
  static int computeActiveLyricIndex(int currentMs, List<LyricLine> lyrics, {int leadInMs = 800}) {
    if (lyrics.isEmpty) return -1;

    // 1. Guard: If before first line starts
    final first = lyrics.first;
    final firstLead = first.text.isEmpty ? 0 : leadInMs;
    if (first.startTimeMs != null && currentMs < math.max(0, first.startTimeMs! - firstLead)) {
      return -1;
    }

    // 2. Direct active range check: line currently being sung (or within lead-in window)
    int bestActiveIdx = -1;
    int bestStartMs = -1;
    bool bestIsLead = false;

    for (int i = 0; i < lyrics.length; i++) {
      final line = lyrics[i];
      if (line.startTimeMs == null) continue;

      final lineLead = line.text.isEmpty ? 0 : leadInMs;
      final start = math.max(0, line.startTimeMs! - lineLead);
      final end = line.endTimeMs ?? (line.startTimeMs! + 3500);

      if (currentMs >= start && currentMs < end) {
        final isLead = !line.isBackground && line.text.isNotEmpty;
        if (bestActiveIdx == -1) {
          bestActiveIdx = i;
          bestStartMs = start;
          bestIsLead = isLead;
        } else {
          // Priority: Lead over background, then newer start time
          if (isLead && !bestIsLead) {
            bestActiveIdx = i;
            bestStartMs = start;
            bestIsLead = isLead;
          } else if (isLead == bestIsLead && start >= bestStartMs) {
            bestActiveIdx = i;
            bestStartMs = start;
          }
        }
      }
    }

    if (bestActiveIdx != -1) {
      return bestActiveIdx;
    }

    // 3. Inter-line gap handling (between line i end and line i+1 start)
    for (int i = 0; i < lyrics.length; i++) {
      final line = lyrics[i];
      if (line.startTimeMs == null) continue;

      final nextLine = (i < lyrics.length - 1) ? lyrics[i + 1] : null;
      final nextLead = (nextLine != null && nextLine.text.isNotEmpty) ? leadInMs : 0;
      final nextStart = nextLine?.startTimeMs != null
          ? math.max(0, nextLine!.startTimeMs! - nextLead)
          : null;
      if (currentMs >= line.startTimeMs! && (nextStart == null || currentMs < nextStart)) {
        final lineEnd = line.endTimeMs ?? (line.startTimeMs! + 3500);
        // If line has finished singing and next line is approaching, advance early to move upcoming line up first
        if (nextLine?.startTimeMs != null && currentMs >= (lineEnd + 250)) {
          final timeToNext = nextLine!.startTimeMs! - currentMs;
          if (timeToNext <= 2500) {
            return i + 1;
          }
        }
        // If there is an unvoiced break (> 2.5s after lineEnd and > 3.5s to next line), un-highlight
        if (line.text.isNotEmpty && (currentMs - lineEnd) > 2500) {
          if (nextStart != null && (nextStart - lineEnd) > 3500) {
            return -1; // In unvoiced break
          }
        }
        return i;
      }
    }

    return -1;
  }

  /// Finds the target line to center in view when seeking to [currentMs].
  static int findClosestLineIndex(int currentMs, List<LyricLine> lyrics) {
    if (lyrics.isEmpty) return -1;

    // 1. If before first line: target line 0
    final firstStart = lyrics.first.startTimeMs;
    if (firstStart != null && currentMs < firstStart) {
      return 0;
    }

    // 2. Find the line active at or immediately preceding currentMs
    for (int i = lyrics.length - 1; i >= 0; i--) {
      final start = lyrics[i].startTimeMs;
      if (start != null && currentMs >= start) {
        return i;
      }
    }

    // 3. Fallback to first line
    return 0;
  }

  static void _collectPieces(
    XmlNode node,
    List<_TtmlPiece> out,
    List<_TtmlPiece> backing,
  ) {
    for (final child in node.children) {
      if (child is XmlElement) {
        final role = child.getAttribute('ttm:role') ?? child.getAttribute('role');
        if (role == 'x-annotation' || role == 'x-translation') continue;
        final targetSink = (role == 'x-bg' || role == 'background') ? backing : out;

        final begin = ttmlTimeToMs(child.getAttribute('begin'));
        final end = ttmlTimeToMs(child.getAttribute('end'));

        final hasTimedChildren = child.children
            .whereType<XmlElement>()
            .any((el) => el.getAttribute('begin') != null);

        if (begin != null && end != null && !hasTimedChildren) {
          targetSink.add(_TtmlPiece(
            text: child.innerText,
            isTimed: true,
            startMs: begin,
            endMs: end,
          ));
        } else {
          _collectPieces(child, targetSink, backing);
        }
      } else if (child is XmlText) {
        final text = child.value;
        if (text.isNotEmpty) {
          out.add(_TtmlPiece(text: text, isTimed: false));
        }
      }
    }
  }

  static List<_TtmlWord> _mergeIntoWords(List<_TtmlPiece> pieces) {
    final words = <_TtmlWord>[];
    String currentText = '';
    final currentSyllables = <LyricSyllable>[];
    int start = 0;
    int end = 0;
    bool timed = false;

    void flush() {
      final trimmed = currentText.trim();
      currentText = '';
      if (trimmed.isNotEmpty && timed) {
        words.add(_TtmlWord(
          startMs: start,
          endMs: end,
          text: trimmed,
          syllables: List.from(currentSyllables),
        ));
      }
      currentSyllables.clear();
      timed = false;
    }

    for (final piece in pieces) {
      if (!piece.isTimed) {
        if (piece.text.trim().isEmpty) {
          flush();
        } else if (timed) {
          currentText += piece.text;
        }
        continue;
      }

      if (piece.text.trim().isEmpty) continue;
      if (piece.text.startsWith(RegExp(r'\s'))) {
        flush();
      }

      if (currentText.isEmpty) {
        start = piece.startMs;
      }
      currentText += piece.text.trim();
      currentSyllables.add(LyricSyllable(
        text: piece.text.trim(),
        startTimeMs: piece.startMs,
        endTimeMs: piece.endMs,
        isPartOfWord: true,
      ));
      end = math.max(end, piece.endMs);
      timed = true;

      if (piece.text.endsWith(' ')) {
        flush();
      }
    }
    flush();
    return words;
  }

  // =========================================================================
  // CACHE ACCESSORS
  // =========================================================================

  LyricsResult? getCachedLyrics(String trackKey, LyricsProviderType provider) {
    return _lyricsMemoryCache[trackKey]?[provider];
  }

  void cacheLyrics(String trackKey, LyricsProviderType provider, LyricsResult result) {
    _lyricsMemoryCache.putIfAbsent(trackKey, () => {})[provider] = result;
  }

  List<LyricsProviderType> getAvailableProviders(String trackKey) {
    final cacheForTrack = _lyricsMemoryCache[trackKey];
    if (cacheForTrack == null) return [];
    return cacheForTrack.entries
        .where((e) => e.value.lines.isNotEmpty)
        .map((e) => e.key)
        .toList();
  }

  // =========================================================================
  // FASTEST-FIRST MULTI-PROVIDER RACE & BACKGROUND FETCH
  // =========================================================================

  /// Fetches lyrics across all supported providers concurrently.
  /// Yields the fastest successful result immediately so the user experiences zero lag,
  /// while continuing background resolution for all remaining providers so they can be
  /// switched to instantaneously via the "More" options menu.
  Future<LyricsResult> fetchLyricsFastest({
    required String title,
    required String artist,
    required String videoId,
    String? isrc,
    int? durationSeconds,
    LyricsProviderType? preferredProvider,
    Future<List<LyricLine>> Function()? ytFallback,
    void Function(LyricsProviderType provider, LyricsResult result)? onProviderResult,
  }) async {
    final cleanTitle = cleanTrackTitle(title);
    final cleanArtist = cleanArtistName(artist);
    final trackKey = '$cleanTitle::$cleanArtist';

    // 1. If preferred provider is already cached with lyrics, return immediately
    if (preferredProvider != null) {
      final cached = getCachedLyrics(trackKey, preferredProvider);
      if (cached != null && cached.lines.isNotEmpty) {
        return cached;
      }
    }

    // 2. If any provider is already cached with lyrics for this track, return it immediately
    final existingProviders = getAvailableProviders(trackKey);
    if (existingProviders.isNotEmpty) {
      final primary = existingProviders.first;
      return getCachedLyrics(trackKey, primary)!;
    }

    final completer = Completer<LyricsResult>();

    // Priority ordering: preferred first, then high-probability fast word-sync & LRC APIs
    final allProviders = <LyricsProviderType>{
      ?preferredProvider,
      LyricsProviderType.lrcRed,
      LyricsProviderType.betterLyrics,
      LyricsProviderType.lrcLib,
      LyricsProviderType.lyricsPlus,
      LyricsProviderType.biniLyrics,
      LyricsProviderType.unison,
      LyricsProviderType.kuGou,
      LyricsProviderType.megalobiz,
      LyricsProviderType.musixmatch,
      LyricsProviderType.genius,
      LyricsProviderType.simpMusic,
      LyricsProviderType.paxSenix,
      LyricsProviderType.youTube,
    }.toList();

    int pendingCount = allProviders.length;

    for (final provider in allProviders) {
      fetchLyricsForProvider(
        provider: provider,
        title: cleanTitle,
        artist: cleanArtist,
        videoId: videoId,
        isrc: isrc,
        durationSeconds: durationSeconds,
        ytFallback: ytFallback,
      ).then((res) {
        pendingCount--;
        if (res.lines.isNotEmpty) {
          cacheLyrics(trackKey, provider, res);
          onProviderResult?.call(provider, res);

          if (!completer.isCompleted) {
            completer.complete(res);
          }
        } else {
          if (pendingCount <= 0 && !completer.isCompleted) {
            completer.complete(LyricsResult.empty);
          }
        }
      }).catchError((_) {
        pendingCount--;
        if (pendingCount <= 0 && !completer.isCompleted) {
          completer.complete(LyricsResult.empty);
        }
      });
    }

    return completer.future;
  }

  /// Fetches lyrics for a single specific provider.
  Future<LyricsResult> fetchLyricsForProvider({
    required LyricsProviderType provider,
    required String title,
    required String artist,
    required String videoId,
    String? isrc,
    int? durationSeconds,
    Future<List<LyricLine>> Function()? ytFallback,
  }) async {
    final cleanTitle = cleanTrackTitle(title);
    final cleanArtist = cleanArtistName(artist);
    final trackKey = '$cleanTitle::$cleanArtist';

    final cached = getCachedLyrics(trackKey, provider);
    if (cached != null) return cached;

    LyricsResult result = LyricsResult.empty;

    try {
      switch (provider) {
        case LyricsProviderType.lrcRed:
          result = await _fetchFromLrcRed(
            title: cleanTitle,
            artist: cleanArtist,
            isrc: isrc,
            durationSeconds: durationSeconds,
          ) ?? LyricsResult.empty;
          break;

        case LyricsProviderType.biniLyrics:
          result = await _fetchFromBiniLyrics(
            title: cleanTitle,
            artist: cleanArtist,
            isrc: isrc,
          ) ?? LyricsResult.empty;
          break;

        case LyricsProviderType.betterLyrics:
          result = await _fetchFromBetterLyrics(
            title: cleanTitle,
            artist: cleanArtist,
          ) ?? LyricsResult.empty;
          break;

        case LyricsProviderType.lyricsPlus:
          result = await _fetchFromLyricsPlus(
            title: cleanTitle,
            artist: cleanArtist,
            durationSeconds: durationSeconds,
          ) ?? LyricsResult.empty;
          break;

        case LyricsProviderType.unison:
          result = await _fetchFromUnison(
            videoId: videoId,
          ) ?? LyricsResult.empty;
          break;

        case LyricsProviderType.lrcLib:
          result = await _fetchFromLrcLib(
            title: cleanTitle,
            artist: cleanArtist,
            durationSeconds: durationSeconds,
          ) ?? LyricsResult.empty;
          break;

        case LyricsProviderType.kuGou:
          result = await _fetchFromKuGou(
            title: cleanTitle,
            artist: cleanArtist,
            durationSeconds: durationSeconds,
          ) ?? LyricsResult.empty;
          break;

        case LyricsProviderType.megalobiz:
          result = await _fetchFromMegalobiz(
            title: cleanTitle,
            artist: cleanArtist,
            durationSeconds: durationSeconds,
          ) ?? LyricsResult.empty;
          break;

        case LyricsProviderType.musixmatch:
          result = await _fetchFromMusixmatch(
            title: cleanTitle,
            artist: cleanArtist,
          ) ?? LyricsResult.empty;
          break;

        case LyricsProviderType.genius:
          result = await _fetchFromGenius(
            title: cleanTitle,
            artist: cleanArtist,
          ) ?? LyricsResult.empty;
          break;

        case LyricsProviderType.simpMusic:
          result = await _fetchFromSimpMusic(
            title: cleanTitle,
            artist: cleanArtist,
          ) ?? LyricsResult.empty;
          break;

        case LyricsProviderType.paxSenix:
          result = await _fetchFromPaxSenix(
            title: cleanTitle,
            artist: cleanArtist,
          ) ?? LyricsResult.empty;
          break;

        case LyricsProviderType.youTube:
          if (ytFallback != null) {
            final ytLines = await ytFallback();
            if (ytLines.isNotEmpty) {
              result = LyricsResult(
                lines: withInstrumentalGaps(ytLines),
                source: LyricsProviderType.youTube.attributionName,
                hasWordSync: false,
                provider: LyricsProviderType.youTube,
              );
            }
          }
          break;
      }
    } catch (e) {
      debugPrint('[LyricsService] ${provider.displayName} fetch error: $e');
    }

    if (result.lines.isNotEmpty) {
      cacheLyrics(trackKey, provider, result);
    }
    return result;
  }

  /// Backward-compatible fetchLyrics method.
  Future<LyricsResult> fetchLyrics({
    required String title,
    required String artist,
    required String videoId,
    String? isrc,
    int? durationSeconds,
    LyricsProviderType preferredProvider = LyricsProviderType.lrcRed,
    Future<List<LyricLine>> Function()? ytFallback,
  }) async {
    return fetchLyricsFastest(
      title: title,
      artist: artist,
      videoId: videoId,
      isrc: isrc,
      durationSeconds: durationSeconds,
      preferredProvider: preferredProvider,
      ytFallback: ytFallback,
    );
  }

  // =========================================================================
  // PROVIDER 1: lrc.red (Apple Music TTML / Word-Synced)
  // =========================================================================

  Future<LyricsResult?> _fetchFromLrcRed({
    required String title,
    required String artist,
    String? isrc,
    int? durationSeconds,
  }) async {
    if (isValidIsrc(isrc)) {
      final directUri = Uri.parse('$lrcRedBaseUrl/s/${isrc!.trim().toUpperCase()}.ttml');
      final ttml = await _getString(directUri);
      if (ttml != null && ttml.isNotEmpty) {
        final result = parseTtml(ttml, provider: LyricsProviderType.lrcRed);
        if (result.lines.isNotEmpty) return result;
      }
    }

    final searchQuery = '$title $artist'.trim();
    final searchUri = Uri.https('lrc.red', '/search.json', {'q': searchQuery});
    final searchData = await _getJson(searchUri);
    if (searchData == null) return null;

    final hitsRaw = searchData['hits'] as List<dynamic>?;
    if (hitsRaw == null || hitsRaw.isEmpty) return null;

    final hits = hitsRaw
        .whereType<Map<String, dynamic>>()
        .map((h) => LrcRedHit.fromJson(h))
        .toList();

    final durMs = (durationSeconds != null && durationSeconds > 0) ? durationSeconds * 1000 : 0;
    final hit = bestLrcRedHit(
      hits: hits,
      title: title,
      artist: artist,
      durationMs: durMs,
    );

    if (hit == null || !isValidIsrc(hit.isrc)) return null;

    final hitTtmlUri = Uri.parse('$lrcRedBaseUrl/s/${hit.isrc!.trim().toUpperCase()}.ttml');
    final ttml = await _getString(hitTtmlUri);
    if (ttml == null || ttml.isEmpty) return null;

    final result = parseTtml(ttml, provider: LyricsProviderType.lrcRed);
    return result.lines.isNotEmpty ? result : null;
  }

  // =========================================================================
  // PROVIDER 2: BiniLyrics (binimum)
  // =========================================================================

  Future<LyricsResult?> _fetchFromBiniLyrics({
    required String title,
    required String artist,
    String? isrc,
  }) async {
    final uri = Uri.https('lyrics-api.binimum.org', '/getLyrics', {
      'title': title,
      'artist': artist,
      if (isValidIsrc(isrc)) 'isrc': isrc!,
    });

    final data = await _getJson(uri);
    if (data == null) return null;

    final results = data['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;

    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;
      final lyricsUrl = item['lyricsUrl']?.toString();
      if (lyricsUrl != null && lyricsUrl.isNotEmpty) {
        final content = await _getString(Uri.parse(lyricsUrl));
        if (content != null && content.isNotEmpty) {
          if (content.contains('<tt') || lyricsUrl.endsWith('.ttml')) {
            final res = parseTtml(content, provider: LyricsProviderType.biniLyrics);
            if (res.lines.isNotEmpty) return res;
          } else {
            final res = parseLrc(content, provider: LyricsProviderType.biniLyrics);
            if (res.lines.isNotEmpty) return res;
          }
        }
      }
    }
    return null;
  }

  // =========================================================================
  // PROVIDER 3: BetterLyrics (api.betterlyrics.org)
  // =========================================================================

  Future<LyricsResult?> _fetchFromBetterLyrics({
    required String title,
    required String artist,
  }) async {
    final uri = Uri.https('api.betterlyrics.org', '/getLyrics', {
      's': title,
      'a': artist,
    });

    final data = await _getJson(uri);
    if (data == null) return null;

    final ttml = data['ttml']?.toString();
    if (ttml != null && ttml.isNotEmpty) {
      final res = parseTtml(ttml, provider: LyricsProviderType.betterLyrics);
      if (res.lines.isNotEmpty) return res;
    }
    return null;
  }

  // =========================================================================
  // PROVIDER 4: Unison (unison.betterlyrics.org / unison.boidu.dev)
  // =========================================================================

  Future<LyricsResult?> _fetchFromUnison({
    required String videoId,
  }) async {
    final trimmedId = videoId.trim();
    if (trimmedId.isEmpty) return null;

    // Try primary and secondary Unison hosts
    final hosts = ['unison.betterlyrics.org', 'unison.boidu.dev'];
    for (final host in hosts) {
      final uri = Uri.https(host, '/lyrics', {'v': trimmedId});
      final data = await _getJson(uri);
      if (data != null && data['success'] == true) {
        final payload = data['data'] as Map<String, dynamic>?;
        if (payload != null) {
          final lyrics = payload['lyrics']?.toString() ?? '';
          final format = payload['format']?.toString().toLowerCase() ?? '';
          if (lyrics.isNotEmpty) {
            if (format == 'ttml' || lyrics.contains('<tt')) {
              final res = parseTtml(lyrics, provider: LyricsProviderType.unison);
              if (res.lines.isNotEmpty) return res;
            } else {
              final res = parseLrc(lyrics, provider: LyricsProviderType.unison);
              if (res.lines.isNotEmpty) return res;
            }
          }
        }
      }
    }
    return null;
  }

  // =========================================================================
  // PROVIDER 5: LyricsPlus (lyricsplus.prjktla.my.id)
  // =========================================================================

  Future<LyricsResult?> _fetchFromLyricsPlus({
    required String title,
    required String artist,
    int? durationSeconds,
  }) async {
    final uri = Uri.https('lyricsplus.prjktla.my.id', '/v1/lyrics/get', {
      'title': title,
      'artist': artist,
      if (durationSeconds != null && durationSeconds > 0)
        'duration': durationSeconds.toString(),
    });

    final data = await _getJson(uri);
    if (data == null) return null;

    if (data['type'] == 'syllable') {
      final res = parseSyllableJson(data, provider: LyricsProviderType.lyricsPlus);
      if (res.lines.isNotEmpty) return res;
    }

    final lyricsList = data['lyrics'] as List<dynamic>?;
    if (lyricsList != null && lyricsList.isNotEmpty) {
      final lines = <LyricLine>[];
      for (final item in lyricsList) {
        if (item is Map<String, dynamic>) {
          final text = item['text']?.toString() ?? '';
          final time = (item['time'] as num?)?.toInt() ?? 0;
          final dur = (item['duration'] as num?)?.toInt() ?? 3500;
          if (text.trim().isNotEmpty) {
            lines.add(LyricLine(
              text: text.trim(),
              startTimeMs: time,
              endTimeMs: time + dur,
              isWordSynced: false,
            ));
          }
        }
      }
      if (lines.isNotEmpty) {
        return LyricsResult(
          lines: withInstrumentalGaps(lines),
          source: LyricsProviderType.lyricsPlus.attributionName,
          hasWordSync: false,
          provider: LyricsProviderType.lyricsPlus,
        );
      }
    }
    return null;
  }

  // =========================================================================
  // PROVIDER 6: LRCLIB (lrclib.net)
  // =========================================================================

  Future<LyricsResult?> _fetchFromLrcLib({
    required String title,
    required String artist,
    int? durationSeconds,
  }) async {
    // 1. Direct get endpoint
    final uri = Uri.https('lrclib.net', '/api/get', {
      'track_name': title,
      'artist_name': artist,
      if (durationSeconds != null && durationSeconds > 0)
        'duration': durationSeconds.toString(),
    });

    Map<String, dynamic>? data = await _getJson(uri);

    // 2. Search fallback if direct match failed
    if (data == null || (data['syncedLyrics'] == null && data['plainLyrics'] == null)) {
      final searchUri = Uri.https('lrclib.net', '/api/search', {'q': '$title $artist'});
      final searchList = await _getJsonList(searchUri);
      if (searchList != null && searchList.isNotEmpty) {
        data = searchList.first;
      }
    }

    if (data == null) return null;

    final syncedLyrics = data['syncedLyrics']?.toString();
    if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
      final res = parseLrc(syncedLyrics, provider: LyricsProviderType.lrcLib);
      if (res.lines.isNotEmpty) return res;
    }

    final plainLyrics = data['plainLyrics']?.toString();
    if (plainLyrics != null && plainLyrics.isNotEmpty) {
      final lines = plainLyrics
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((l) => LyricLine(text: l))
          .toList();
      if (lines.isNotEmpty) {
        return LyricsResult(
          lines: lines,
          source: LyricsProviderType.lrcLib.attributionName,
          hasWordSync: false,
          provider: LyricsProviderType.lrcLib,
        );
      }
    }
    return null;
  }

  // =========================================================================
  // PROVIDER 7: KuGou (酷狗音乐)
  // =========================================================================

  Future<LyricsResult?> _fetchFromKuGou({
    required String title,
    required String artist,
    int? durationSeconds,
  }) async {
    final durMs = (durationSeconds != null && durationSeconds > 0) ? durationSeconds * 1000 : 0;
    final searchUri = Uri.http('lyrics.kugou.com', '/search', {
      'ver': '1',
      'man': 'yes',
      'client': 'pc',
      'keyword': '$title $artist',
      if (durMs > 0) 'duration': durMs.toString(),
    });

    final searchData = await _getJson(searchUri);
    if (searchData == null) return null;

    final candidates = searchData['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;

    final first = candidates.first as Map<String, dynamic>;
    final id = first['id']?.toString();
    final accesskey = first['accesskey']?.toString();

    if (id == null || accesskey == null) return null;

    final downloadUri = Uri.http('lyrics.kugou.com', '/download', {
      'ver': '1',
      'client': 'pc',
      'id': id,
      'accesskey': accesskey,
      'fmt': 'lrc',
      'charset': 'utf8',
    });

    final downloadData = await _getJson(downloadUri);
    if (downloadData == null) return null;

    final b64Content = downloadData['content']?.toString();
    if (b64Content == null || b64Content.isEmpty) return null;

    try {
      final decodedLrc = utf8.decode(base64.decode(b64Content), allowMalformed: true);
      final res = parseLrc(decodedLrc, provider: LyricsProviderType.kuGou);
      if (res.lines.isNotEmpty) return res;
    } catch (_) {}

    return null;
  }

  // =========================================================================
  // PROVIDER 8: Megalobiz (api.megalobiz.com)
  // =========================================================================

  Future<LyricsResult?> _fetchFromMegalobiz({
    required String title,
    required String artist,
    int? durationSeconds,
  }) async {
    final searchUri = Uri.https('api.megalobiz.com', '/api/public/v1/search', {
      'title': title,
      'artist': artist,
      if (durationSeconds != null && durationSeconds > 0)
        'duration': durationSeconds.toString(),
      'limit': '5',
    });

    final searchData = await _getJson(searchUri);
    if (searchData == null) return null;

    final results = searchData['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) return null;

    for (final item in results) {
      if (item is! Map<String, dynamic>) continue;
      final lrcUrl = item['lrc_url']?.toString();
      if (lrcUrl != null && lrcUrl.isNotEmpty) {
        final lrc = await _getString(Uri.parse(lrcUrl));
        if (lrc != null && lrc.isNotEmpty) {
          final res = parseLrc(lrc, provider: LyricsProviderType.megalobiz);
          if (res.lines.isNotEmpty) return res;
        }
      }
    }
    return null;
  }

  // =========================================================================
  // PROVIDER 9: Musixmatch (apic-desktop.musixmatch.com)
  // =========================================================================

  Future<LyricsResult?> _fetchFromMusixmatch({
    required String title,
    required String artist,
  }) async {
    final uri = Uri.https('apic-desktop.musixmatch.com', '/ws/1.1/macro.subtitles.get', {
      'format': 'json',
      'q_track': title,
      'q_artist': artist,
      'user_language': 'en',
      'namespace': 'lyrics_richsync',
      'subtitle_format': 'lrc',
      'app_id': 'web-desktop-app-v1.0',
    });

    final data = await _getJson(uri);
    if (data == null) return null;

    final macroCalls = data['message']?['body']?['macro_calls'] as Map<String, dynamic>?;
    if (macroCalls == null) return null;

    final subList = macroCalls['track.subtitles.get']?['message']?['body']?['subtitle_list'] as List<dynamic>?;
    if (subList != null && subList.isNotEmpty) {
      final subBody = subList.first?['subtitle']?['subtitle_body']?.toString();
      // Drop Musixmatch anti-scraping honeypot text: "Wob gopini den..."
      if (subBody != null && subBody.isNotEmpty && !subBody.toLowerCase().contains('wob gopini')) {
        final res = parseLrc(subBody, provider: LyricsProviderType.musixmatch);
        if (res.lines.isNotEmpty) return res;
      }
    }
    return null;
  }

  // =========================================================================
  // PROVIDER 10: Genius (Plain Text Fallback)
  // =========================================================================

  Future<LyricsResult?> _fetchFromGenius({
    required String title,
    required String artist,
  }) async {
    final uri = Uri.https('api.lyrics.ovh', '/v1/$artist/$title');
    final data = await _getJson(uri);
    if (data == null) return null;

    final lyrics = data['lyrics']?.toString();
    if (lyrics != null && lyrics.trim().isNotEmpty) {
      final lines = lyrics
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((l) => LyricLine(text: l))
          .toList();
      if (lines.isNotEmpty) {
        return LyricsResult(
          lines: lines,
          source: LyricsProviderType.genius.attributionName,
          hasWordSync: false,
          provider: LyricsProviderType.genius,
        );
      }
    }
    return null;
  }

  // =========================================================================
  // PROVIDER 11: SimpMusic (api-lyrics.simpmusic.org)
  // =========================================================================

  Future<LyricsResult?> _fetchFromSimpMusic({
    required String title,
    required String artist,
  }) async {
    final uri = Uri.https('api-lyrics.simpmusic.org', '/lyrics', {
      'title': title,
      'artist': artist,
    });

    final data = await _getJson(uri);
    if (data != null) {
      final lrc = data['lrc']?.toString() ?? data['syncedLyrics']?.toString();
      if (lrc != null && lrc.isNotEmpty) {
        final res = parseLrc(lrc, provider: LyricsProviderType.simpMusic);
        if (res.lines.isNotEmpty) return res;
      }
    }
    return null;
  }

  // =========================================================================
  // PROVIDER 12: PaxSenix (api.paxsenix.org)
  // =========================================================================

  Future<LyricsResult?> _fetchFromPaxSenix({
    required String title,
    required String artist,
  }) async {
    final uri = Uri.https('api.paxsenix.org', '/lyrics/search', {
      'q': '$title $artist',
    });

    final data = await _getJson(uri);
    if (data != null && data['ok'] == true) {
      final lrc = data['lrc']?.toString() ?? data['lyrics']?.toString();
      if (lrc != null && lrc.isNotEmpty) {
        final res = parseLrc(lrc, provider: LyricsProviderType.paxSenix);
        if (res.lines.isNotEmpty) return res;
      }
    }
    return null;
  }

  // =========================================================================
  // HTTP HELPERS
  // =========================================================================

  Future<String?> _getString(Uri uri) async {
    try {
      final request = await _httpClient.getUrl(uri).timeout(const Duration(seconds: 4));
      request.headers.set('User-Agent', 'Cadmium-Lyrics/1.0 (Flutter; Mobile)');
      request.headers.set('Accept', 'application/xml, text/xml, text/plain, */*');

      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return await response.transform(utf8.decoder).join();
      }
    } catch (_) {
      // Network failure
    }
    return null;
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final request = await _httpClient.getUrl(uri).timeout(const Duration(seconds: 4));
      request.headers.set('User-Agent', 'Cadmium-Lyrics/1.0 (Flutter; Mobile)');
      request.headers.set('Accept', 'application/json, text/plain, */*');

      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
    } catch (_) {
      // Network or decode failure
    }
    return null;
  }

  Future<List<Map<String, dynamic>>?> _getJsonList(Uri uri) async {
    try {
      final request = await _httpClient.getUrl(uri).timeout(const Duration(seconds: 4));
      request.headers.set('User-Agent', 'Cadmium-Lyrics/1.0 (Flutter; Mobile)');
      request.headers.set('Accept', 'application/json, text/plain, */*');

      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is List) {
          return decoded.whereType<Map<String, dynamic>>().toList();
        }
      }
    } catch (_) {
      // Network or decode failure
    }
    return null;
  }

  void dispose() {
    _lyricsMemoryCache.clear();
    _httpClient.close();
  }
}

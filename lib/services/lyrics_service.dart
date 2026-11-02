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
}

extension LyricsProviderTypeExt on LyricsProviderType {
  String get displayName {
    switch (this) {
      case LyricsProviderType.lrcRed:
        return 'lrc.red';
      case LyricsProviderType.youTube:
        return 'YouTube';
    }
  }

  String get attributionName {
    switch (this) {
      case LyricsProviderType.lrcRed:
        return 'Apple Music (via lrc.red)';
      case LyricsProviderType.youTube:
        return 'YouTube Music';
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

  const LyricsResult({
    required this.lines,
    required this.source,
    this.songwriters,
    this.hasWordSync = false,
  });

  static const empty = LyricsResult(
    lines: [],
    source: 'None',
    hasWordSync: false,
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

/// Lyrics Service supporting lrc.red (Apple Music TTML / Word-Synced) and YouTube Music.
class LyricsService {
  final HttpClient _httpClient;
  final Map<String, LyricsResult> _lrcRedCache = {};
  final Map<String, LyricsResult> _youTubeCache = {};

  LyricsService({HttpClient? httpClient})
      : _httpClient = httpClient ?? (HttpClient()..connectionTimeout = const Duration(seconds: 5));

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

  /// Parses a TTML XML string (from lrc.red) into structured LyricLines.
  static LyricsResult parseTtml(String ttmlContent) {
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
        source: LyricsProviderType.lrcRed.attributionName,
        songwriters: songwriters,
        hasWordSync: anyWordSync,
      );
    } catch (e) {
      debugPrint('[LyricsService] Error parsing TTML: $e');
      return LyricsResult.empty;
    }
  }

  static const int minGapMs = 4000;

  /// Inserts blank instrumental gap lines for musical intros or breaks >= 4s.
  /// Matches Benjamin's am-lyrics withInstrumentalGaps (LyricGaps.kt).
  static List<LyricLine> withInstrumentalGaps(List<LyricLine> lines) {
    if (lines.isEmpty) return lines;

    // Filter out existing blank gap lines to prevent duplicate gaps on repeated processing
    final meaningfulLines = lines.where((l) => l.text.isNotEmpty || (l.startTimeMs != null && l.endTimeMs != null)).toList();
    if (meaningfulLines.isEmpty) return lines;

    final out = <LyricLine>[];

    // 1. Initial intro gap: If first timed line begins >= 3000ms, insert intro dots
    final first = meaningfulLines.first;
    if (first.text.isNotEmpty && first.startTimeMs != null && first.startTimeMs! >= 3000) {
      out.add(LyricLine(
        text: '',
        startTimeMs: 0,
        endTimeMs: first.startTimeMs!,
      ));
    }

    int maxEndSoFar = 0;
    for (int i = 0; i < meaningfulLines.length; i++) {
      final current = meaningfulLines[i];
      out.add(current);

      if (current.startTimeMs == null) continue;

      final currentStart = current.startTimeMs!;
      final currentEnd = current.endTimeMs ?? (currentStart + 3500);
      maxEndSoFar = math.max(maxEndSoFar, currentEnd);

      if (i < meaningfulLines.length - 1) {
        final next = meaningfulLines[i + 1];
        if (next.startTimeMs != null) {
          final nextStart = next.startTimeMs!;
          // Instrumental gap only occurs if singing has completely stopped for >= minGapMs
          if (nextStart - maxEndSoFar >= minGapMs && maxEndSoFar > 0) {
            out.add(LyricLine(
              text: '',
              startTimeMs: maxEndSoFar,
              endTimeMs: nextStart,
            ));
            maxEndSoFar = nextStart;
          }
        }
      }
    }
    return out;
  }

  /// Computes the exact active lyric line index for [currentMs] within [lyrics].
  ///
  /// Features:
  /// - Automatic 180ms lead-in anticipation so that upcoming lines scroll into
  ///   position right as vocal delivery begins, eliminating perceived lag.
  /// - Priority-based matching for overlapping vocals (duets, backing vocals):
  ///   Lead vocals (!isBackground) are prioritized over background vocals.
  ///   The line that began most recently (highest startTimeMs <= currentMs) takes precedence.
  /// - Instrumental gap lines (text == '') are matched directly when [currentMs] falls in their range.
  /// - Natural vocal pauses (< 2.5s) keep the preceding lyric active.
  /// - Returns -1 if playback is in an unvoiced intro or break before any line starts.
  static int computeActiveLyricIndex(int currentMs, List<LyricLine> lyrics, {int leadInMs = 180}) {
    if (lyrics.isEmpty) return -1;

    // 1. Guard: If before first line starts and first line is not an intro gap
    final first = lyrics.first;
    final firstLead = first.text.isEmpty ? 0 : leadInMs;
    if (first.startTimeMs != null && currentMs < math.max(0, first.startTimeMs! - firstLead)) {
      return -1;
    }

    // 2. Direct active range check: line currently being sung
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

  /// Finds the target line to center in view when seeking to [currentMs], even if
  /// [currentMs] falls in an unvoiced gap where [computeActiveLyricIndex] returns -1.
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

  /// Fetches lyrics for the requested provider (lrc.red or YouTube).
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
    final lrcCacheKey = '$cleanTitle::$cleanArtist';
    final ytCacheKey = videoId.trim();

    if (provider == LyricsProviderType.lrcRed) {
      if (_lrcRedCache.containsKey(lrcCacheKey)) {
        return _lrcRedCache[lrcCacheKey]!;
      }

      try {
        final result = await _fetchFromLrcRed(
          title: cleanTitle,
          artist: cleanArtist,
          isrc: isrc,
          durationSeconds: durationSeconds,
        );
        if (result != null && result.lines.isNotEmpty) {
          _lrcRedCache[lrcCacheKey] = result;
          return result;
        }
      } catch (e) {
        debugPrint('[LyricsService] lrc.red fetch error: $e');
      }
      return LyricsResult.empty;
    }

    // Provider == YouTube
    if (_youTubeCache.containsKey(ytCacheKey)) {
      return _youTubeCache[ytCacheKey]!;
    }

    if (ytFallback != null) {
      try {
        final ytLines = await ytFallback();
        if (ytLines.isNotEmpty) {
          final processedLines = withInstrumentalGaps(ytLines);
          final result = LyricsResult(
            lines: processedLines,
            source: LyricsProviderType.youTube.attributionName,
            hasWordSync: false,
          );
          _youTubeCache[ytCacheKey] = result;
          return result;
        }
      } catch (e) {
        debugPrint('[LyricsService] YouTube lyrics error: $e');
      }
    }

    return LyricsResult.empty;
  }

  /// Fetches lyrics with primary provider and fallback if primary has no results.
  Future<LyricsResult> fetchLyrics({
    required String title,
    required String artist,
    required String videoId,
    String? isrc,
    int? durationSeconds,
    LyricsProviderType preferredProvider = LyricsProviderType.lrcRed,
    Future<List<LyricLine>> Function()? ytFallback,
  }) async {
    // 1. Try preferred provider
    final primaryResult = await fetchLyricsForProvider(
      provider: preferredProvider,
      title: title,
      artist: artist,
      videoId: videoId,
      isrc: isrc,
      durationSeconds: durationSeconds,
      ytFallback: ytFallback,
    );

    if (primaryResult.lines.isNotEmpty) {
      return primaryResult;
    }

    // 2. Fallback to alternative supported provider
    final fallbackProvider = preferredProvider == LyricsProviderType.lrcRed
        ? LyricsProviderType.youTube
        : LyricsProviderType.lrcRed;

    return fetchLyricsForProvider(
      provider: fallbackProvider,
      title: title,
      artist: artist,
      videoId: videoId,
      isrc: isrc,
      durationSeconds: durationSeconds,
      ytFallback: ytFallback,
    );
  }

  // =========================================================================
  // lrc.red PROVIDER IMPLEMENTATION
  // =========================================================================

  Future<LyricsResult?> _fetchFromLrcRed({
    required String title,
    required String artist,
    String? isrc,
    int? durationSeconds,
  }) async {
    // 1. Direct ISRC lookup if available
    if (isValidIsrc(isrc)) {
      final directUri = Uri.parse('$lrcRedBaseUrl/s/${isrc!.trim().toUpperCase()}.ttml');
      final ttml = await _getString(directUri);
      if (ttml != null && ttml.isNotEmpty) {
        final result = parseTtml(ttml);
        if (result.lines.isNotEmpty) return result;
      }
    }

    // 2. Search query lookup: https://lrc.red/search.json?q={title} {artist}
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

    final result = parseTtml(ttml);
    return result.lines.isNotEmpty ? result : null;
  }

  // =========================================================================
  // HTTP HELPERS
  // =========================================================================

  Future<String?> _getString(Uri uri) async {
    try {
      final request = await _httpClient.getUrl(uri).timeout(const Duration(seconds: 5));
      request.headers.set('User-Agent', 'Wavify-Lyrics/1.0 (Flutter; Mobile)');
      request.headers.set('Accept', 'application/xml, text/xml, */*');

      final response = await request.close().timeout(const Duration(seconds: 5));
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
      final request = await _httpClient.getUrl(uri).timeout(const Duration(seconds: 5));
      request.headers.set('User-Agent', 'Wavify-Lyrics/1.0 (Flutter; Mobile)');
      request.headers.set('Accept', 'application/json');

      final response = await request.close().timeout(const Duration(seconds: 5));
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

  void dispose() {
    _lrcRedCache.clear();
    _youTubeCache.clear();
    _httpClient.close();
  }
}

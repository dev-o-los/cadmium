import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/lyric_line.dart';

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

/// Apple Music-style Multi-Tier Lyrics Provider Service
/// Inspired by binimum/am-lyrics (Benjamin):
/// 1. lrc.red (Apple Music TTML / Word-Synced JSON via ISRC & track matching)
/// 2. BiniLyrics / LyricsPlus (KPoe) (Word-Synced Apple Music syllabus format)
/// 3. LRCLIB (Synced LRC & plain text fallback)
/// 4. YouTube Music Timed Lyrics fallback
class LyricsService {
  final HttpClient _httpClient;
  final Map<String, LyricsResult> _cache = {};

  LyricsService({HttpClient? httpClient})
      : _httpClient = httpClient ?? (HttpClient()..connectionTimeout = const Duration(seconds: 4));

  static const List<String> _kpoeServers = [
    'https://lyricsplus.binimum.org',
    'https://lyricsplus-seven.vercel.app',
    'https://lyrics-plus-backend.vercel.app',
  ];

  /// Cleans track title by stripping visualizer, official video, and featured artist tags
  /// that commonly pollute YouTube Music song names and interfere with exact lyrics matching.
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
    final parts = rawArtist.split(RegExp(r'[,&]|\s+feat\.?|\s+ft\.?', caseSensitive: false));
    return parts.first.trim();
  }

  /// Fetches lyrics using the binimum/am-lyrics provider chain.
  Future<LyricsResult> fetchLyrics({
    required String title,
    required String artist,
    String? album,
    int? durationSeconds,
    Future<List<LyricLine>> Function()? ytFallback,
  }) async {
    final cleanTitle = cleanTrackTitle(title);
    final cleanArtist = cleanArtistName(artist);
    final cacheKey = '$cleanTitle::$cleanArtist';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // 1. Try lrc.red (Apple Music word-by-word synced TTML/JSON)
    try {
      final lrcRedResult = await _fetchFromLrcRed(cleanTitle, cleanArtist, album: album, durationSeconds: durationSeconds);
      if (lrcRedResult != null && lrcRedResult.lines.isNotEmpty) {
        _cache[cacheKey] = lrcRedResult;
        return lrcRedResult;
      }
    } catch (e) {
      debugPrint('[LyricsService] lrc.red lookup error: $e');
    }

    // 2. Try LyricsPlus / BiniLyrics (Word-by-word Apple syllabus format)
    try {
      final lyricsPlusResult = await _fetchFromLyricsPlus(cleanTitle, cleanArtist, album: album, durationSeconds: durationSeconds);
      if (lyricsPlusResult != null && lyricsPlusResult.lines.isNotEmpty) {
        _cache[cacheKey] = lyricsPlusResult;
        return lyricsPlusResult;
      }
    } catch (e) {
      debugPrint('[LyricsService] LyricsPlus lookup error: $e');
    }

    // 3. Try LRCLIB (LRC synced lyrics)
    try {
      final lrclibResult = await _fetchFromLrclib(cleanTitle, cleanArtist, durationSeconds: durationSeconds);
      if (lrclibResult != null && lrclibResult.lines.isNotEmpty) {
        _cache[cacheKey] = lrclibResult;
        return lrclibResult;
      }
    } catch (e) {
      debugPrint('[LyricsService] LRCLIB lookup error: $e');
    }

    // 4. Fallback to YouTube Music Timed Lyrics
    if (ytFallback != null) {
      try {
        final ytLines = await ytFallback();
        if (ytLines.isNotEmpty) {
          final result = LyricsResult(
            lines: ytLines,
            source: 'YouTube Music',
            hasWordSync: false,
          );
          _cache[cacheKey] = result;
          return result;
        }
      } catch (e) {
        debugPrint('[LyricsService] YouTube Music fallback error: $e');
      }
    }

    return LyricsResult.empty;
  }

  // =========================================================================
  // PROVIDER 1: lrc.red
  // =========================================================================
  Future<LyricsResult?> _fetchFromLrcRed(
    String title,
    String artist, {
    String? album,
    int? durationSeconds,
  }) async {
    final queryParams = {
      'track': title,
      'artist': artist,
      if (album != null && album.isNotEmpty) 'album': album,
      if (durationSeconds != null && durationSeconds > 0) 'duration': durationSeconds.toString(),
    };

    final uri = Uri.https('lrc.red', '/match.json', queryParams);
    final matchData = await _getJson(uri);
    if (matchData == null) return null;

    final hits = matchData['hits'] as List<dynamic>?;
    if (hits == null || hits.isEmpty) return null;

    final firstHit = hits.first as Map<String, dynamic>;
    final isrc = firstHit['isrc'] as String?;
    if (isrc == null || isrc.trim().isEmpty) return null;

    final songUri = Uri.https('lrc.red', '/s/${isrc.trim()}.song.json');
    final songData = await _getJson(songUri);
    if (songData == null) return null;

    return _parseLrcRedJson(songData);
  }

  LyricsResult? _parseLrcRedJson(Map<String, dynamic> songData) {
    final lyricsObj = songData['lyrics'] as Map<String, dynamic>?;
    if (lyricsObj == null) return null;

    final rawLines = lyricsObj['lines'] as List<dynamic>?;
    if (rawLines == null || rawLines.isEmpty) return null;

    final isWordSync = lyricsObj['sync'] == 'word';
    final songwritersList = songData['songwriters'] as List<dynamic>?;
    final songwriters = songwritersList?.map((s) => s.toString()).join(', ');

    final List<LyricLine> lines = [];

    for (final raw in rawLines) {
      if (raw is! Map<String, dynamic>) continue;
      final text = (raw['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) continue;

      final beginSec = (raw['begin'] as num?)?.toDouble() ?? 0.0;
      final endSec = (raw['end'] as num?)?.toDouble() ?? beginSec;
      final startTimeMs = (beginSec * 1000).round();
      final endTimeMs = (endSec * 1000).round();

      final voice = (raw['voice'] as String?)?.toLowerCase();
      final isOppositeTurn = voice != null && voice != 'a' && voice != 'v1';
      final part = raw['part'] as String?;
      final isBackground = part?.toLowerCase() == 'background' || (text.startsWith('(') && text.endsWith(')'));

      final List<LyricSyllable> syllables = [];
      if (isWordSync && raw['words'] is List) {
        final wordsList = raw['words'] as List<dynamic>;
        for (int wIdx = 0; wIdx < wordsList.length; wIdx++) {
          final wordGroup = wordsList[wIdx];
          if (wordGroup is List) {
            for (int sIdx = 0; sIdx < wordGroup.length; sIdx++) {
              final syl = wordGroup[sIdx];
              if (syl is Map<String, dynamic>) {
                final sylText = (syl['text'] as String?) ?? '';
                final isPartOfWord = sIdx < wordGroup.length - 1;
                final space = (!isPartOfWord && wIdx < wordsList.length - 1) ? ' ' : '';
                final sBegin = (syl['begin'] as num?)?.toDouble() ?? beginSec;
                final sEnd = (syl['end'] as num?)?.toDouble() ?? endSec;

                syllables.add(LyricSyllable(
                  text: '$sylText$space',
                  startTimeMs: (sBegin * 1000).round(),
                  endTimeMs: (sEnd * 1000).round(),
                  isPartOfWord: isPartOfWord,
                ));
              }
            }
          }
        }
      }

      lines.add(LyricLine(
        text: text,
        startTimeMs: startTimeMs,
        endTimeMs: endTimeMs,
        syllables: syllables,
        isWordSynced: isWordSync && syllables.isNotEmpty,
        isBackground: isBackground,
        isOppositeTurn: isOppositeTurn,
        singer: voice,
        songPart: part,
      ));
    }

    if (lines.isEmpty) return null;

    return LyricsResult(
      lines: lines,
      source: 'Apple Music (via lrc.red)',
      songwriters: songwriters,
      hasWordSync: isWordSync,
    );
  }

  // =========================================================================
  // PROVIDER 2: LyricsPlus / BiniLyrics (KPoe)
  // =========================================================================
  Future<LyricsResult?> _fetchFromLyricsPlus(
    String title,
    String artist, {
    String? album,
    int? durationSeconds,
  }) async {
    final queryParams = {
      'title': title,
      'artist': artist,
      if (album != null && album.isNotEmpty) 'album': album,
      if (durationSeconds != null && durationSeconds > 0) 'duration': durationSeconds.toString(),
    };

    for (final baseUrl in _kpoeServers) {
      try {
        final uri = Uri.parse('$baseUrl/v2/lyrics/get').replace(queryParameters: queryParams);
        final payload = await _getJson(uri);
        if (payload != null && payload['lyrics'] is List) {
          final result = _parseLyricsPlusJson(payload);
          if (result != null && result.lines.isNotEmpty) {
            return result;
          }
        }
      } catch (_) {
        // Continue to fallback server
      }
    }
    return null;
  }

  LyricsResult? _parseLyricsPlusJson(Map<String, dynamic> payload) {
    final rawLyrics = payload['lyrics'] as List<dynamic>?;
    if (rawLyrics == null || rawLyrics.isEmpty) return null;

    final metadata = payload['metadata'] as Map<String, dynamic>?;
    final songwritersList = metadata?['songWriters'] as List<dynamic>?;
    final songwriters = songwritersList?.map((s) => s.toString()).join(', ');
    final isWordType = payload['type'] == 'Word';

    final List<LyricLine> lines = [];

    for (final item in rawLyrics) {
      if (item is! Map<String, dynamic>) continue;
      final text = (item['text'] as String?)?.trim() ?? '';
      if (text.isEmpty) continue;

      final timeMs = (item['time'] as num?)?.toInt() ?? 0;
      final durationMs = (item['duration'] as num?)?.toInt() ?? 0;
      final endTimeMs = timeMs + durationMs;

      final element = item['element'] as Map<String, dynamic>?;
      final singer = element?['singer'] as String?;
      final isOppositeTurn = singer != null && singer != 'v1';
      final isBackground = text.startsWith('(') && text.endsWith(')');

      final List<LyricSyllable> syllables = [];
      final rawSyllabus = item['syllabus'] as List<dynamic>?;
      if (rawSyllabus != null && rawSyllabus.isNotEmpty) {
        for (int i = 0; i < rawSyllabus.length; i++) {
          final s = rawSyllabus[i];
          if (s is Map<String, dynamic>) {
            final sText = (s['text'] as String?) ?? '';
            final sTime = (s['time'] as num?)?.toInt() ?? timeMs;
            final sDuration = (s['duration'] as num?)?.toInt() ?? 0;

            syllables.add(LyricSyllable(
              text: sText,
              startTimeMs: sTime,
              endTimeMs: sTime + sDuration,
              isPartOfWord: !sText.endsWith(' ') && i < rawSyllabus.length - 1,
            ));
          }
        }
      }

      lines.add(LyricLine(
        text: text,
        startTimeMs: timeMs,
        endTimeMs: endTimeMs,
        syllables: syllables,
        isWordSynced: isWordType && syllables.isNotEmpty,
        isBackground: isBackground,
        isOppositeTurn: isOppositeTurn,
        singer: singer,
      ));
    }

    if (lines.isEmpty) return null;

    return LyricsResult(
      lines: lines,
      source: 'Apple Music (via BiniLyrics)',
      songwriters: songwriters,
      hasWordSync: isWordType,
    );
  }

  // =========================================================================
  // PROVIDER 3: LRCLIB
  // =========================================================================
  Future<LyricsResult?> _fetchFromLrclib(
    String title,
    String artist, {
    int? durationSeconds,
  }) async {
    // 1. Try exact match
    final queryParams = {
      'track_name': title,
      'artist_name': artist,
      if (durationSeconds != null && durationSeconds > 0) 'duration': durationSeconds.toString(),
    };

    final uri = Uri.https('lrclib.net', '/api/get', queryParams);
    var data = await _getJson(uri);

    // 2. Fallback to search query
    if (data == null || (data['syncedLyrics'] == null && data['plainLyrics'] == null)) {
      final searchUri = Uri.https('lrclib.net', '/api/search', {'q': '$artist $title'});
      final searchData = await _getJsonList(searchUri);
      if (searchData != null && searchData.isNotEmpty) {
        data = searchData.firstWhere(
          (item) => item['syncedLyrics'] != null,
          orElse: () => searchData.first,
        ) as Map<String, dynamic>;
      }
    }

    if (data == null) return null;

    final syncedLyrics = data['syncedLyrics'] as String?;
    if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
      final lines = _parseLrcSubtitles(syncedLyrics);
      if (lines.isNotEmpty) {
        return LyricsResult(
          lines: lines,
          source: 'LRCLIB (Synced)',
          hasWordSync: false,
        );
      }
    }

    final plainLyrics = data['plainLyrics'] as String?;
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
          source: 'LRCLIB',
          hasWordSync: false,
        );
      }
    }

    return null;
  }

  List<LyricLine> _parseLrcSubtitles(String lrcContent) {
    final List<LyricLine> parsedLines = [];
    final lrcRegex = RegExp(r'^\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\](.*)$');

    final rawLines = lrcContent.split('\n');
    for (final raw in rawLines) {
      final trimmed = raw.trim();
      final match = lrcRegex.firstMatch(trimmed);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final subSecondsStr = match.group(3) ?? '00';
        final subSeconds = int.parse(subSecondsStr.padRight(3, '0').substring(0, 3));

        final timestampMs = (minutes * 60 * 1000) + (seconds * 1000) + subSeconds;
        final text = match.group(4)?.trim() ?? '';

        if (text.isNotEmpty) {
          parsedLines.add(LyricLine(
            text: text,
            startTimeMs: timestampMs,
            isBackground: text.startsWith('(') && text.endsWith(')'),
          ));
        }
      }
    }

    // Infer endTimeMs from subsequent line's startTimeMs
    for (int i = 0; i < parsedLines.length; i++) {
      if (i < parsedLines.length - 1) {
        final nextStart = parsedLines[i + 1].startTimeMs;
        if (nextStart != null) {
          parsedLines[i] = parsedLines[i].copyWith(endTimeMs: nextStart);
        }
      } else {
        // Last line default 5s duration
        if (parsedLines[i].startTimeMs != null) {
          parsedLines[i] = parsedLines[i].copyWith(endTimeMs: parsedLines[i].startTimeMs! + 5000);
        }
      }
    }

    return parsedLines;
  }

  // =========================================================================
  // HTTP HELPERS
  // =========================================================================
  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    try {
      final request = await _httpClient.getUrl(uri).timeout(const Duration(seconds: 4));
      request.headers.set('User-Agent', 'Wavify-AmLyrics/1.0 (Flutter; Mobile)');
      request.headers.set('Accept', 'application/json');

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

  Future<List<dynamic>?> _getJsonList(Uri uri) async {
    try {
      final request = await _httpClient.getUrl(uri).timeout(const Duration(seconds: 4));
      request.headers.set('User-Agent', 'Wavify-AmLyrics/1.0 (Flutter; Mobile)');
      request.headers.set('Accept', 'application/json');

      final response = await request.close().timeout(const Duration(seconds: 4));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = await response.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is List<dynamic>) {
          return decoded;
        }
      }
    } catch (_) {
      // Network or decode failure
    }
    return null;
  }

  void dispose() {
    _cache.clear();
    _httpClient.close();
  }
}


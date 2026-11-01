import 'dart:math' as math;

/// Represents a single syllable or word in word-by-word synced Apple Music karaoke lyrics.
class LyricSyllable {
  final String text;
  final int startTimeMs;
  final int endTimeMs;
  final bool isPartOfWord;

  const LyricSyllable({
    required this.text,
    required this.startTimeMs,
    required this.endTimeMs,
    this.isPartOfWord = false,
  });

  int get durationMs => math.max(0, endTimeMs - startTimeMs);

  /// Progress from 0.0 (not reached) to 1.0 (completed) at [currentMs].
  double getProgress(int currentMs) {
    if (currentMs <= startTimeMs) return 0.0;
    if (currentMs >= endTimeMs) return 1.0;
    final duration = durationMs;
    if (duration <= 0) return 1.0;
    return ((currentMs - startTimeMs) / duration).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'startTimeMs': startTimeMs,
        'endTimeMs': endTimeMs,
        'isPartOfWord': isPartOfWord,
      };

  factory LyricSyllable.fromJson(Map<String, dynamic> json) => LyricSyllable(
        text: json['text'] as String,
        startTimeMs: json['startTimeMs'] as int,
        endTimeMs: json['endTimeMs'] as int,
        isPartOfWord: json['isPartOfWord'] as bool? ?? false,
      );
}

/// Domain model representing a line of synchronized or untimed lyrics,
/// matching Apple Music's word-by-word specification (as seen in binimum/am-lyrics).
class LyricLine {
  final String text;
  final int? startTimeMs;
  final int? endTimeMs;
  final List<LyricSyllable> syllables;
  final bool isWordSynced;
  final bool isBackground;
  final bool isOppositeTurn;
  final String? singer;
  final String? songPart;

  const LyricLine({
    required this.text,
    this.startTimeMs,
    this.endTimeMs,
    this.syllables = const [],
    this.isWordSynced = false,
    this.isBackground = false,
    this.isOppositeTurn = false,
    this.singer,
    this.songPart,
  });

  bool get isTimed => startTimeMs != null;

  /// Whether playback timestamp in milliseconds falls within this line.
  bool isActiveAt(int currentMs) {
    if (startTimeMs == null) return false;
    if (endTimeMs != null) {
      return currentMs >= startTimeMs! && currentMs <= endTimeMs!;
    }
    return currentMs >= startTimeMs!;
  }

  LyricLine copyWith({
    String? text,
    int? startTimeMs,
    int? endTimeMs,
    List<LyricSyllable>? syllables,
    bool? isWordSynced,
    bool? isBackground,
    bool? isOppositeTurn,
    String? singer,
    String? songPart,
  }) {
    return LyricLine(
      text: text ?? this.text,
      startTimeMs: startTimeMs ?? this.startTimeMs,
      endTimeMs: endTimeMs ?? this.endTimeMs,
      syllables: syllables ?? this.syllables,
      isWordSynced: isWordSynced ?? this.isWordSynced,
      isBackground: isBackground ?? this.isBackground,
      isOppositeTurn: isOppositeTurn ?? this.isOppositeTurn,
      singer: singer ?? this.singer,
      songPart: songPart ?? this.songPart,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'startTimeMs': startTimeMs,
        'endTimeMs': endTimeMs,
        'syllables': syllables.map((s) => s.toJson()).toList(),
        'isWordSynced': isWordSynced,
        'isBackground': isBackground,
        'isOppositeTurn': isOppositeTurn,
        'singer': singer,
        'songPart': songPart,
      };

  factory LyricLine.fromJson(Map<String, dynamic> json) => LyricLine(
        text: json['text'] as String,
        startTimeMs: json['startTimeMs'] as int?,
        endTimeMs: json['endTimeMs'] as int?,
        syllables: (json['syllables'] as List<dynamic>?)
                ?.map((s) => LyricSyllable.fromJson(s as Map<String, dynamic>))
                .toList() ??
            const [],
        isWordSynced: json['isWordSynced'] as bool? ?? false,
        isBackground: json['isBackground'] as bool? ?? false,
        isOppositeTurn: json['isOppositeTurn'] as bool? ?? false,
        singer: json['singer'] as String?,
        songPart: json['songPart'] as String?,
      );
}

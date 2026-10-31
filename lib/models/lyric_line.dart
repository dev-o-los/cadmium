/// Domain model representing a line of synchronized or untimed lyrics.
class LyricLine {
  final String text;
  final int? startTimeMs;
  final int? endTimeMs;

  const LyricLine({
    required this.text,
    this.startTimeMs,
    this.endTimeMs,
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
}


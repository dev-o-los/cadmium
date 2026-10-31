/// Domain model representing a song item parsed from YouTube Music.
/// This decouples the UI from third-party API data structures.
class SongItem {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? thumbnailUrl;
  final int? durationSeconds;

  const SongItem({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.thumbnailUrl,
    this.durationSeconds,
  });

  /// Formats duration seconds into mm:ss format.
  String get formattedDuration {
    if (durationSeconds == null || durationSeconds! <= 0) return '';
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}


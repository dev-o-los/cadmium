class VideoItem {
  final String id;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final String? views;

  const VideoItem({
    required this.id,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    this.durationSeconds,
    this.views,
  });

  String get subtitle {
    final parts = <String>[];
    if (artist.isNotEmpty) parts.add(artist);
    if (views != null && views!.isNotEmpty) {
      parts.add(views!);
    } else if (durationSeconds != null && durationSeconds! > 0) {
      final minutes = durationSeconds! ~/ 60;
      final seconds = durationSeconds! % 60;
      parts.add('$minutes min ${seconds.toString().padLeft(2, '0')} sec');
    }
    return parts.join(' • ');
  }
}


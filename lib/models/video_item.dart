import 'song_item.dart';

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

  /// Guaranteed thumbnail URL. If [thumbnailUrl] is provided and clean, uses it.
  /// Otherwise resolves guaranteed YouTube video thumbnail endpoint for [id].
  String? get resolvedThumbnailUrl {
    if (thumbnailUrl != null && thumbnailUrl!.trim().isNotEmpty) {
      final clean = thumbnailUrl!.trim();
      return clean.startsWith('//') ? 'https:$clean' : clean;
    }
    if (id.isNotEmpty && !id.startsWith('local_') && !id.contains('/')) {
      return 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
    }
    return null;
  }

  /// High-resolution upgraded thumbnail for crisp AMOLED display.
  String? get highResThumbnailUrl =>
      SongItem.upgradeThumbnail(resolvedThumbnailUrl, size: 800, quality: 95) ??
      resolvedThumbnailUrl;

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'thumbnailUrl': thumbnailUrl,
        'durationSeconds': durationSeconds,
        'views': views,
      };

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        durationSeconds: json['durationSeconds'] as int?,
        views: json['views'] as String?,
      );
}


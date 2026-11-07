import 'song_item.dart';

class AlbumItem {
  final String id;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final String type; // 'Single', 'EP', 'Album'
  final int? year;
  final bool isCustom;
  final String? description;
  final int? trackCount;
  final int? durationMinutes;

  const AlbumItem({
    required this.id,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    this.type = 'Album',
    this.year,
    this.isCustom = false,
    this.description,
    this.trackCount,
    this.durationMinutes,
  });

  String get subtitle {
    final yearStr = year != null ? ' • $year' : '';
    return '$type • $artist$yearStr';
  }

  /// Clean, sanitized thumbnail URL for the album.
  String? get resolvedThumbnailUrl {
    if (thumbnailUrl != null && thumbnailUrl!.trim().isNotEmpty) {
      final clean = thumbnailUrl!.trim();
      return clean.startsWith('//') ? 'https:$clean' : clean;
    }
    return null;
  }

  AlbumItem copyWith({
    String? id,
    String? title,
    String? artist,
    String? thumbnailUrl,
    String? type,
    int? year,
    bool? isCustom,
    String? description,
    int? trackCount,
    int? durationMinutes,
  }) {
    return AlbumItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      type: type ?? this.type,
      year: year ?? this.year,
      isCustom: isCustom ?? this.isCustom,
      description: description ?? this.description,
      trackCount: trackCount ?? this.trackCount,
      durationMinutes: durationMinutes ?? this.durationMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'thumbnailUrl': thumbnailUrl,
        'type': type,
        'year': year,
        'isCustom': isCustom,
        'description': description,
        'trackCount': trackCount,
        'durationMinutes': durationMinutes,
      };

  factory AlbumItem.fromJson(Map<String, dynamic> json) => AlbumItem(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        type: json['type'] as String? ?? 'Album',
        year: json['year'] as int?,
        isCustom: json['isCustom'] as bool? ?? false,
        description: json['description'] as String?,
        trackCount: json['trackCount'] as int?,
        durationMinutes: json['durationMinutes'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlbumItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Detailed domain model combining an [AlbumItem] with its resolved tracks
/// and total calculated duration.
class AlbumDetails {
  final AlbumItem album;
  final List<SongItem> tracks;
  final int totalDurationSeconds;

  const AlbumDetails({
    required this.album,
    required this.tracks,
    required this.totalDurationSeconds,
  });

  String get formattedTotalDuration {
    if (totalDurationSeconds <= 0) return '';
    final minutes = totalDurationSeconds ~/ 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final remainingMins = minutes % 60;
      return '$hours hr $remainingMins min';
    }
    return '$minutes min';
  }
}

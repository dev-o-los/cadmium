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

  /// Automatically upgrades YouTube Music thumbnails (which default to 60x60 or 120x120)
  /// into crystal-clear HD resolution (800x800, 1000x1000, or 1200x1200).
  static String? upgradeThumbnail(String? url, {int size = 800}) {
    if (url == null || url.isEmpty) return url;

    // Google User Content (YouTube Music album art, e.g. yt3.googleusercontent.com, lh3.googleusercontent.com)
    if (url.contains('googleusercontent.com') || url.contains('ggpht.com')) {
      if (RegExp(r'=w\d+-h\d+').hasMatch(url)) {
        return url.replaceAll(RegExp(r'=w\d+-h\d+.*'), '=w$size-h$size-l90-rj');
      }
      if (RegExp(r'=s\d+').hasMatch(url)) {
        return url.replaceAll(RegExp(r'=s\d+.*'), '=s$size');
      }
      return '$url=w$size-h$size-l90-rj';
    }

    // YouTube standard thumbnails
    if (url.contains('i.ytimg.com') || url.contains('img.youtube.com')) {
      if (url.contains('hqdefault.jpg') || url.contains('default.jpg') || url.contains('mqdefault.jpg')) {
        return url.replaceAll(RegExp(r'(mqdefault|default)\.jpg'), 'hqdefault.jpg');
      }
    }

    return url;
  }

  /// Returns high-resolution artwork URL for full-screen and crisp player displays
  String? get highResThumbnailUrl => upgradeThumbnail(thumbnailUrl, size: 1000);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'thumbnailUrl': thumbnailUrl,
        'durationSeconds': durationSeconds,
      };

  factory SongItem.fromJson(Map<String, dynamic> json) => SongItem(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        durationSeconds: json['durationSeconds'] as int?,
      );

  SongItem copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? thumbnailUrl,
    int? durationSeconds,
  }) {
    return SongItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}


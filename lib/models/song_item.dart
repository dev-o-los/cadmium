/// Domain model representing a song item parsed from YouTube Music.
/// This decouples the UI from third-party API data structures.
class SongItem {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final String? animatedArtworkUrl;

  const SongItem({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.thumbnailUrl,
    this.durationSeconds,
    this.animatedArtworkUrl,
  });

  /// Formats duration seconds into mm:ss format.
  String get formattedDuration {
    if (durationSeconds == null || durationSeconds! <= 0) return '';
    final minutes = durationSeconds! ~/ 60;
    final seconds = durationSeconds! % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Returns the thumbnail URL if non-empty, or resolves a YouTube thumbnail from [id]
  /// when [id] is a valid YouTube video ID (non-empty and not a synthetic ID like local_*).
  String? get resolvedThumbnailUrl {
    if (thumbnailUrl != null && thumbnailUrl!.trim().isNotEmpty) {
      return thumbnailUrl!.trim();
    }
    if (id.isNotEmpty && !id.startsWith('local_') && !id.contains('/')) {
      return 'https://i.ytimg.com/vi/$id/hqdefault.jpg';
    }
    return null;
  }

  /// Automatically upgrades YouTube Music thumbnails (which default to 60x60 or 120x120)
  /// and standard YouTube thumbnails into studio-master quality (up to 1800x1800 uncompressed quality)
  /// optimized for high-DPI AMOLED mobile screens.
  static String? upgradeThumbnail(String? url, {int size = 800, int quality = 95}) {
    if (url == null || url.isEmpty) return url;

    final cleanUrl = url.startsWith('//') ? 'https:$url' : url;

    // Google User Content (YouTube Music album art, e.g. yt3.googleusercontent.com, lh3.googleusercontent.com)
    if (cleanUrl.contains('googleusercontent.com') || cleanUrl.contains('ggpht.com')) {
      if (RegExp(r'=w\d+-h\d+').hasMatch(cleanUrl)) {
        return cleanUrl.replaceAll(RegExp(r'=w\d+-h\d+.*'), '=w$size-h$size-l$quality-rj');
      }
      if (RegExp(r'=s\d+').hasMatch(cleanUrl)) {
        return cleanUrl.replaceAll(RegExp(r'=s\d+.*'), '=s$size-c-k');
      }
      if (!cleanUrl.contains('=')) {
        return '$cleanUrl=w$size-h$size-l$quality-rj';
      }
      return cleanUrl;
    }

    // YouTube standard thumbnails: upgrade to 1920x1080 Full HD maxresdefault
    if (cleanUrl.contains('i.ytimg.com') || cleanUrl.contains('img.youtube.com')) {
      if (cleanUrl.contains('hqdefault.jpg') ||
          cleanUrl.contains('default.jpg') ||
          cleanUrl.contains('mqdefault.jpg') ||
          cleanUrl.contains('sddefault.jpg') ||
          cleanUrl.contains('hq720.jpg')) {
        return cleanUrl.replaceAll(RegExp(r'(mqdefault|default|hqdefault|sddefault|hq720)\.jpg'), 'maxresdefault.jpg');
      }
    }

    return cleanUrl;
  }

  /// Returns studio-master resolution artwork URL (up to 800x800 / maxresdefault) for pristine player and AMOLED displays
  String? get highResThumbnailUrl => upgradeThumbnail(resolvedThumbnailUrl, size: 800, quality: 95);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'thumbnailUrl': thumbnailUrl,
        'durationSeconds': durationSeconds,
        'animatedArtworkUrl': animatedArtworkUrl,
      };

  factory SongItem.fromJson(Map<String, dynamic> json) => SongItem(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        durationSeconds: json['durationSeconds'] as int?,
        animatedArtworkUrl: json['animatedArtworkUrl'] as String?,
      );

  SongItem copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? thumbnailUrl,
    int? durationSeconds,
    String? animatedArtworkUrl,
  }) {
    return SongItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      animatedArtworkUrl: animatedArtworkUrl ?? this.animatedArtworkUrl,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SongItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}


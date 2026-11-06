class PlaylistItem {
  final String id;
  final String title;
  final String author;
  final String? thumbnailUrl;
  final int? trackCount;
  final bool isCustom;

  const PlaylistItem({
    required this.id,
    required this.title,
    required this.author,
    this.thumbnailUrl,
    this.trackCount,
    this.isCustom = false,
  });

  String get subtitle {
    if (author.toLowerCase() == 'youtube music' ||
        id == 'LM' ||
        id == 'VLLM' ||
        title.toLowerCase() == 'liked music') {
      if (trackCount != null) {
        return '$trackCount songs';
      }
      return 'Playlist';
    }
    if (trackCount != null) {
      return author.isNotEmpty ? '$trackCount songs • $author' : '$trackCount songs';
    }
    return author.isNotEmpty ? author : 'Playlist';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'thumbnailUrl': thumbnailUrl,
        'trackCount': trackCount,
        'isCustom': isCustom,
      };

  factory PlaylistItem.fromJson(Map<String, dynamic> json) => PlaylistItem(
        id: json['id'] as String,
        title: json['title'] as String,
        author: json['author'] as String? ?? 'YouTube Music',
        thumbnailUrl: json['thumbnailUrl'] as String?,
        trackCount: json['trackCount'] as int?,
        isCustom: json['isCustom'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaylistItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}


class AlbumItem {
  final String id;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final String type; // 'Single', 'EP', 'Album'
  final int? year;

  const AlbumItem({
    required this.id,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    this.type = 'Album',
    this.year,
  });

  String get subtitle {
    final yearStr = year != null ? ' • $year' : '';
    return '$type • $artist$yearStr';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'thumbnailUrl': thumbnailUrl,
        'type': type,
        'year': year,
      };

  factory AlbumItem.fromJson(Map<String, dynamic> json) => AlbumItem(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        type: json['type'] as String? ?? 'Album',
        year: json['year'] as int?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlbumItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

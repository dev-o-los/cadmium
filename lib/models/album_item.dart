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
}


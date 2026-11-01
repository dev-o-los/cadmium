class AlbumItem {
  final String id;
  final String title;
  final String artist;
  final String? thumbnailUrl;
  final String type; // 'Single', 'EP', 'Album'
  final int? year;
  final bool isCustom;

  const AlbumItem({
    required this.id,
    required this.title,
    required this.artist,
    this.thumbnailUrl,
    this.type = 'Album',
    this.year,
    this.isCustom = false,
  });

  String get subtitle {
    final yearStr = year != null ? ' • $year' : '';
    return '$type • $artist$yearStr';
  }

  AlbumItem copyWith({
    String? id,
    String? title,
    String? artist,
    String? thumbnailUrl,
    String? type,
    int? year,
    bool? isCustom,
  }) {
    return AlbumItem(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      type: type ?? this.type,
      year: year ?? this.year,
      isCustom: isCustom ?? this.isCustom,
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
      };

  factory AlbumItem.fromJson(Map<String, dynamic> json) => AlbumItem(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        type: json['type'] as String? ?? 'Album',
        year: json['year'] as int?,
        isCustom: json['isCustom'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlbumItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

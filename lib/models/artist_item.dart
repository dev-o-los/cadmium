class ArtistItem {
  final String id;
  final String name;
  final String? thumbnailUrl;
  final String? subscribers;

  const ArtistItem({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    this.subscribers,
  });

  String get subtitle => subscribers?.isNotEmpty == true ? subscribers! : 'Artist';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'thumbnailUrl': thumbnailUrl,
        'subscribers': subscribers,
      };

  factory ArtistItem.fromJson(Map<String, dynamic> json) => ArtistItem(
        id: json['id'] as String,
        name: json['name'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        subscribers: json['subscribers'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtistItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}


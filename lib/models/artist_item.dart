class ArtistItem {
  final String id;
  final String name;
  final String? thumbnailUrl;
  final String? subscribers;
  final bool isCustom;

  const ArtistItem({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    this.subscribers,
    this.isCustom = false,
  });

  String get subtitle =>
      subscribers?.isNotEmpty == true ? subscribers! : 'Artist';

  ArtistItem copyWith({
    String? id,
    String? name,
    String? thumbnailUrl,
    String? subscribers,
    bool? isCustom,
  }) {
    return ArtistItem(
      id: id ?? this.id,
      name: name ?? this.name,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      subscribers: subscribers ?? this.subscribers,
      isCustom: isCustom ?? this.isCustom,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'thumbnailUrl': thumbnailUrl,
        'subscribers': subscribers,
        'isCustom': isCustom,
      };

  factory ArtistItem.fromJson(Map<String, dynamic> json) => ArtistItem(
        id: json['id'] as String,
        name: json['name'] as String,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        subscribers: json['subscribers'] as String?,
        isCustom: json['isCustom'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtistItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

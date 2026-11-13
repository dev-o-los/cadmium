import 'song_item.dart';

class HeroCardItem {
  final String id;
  final String title;
  final String subtitle;
  final String caption;
  final String? imageUrl;
  final int? primaryColor;
  final String? secondaryImageUrl;
  final SongItem? playTrack;
  final String? style; // 'fullBleed', 'artistPortrait', 'similarArtists', 'discoveryStation', 'userStation', 'moodForYou', 'mixWithBadge'
  final List<String> artistAvatars;
  final String? iconType;

  /// Studio-quality HD resolution URL (up to 1024x1024 or maxresdefault) for hero displays
  String? get hdImageUrl {
    if (imageUrl == null || imageUrl!.trim().isEmpty) return null;
    return SongItem.upgradeThumbnail(imageUrl!.trim(), size: 1024, quality: 95);
  }

  const HeroCardItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.caption,
    this.imageUrl,
    this.primaryColor,
    this.secondaryImageUrl,
    this.playTrack,
    this.style,
    this.artistAvatars = const [],
    this.iconType,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'caption': caption,
        'imageUrl': imageUrl,
        'primaryColor': primaryColor,
        'secondaryImageUrl': secondaryImageUrl,
        'playTrack': playTrack?.toJson(),
        'style': style,
        'artistAvatars': artistAvatars,
        'iconType': iconType,
      };

  factory HeroCardItem.fromJson(Map<String, dynamic> json) => HeroCardItem(
        id: json['id'] as String,
        title: json['title'] as String,
        subtitle: json['subtitle'] as String,
        caption: json['caption'] as String,
        imageUrl: json['imageUrl'] as String?,
        primaryColor: json['primaryColor'] as int?,
        secondaryImageUrl: json['secondaryImageUrl'] as String?,
        playTrack: json['playTrack'] != null
            ? SongItem.fromJson(json['playTrack'] as Map<String, dynamic>)
            : null,
        style: json['style'] as String?,
        artistAvatars: (json['artistAvatars'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        iconType: json['iconType'] as String?,
      );
}

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

  const HeroCardItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.caption,
    this.imageUrl,
    this.primaryColor,
    this.secondaryImageUrl,
    this.playTrack,
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
      );
}


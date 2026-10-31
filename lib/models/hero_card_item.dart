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
}


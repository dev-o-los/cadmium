/// Represents a music category, genre, or mood item.
class MusicCategory {
  final String title;
  final int? colorValue;
  final String? iconName;

  const MusicCategory({
    required this.title,
    this.colorValue,
    this.iconName,
  });
}


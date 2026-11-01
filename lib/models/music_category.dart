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

  Map<String, dynamic> toJson() => {
        'title': title,
        'colorValue': colorValue,
        'iconName': iconName,
      };

  factory MusicCategory.fromJson(Map<String, dynamic> json) => MusicCategory(
        title: json['title'] as String,
        colorValue: json['colorValue'] as int?,
        iconName: json['iconName'] as String?,
      );
}


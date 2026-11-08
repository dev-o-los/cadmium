/// Represents a music category, genre, or mood item.
class MusicCategory {
  final String title;
  final int? colorValue;
  final String? iconName;
  final String? params;
  final String? imageUrl;
  final String? subtitle;

  const MusicCategory({
    required this.title,
    this.colorValue,
    this.iconName,
    this.params,
    this.imageUrl,
    this.subtitle,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'colorValue': colorValue,
        'iconName': iconName,
        'params': params,
        'imageUrl': imageUrl,
        'subtitle': subtitle,
      };

  factory MusicCategory.fromJson(Map<String, dynamic> json) => MusicCategory(
        title: json['title'] as String,
        colorValue: json['colorValue'] as int?,
        iconName: json['iconName'] as String?,
        params: json['params'] as String?,
        imageUrl: json['imageUrl'] as String?,
        subtitle: json['subtitle'] as String?,
      );
}


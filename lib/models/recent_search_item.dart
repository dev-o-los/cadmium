/// The type of recent search item saved to user search history.
enum RecentSearchType {
  artist,
  song,
  album,
  playlist,
  video,
  query,
}

/// Represents an item in the user's recent search history.
class RecentSearchItem {
  final String id;
  final String title;
  final String subtitle;
  final String? thumbnailUrl;
  final RecentSearchType type;
  final int timestamp;

  const RecentSearchItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.thumbnailUrl,
    required this.type,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'thumbnailUrl': thumbnailUrl,
        'type': type.name,
        'timestamp': timestamp,
      };

  factory RecentSearchItem.fromJson(Map<String, dynamic> json) {
    return RecentSearchItem(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String?,
      type: RecentSearchType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => RecentSearchType.query,
      ),
      timestamp: json['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecentSearchItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}


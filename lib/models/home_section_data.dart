import 'album_item.dart';
import 'playlist_item.dart';
import 'song_item.dart';
import 'video_item.dart';

/// Layout style of an InnerTube home section matching the BitChord UI/UX.
enum HomeSectionLayout {
  /// 4-item vertical columns with horizontal paging (Recents, Quick picks, Trending, Listen again, etc.)
  songColumns,

  /// Horizontal square cards carousel (Albums & singles, Mixed for you, From the community, etc.)
  squareCards,

  /// 16:9 widescreen video carousel (New music videos, Live performances)
  videoCards,
}

/// Represents a dynamic, real YouTube Music home shelf preserved in authentic order.
class HomeSectionData {
  final String id;
  final String title;
  final String? subtitle;
  final HomeSectionLayout layout;
  final List<SongItem> songs;
  final List<AlbumItem> albums;
  final List<PlaylistItem> playlists;
  final List<VideoItem> videos;

  const HomeSectionData({
    required this.id,
    required this.title,
    this.subtitle,
    required this.layout,
    this.songs = const [],
    this.albums = const [],
    this.playlists = const [],
    this.videos = const [],
  });

  bool get isEmpty {
    switch (layout) {
      case HomeSectionLayout.songColumns:
        return songs.isEmpty;
      case HomeSectionLayout.squareCards:
        return albums.isEmpty && playlists.isEmpty;
      case HomeSectionLayout.videoCards:
        return videos.isEmpty;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'layout': layout.name,
        'songs': songs.map((e) => e.toJson()).toList(),
        'albums': albums.map((e) => e.toJson()).toList(),
        'playlists': playlists.map((e) => e.toJson()).toList(),
        'videos': videos.map((e) => e.toJson()).toList(),
      };

  factory HomeSectionData.fromJson(Map<String, dynamic> json) =>
      HomeSectionData(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String?,
        layout: HomeSectionLayout.values.firstWhere(
          (e) => e.name == json['layout'],
          orElse: () => HomeSectionLayout.squareCards,
        ),
        songs: (json['songs'] as List<dynamic>?)
                ?.map((e) => SongItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        albums: (json['albums'] as List<dynamic>?)
                ?.map((e) => AlbumItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        playlists: (json['playlists'] as List<dynamic>?)
                ?.map((e) => PlaylistItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        videos: (json['videos'] as List<dynamic>?)
                ?.map((e) => VideoItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}


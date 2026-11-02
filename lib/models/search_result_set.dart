import 'album_item.dart';
import 'artist_item.dart';
import 'playlist_item.dart';
import 'song_item.dart';
import 'video_item.dart';

/// Bundled multi-category search result set for YouTube Music.
class SearchResultSet {
  final List<SongItem> songs;
  final List<ArtistItem> artists;
  final List<AlbumItem> albums;
  final List<PlaylistItem> playlists;
  final List<VideoItem> videos;

  const SearchResultSet({
    this.songs = const [],
    this.artists = const [],
    this.albums = const [],
    this.playlists = const [],
    this.videos = const [],
  });

  bool get isEmpty =>
      songs.isEmpty &&
      artists.isEmpty &&
      albums.isEmpty &&
      playlists.isEmpty &&
      videos.isEmpty;

  bool get isNotEmpty => !isEmpty;

  int get totalCount =>
      songs.length +
      artists.length +
      albums.length +
      playlists.length +
      videos.length;

  SearchResultSet copyWith({
    List<SongItem>? songs,
    List<ArtistItem>? artists,
    List<AlbumItem>? albums,
    List<PlaylistItem>? playlists,
    List<VideoItem>? videos,
  }) {
    return SearchResultSet(
      songs: songs ?? this.songs,
      artists: artists ?? this.artists,
      albums: albums ?? this.albums,
      playlists: playlists ?? this.playlists,
      videos: videos ?? this.videos,
    );
  }
}


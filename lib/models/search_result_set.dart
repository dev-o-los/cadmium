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

  /// Merges another [SearchResultSet] into this one, deduplicating items by id.
  SearchResultSet merge(SearchResultSet other) {
    final existingSongIds = songs.map((s) => s.id).toSet();
    final newSongs = other.songs.where((s) => !existingSongIds.contains(s.id)).toList();

    final existingArtistIds = artists.map((a) => a.id).toSet();
    final newArtists = other.artists.where((a) => !existingArtistIds.contains(a.id)).toList();

    final existingAlbumIds = albums.map((a) => a.id).toSet();
    final newAlbums = other.albums.where((a) => !existingAlbumIds.contains(a.id)).toList();

    final existingPlaylistIds = playlists.map((p) => p.id).toSet();
    final newPlaylists = other.playlists.where((p) => !existingPlaylistIds.contains(p.id)).toList();

    final existingVideoIds = videos.map((v) => v.id).toSet();
    final newVideos = other.videos.where((v) => !existingVideoIds.contains(v.id)).toList();

    return SearchResultSet(
      songs: [...songs, ...newSongs],
      artists: [...artists, ...newArtists],
      albums: [...albums, ...newAlbums],
      playlists: [...playlists, ...newPlaylists],
      videos: [...videos, ...newVideos],
    );
  }
}


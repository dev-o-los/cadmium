import 'album_item.dart';
import 'artist_item.dart';
import 'playlist_item.dart';
import 'song_item.dart';
import 'video_item.dart';

/// Full artist details model containing comprehensive data from YouTube Music:
/// - Bio, subscriber stats, and monthly audience
/// - Top songs, albums, singles & EPs, videos
/// - Featured playlists, artist playlists, and similar artists
class ArtistDetails {
  final String id;
  final String name;
  final String? bannerUrl;
  final String? thumbnailUrl;
  final String? subscribers;
  final String? monthlyListeners;
  final String? description;
  final List<SongItem> topSongs;
  final List<AlbumItem> albums;
  final List<AlbumItem> singles;
  final List<VideoItem> videos;
  final List<PlaylistItem> featuredOn;
  final List<PlaylistItem> playlistsByArtist;
  final List<ArtistItem> similarArtists;
  final AlbumItem? recentRelease;

  const ArtistDetails({
    required this.id,
    required this.name,
    this.bannerUrl,
    this.thumbnailUrl,
    this.subscribers,
    this.monthlyListeners,
    this.description,
    this.topSongs = const [],
    this.albums = const [],
    this.singles = const [],
    this.videos = const [],
    this.featuredOn = const [],
    this.playlistsByArtist = const [],
    this.similarArtists = const [],
    this.recentRelease,
  });

  ArtistDetails copyWith({
    String? id,
    String? name,
    String? bannerUrl,
    String? thumbnailUrl,
    String? subscribers,
    String? monthlyListeners,
    String? description,
    List<SongItem>? topSongs,
    List<AlbumItem>? albums,
    List<AlbumItem>? singles,
    List<VideoItem>? videos,
    List<PlaylistItem>? featuredOn,
    List<PlaylistItem>? playlistsByArtist,
    List<ArtistItem>? similarArtists,
    AlbumItem? recentRelease,
  }) {
    return ArtistDetails(
      id: id ?? this.id,
      name: name ?? this.name,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      subscribers: subscribers ?? this.subscribers,
      monthlyListeners: monthlyListeners ?? this.monthlyListeners,
      description: description ?? this.description,
      topSongs: topSongs ?? this.topSongs,
      albums: albums ?? this.albums,
      singles: singles ?? this.singles,
      videos: videos ?? this.videos,
      featuredOn: featuredOn ?? this.featuredOn,
      playlistsByArtist: playlistsByArtist ?? this.playlistsByArtist,
      similarArtists: similarArtists ?? this.similarArtists,
      recentRelease: recentRelease ?? this.recentRelease,
    );
  }
}


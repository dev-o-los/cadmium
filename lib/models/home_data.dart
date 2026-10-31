import 'song_item.dart';
import 'music_category.dart';
import 'album_item.dart';
import 'video_item.dart';
import 'hero_card_item.dart';

/// Aggregates all sections displayed on the home page:
/// - Top picks hero cards
/// - Recents / Listen again (4-row column batches)
/// - Find Your Mood
/// - Albums & singles
/// - Music videos (16:9 widescreen)
/// - Quick picks (4-row column batches)
/// - Your daily discover
/// - Trending songs for you
/// - Genres
class HomeData {
  final List<HeroCardItem> heroCards;
  final List<SongItem> recents;
  final List<SongItem> quickPicks;
  final List<MusicCategory> moods;
  final List<MusicCategory> genres;
  final List<AlbumItem> albumsAndSingles;
  final List<VideoItem> musicVideos;
  final List<SongItem> dailyDiscover;
  final List<SongItem> trendingSongs;

  const HomeData({
    required this.heroCards,
    required this.recents,
    required this.quickPicks,
    required this.moods,
    this.genres = const [],
    required this.albumsAndSingles,
    required this.musicVideos,
    required this.dailyDiscover,
    required this.trendingSongs,
  });

  /// Backwards compatibility alias for trendingSongs
  List<SongItem> get trendingTracks => trendingSongs;

  bool get isEmpty =>
      heroCards.isEmpty &&
      recents.isEmpty &&
      quickPicks.isEmpty &&
      moods.isEmpty &&
      genres.isEmpty &&
      albumsAndSingles.isEmpty &&
      musicVideos.isEmpty &&
      dailyDiscover.isEmpty &&
      trendingSongs.isEmpty;
}

import 'song_item.dart';
import 'music_category.dart';

/// Aggregates all sections displayed on the home page:
/// - Trending tracks
/// - Quick picks
/// - Moods & Moments
/// - Genres & Styles
class HomeData {
  final List<SongItem> trendingTracks;
  final List<SongItem> quickPicks;
  final List<MusicCategory> moods;
  final List<MusicCategory> genres;

  const HomeData({
    required this.trendingTracks,
    required this.quickPicks,
    required this.moods,
    required this.genres,
  });

  bool get isEmpty =>
      trendingTracks.isEmpty && quickPicks.isEmpty && moods.isEmpty && genres.isEmpty;
}


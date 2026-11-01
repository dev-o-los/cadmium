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

  Map<String, dynamic> toJson() => {
        'heroCards': heroCards.map((e) => e.toJson()).toList(),
        'recents': recents.map((e) => e.toJson()).toList(),
        'quickPicks': quickPicks.map((e) => e.toJson()).toList(),
        'moods': moods.map((e) => e.toJson()).toList(),
        'genres': genres.map((e) => e.toJson()).toList(),
        'albumsAndSingles': albumsAndSingles.map((e) => e.toJson()).toList(),
        'musicVideos': musicVideos.map((e) => e.toJson()).toList(),
        'dailyDiscover': dailyDiscover.map((e) => e.toJson()).toList(),
        'trendingSongs': trendingSongs.map((e) => e.toJson()).toList(),
      };

  factory HomeData.fromJson(Map<String, dynamic> json) => HomeData(
        heroCards: (json['heroCards'] as List<dynamic>?)
                ?.map((e) => HeroCardItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        recents: (json['recents'] as List<dynamic>?)
                ?.map((e) => SongItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        quickPicks: (json['quickPicks'] as List<dynamic>?)
                ?.map((e) => SongItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        moods: (json['moods'] as List<dynamic>?)
                ?.map((e) => MusicCategory.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        genres: (json['genres'] as List<dynamic>?)
                ?.map((e) => MusicCategory.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        albumsAndSingles: (json['albumsAndSingles'] as List<dynamic>?)
                ?.map((e) => AlbumItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        musicVideos: (json['musicVideos'] as List<dynamic>?)
                ?.map((e) => VideoItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        dailyDiscover: (json['dailyDiscover'] as List<dynamic>?)
                ?.map((e) => SongItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        trendingSongs: (json['trendingSongs'] as List<dynamic>?)
                ?.map((e) => SongItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

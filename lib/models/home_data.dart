import 'song_item.dart';
import 'music_category.dart';
import 'album_item.dart';
import 'video_item.dart';
import 'hero_card_item.dart';
import 'playlist_item.dart';
import 'artist_item.dart';
import 'home_section_data.dart';

export 'home_section_data.dart';

/// Aggregates all sections displayed on the home page, covering both the
/// unauthenticated raw feed and the full personalized authenticated experience:
///
/// **Core sections (always shown):**
/// - Top picks hero cards (personalized ordering when logged in)
/// - Recents / Listen again (4-row column batches)
/// - Find Your Mood
/// - Albums & singles (new from followed artists first when logged in)
/// - Music videos you'll watch (16:9 widescreen)
/// - Quick picks (4-row column batches)
/// - Your daily discover
/// - Trending songs for you
///
/// **Dynamic sections:** Real, ordered shelves from YouTube Music InnerTube feed.
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

  // ── Dynamic live shelves from YouTube Music ────────────────────────────
  final List<HomeSectionData> dynamicSections;

  // ── Personalized-only fields (empty when not logged in) ──────────────────
  /// Featured editorial / algorithmic playlists curated for this user.
  final List<PlaylistItem> featuredPlaylists;

  /// "Mixed for You" Supermix playlists generated from user's taste.
  final List<PlaylistItem> mixedForYou;

  /// Personal mixes: My Mix 1, My Super Mix, My Mix 2, etc.
  final List<PlaylistItem> myMixes;

  /// New albums / singles released by artists the user follows.
  final List<AlbumItem> followedArtistNewReleases;

  /// Artists featured in "Featuring [Artist] & Similar Artists" shelves, with images.
  final List<ArtistItem> featuredArtists;

  /// The user's personal radio station (e.g. "Utkarsh's Station").
  final PlaylistItem? userStation;

  /// "New Release Mix" playlist — new releases matching the user's taste.
  final PlaylistItem? newReleaseMix;

  /// The lead track of the "Discovery Station / Made for You" shelf.
  final SongItem? discoveryStation;

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
    // Dynamic shelves
    this.dynamicSections = const [],
    // Personalized
    this.featuredPlaylists = const [],
    this.mixedForYou = const [],
    this.myMixes = const [],
    this.followedArtistNewReleases = const [],
    this.featuredArtists = const [],
    this.userStation,
    this.newReleaseMix,
    this.discoveryStation,
  });

  /// Whether any personalized data was fetched for this home feed.
  bool get isPersonalized =>
      dynamicSections.isNotEmpty ||
      featuredPlaylists.isNotEmpty ||
      mixedForYou.isNotEmpty ||
      myMixes.isNotEmpty ||
      followedArtistNewReleases.isNotEmpty ||
      featuredArtists.isNotEmpty ||
      userStation != null ||
      newReleaseMix != null ||
      discoveryStation != null;

  /// Backwards compatibility alias for trendingSongs
  List<SongItem> get trendingTracks => trendingSongs;

  bool get isEmpty =>
      heroCards.isEmpty &&
      dynamicSections.isEmpty &&
      recents.isEmpty &&
      quickPicks.isEmpty &&
      moods.isEmpty &&
      genres.isEmpty &&
      albumsAndSingles.isEmpty &&
      musicVideos.isEmpty &&
      dailyDiscover.isEmpty &&
      trendingSongs.isEmpty &&
      featuredPlaylists.isEmpty &&
      mixedForYou.isEmpty &&
      myMixes.isEmpty;

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
        'dynamicSections': dynamicSections.map((e) => e.toJson()).toList(),
        // Personalized
        'featuredPlaylists': featuredPlaylists.map((e) => e.toJson()).toList(),
        'mixedForYou': mixedForYou.map((e) => e.toJson()).toList(),
        'myMixes': myMixes.map((e) => e.toJson()).toList(),
        'followedArtistNewReleases':
            followedArtistNewReleases.map((e) => e.toJson()).toList(),
        'featuredArtists': featuredArtists.map((e) => e.toJson()).toList(),
        'userStation': userStation?.toJson(),
        'newReleaseMix': newReleaseMix?.toJson(),
        'discoveryStation': discoveryStation?.toJson(),
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
        dynamicSections: (json['dynamicSections'] as List<dynamic>?)
                ?.map(
                  (e) => HomeSectionData.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            const [],
        // Personalized
        featuredPlaylists: (json['featuredPlaylists'] as List<dynamic>?)
                ?.map((e) => PlaylistItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        mixedForYou: (json['mixedForYou'] as List<dynamic>?)
                ?.map((e) => PlaylistItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        myMixes: (json['myMixes'] as List<dynamic>?)
                ?.map((e) => PlaylistItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        followedArtistNewReleases:
            (json['followedArtistNewReleases'] as List<dynamic>?)
                    ?.map(
                      (e) => AlbumItem.fromJson(e as Map<String, dynamic>),
                    )
                    .toList() ??
                const [],
        featuredArtists: (json['featuredArtists'] as List<dynamic>?)
                ?.map((e) => ArtistItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        userStation: json['userStation'] != null
            ? PlaylistItem.fromJson(
                json['userStation'] as Map<String, dynamic>,
              )
            : null,
        newReleaseMix: json['newReleaseMix'] != null
            ? PlaylistItem.fromJson(
                json['newReleaseMix'] as Map<String, dynamic>,
              )
            : null,
        discoveryStation: json['discoveryStation'] != null
            ? SongItem.fromJson(
                json['discoveryStation'] as Map<String, dynamic>,
              )
            : null,
      );
}

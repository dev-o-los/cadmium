import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/album_item.dart';
import '../models/hero_card_item.dart';
import '../models/home_data.dart';
import '../models/music_category.dart';
import '../models/song_item.dart';
import '../models/video_item.dart';
import '../providers/auth_provider.dart';
import '../providers/home_data_provider.dart';
import '../providers/player_provider.dart';
import '../utils/playback_utils.dart';
import '../widgets/account_modal_sheet.dart';
import '../widgets/animated_cupertino_icon.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/dynamic_album_artwork.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/wavify_cached_image.dart';
import '../widgets/wavify_logo.dart';
import 'google_signin_screen.dart';

/// The Home Feed Tab screen featuring YouTube Music personalized top picks,
/// recents, mood cards, albums & singles, music videos, quick picks, and discover carousels.
class HomeFeedScreen extends ConsumerWidget {
  final ValueChanged<int>? onNavigateToTab;
  final ValueChanged<String>? onSearch;

  const HomeFeedScreen({
    super.key,
    this.onNavigateToTab,
    this.onSearch,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeDataAsync = ref.watch(homeDataProvider);

    return homeDataAsync.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Loading music...',
              style: TextStyle(color: AppColors.appleSecondaryText, fontSize: 14),
            ),
          ],
        ),
      ),
      error: (err, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_circle,
                size: 52,
                color: AppColors.appleRed,
              ),
              const SizedBox(height: 12),
              Text(
                'Failed to load music: $err',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => ref.read(homeDataProvider.notifier).refresh(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.appleDarkSurfaceHigh,
                ),
                child: const Text(
                  'Try Again',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
      data: (data) => _buildHomeContent(context, ref, data),
    );
  }

  Widget _buildHomeContent(BuildContext context, WidgetRef ref, HomeData data) {
    final playerState = ref.watch(playerProvider);

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: AppColors.appleDarkSurface,
      onRefresh: () => ref.read(homeDataProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 160),
        children: [
          // Top Header: Melomaniac Logo & Wordmark on Left + Profile Avatar on Right
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Redesigned Melomaniac logo & brand title with balanced distancing
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    MelomaniacLogo(size: 28, color: Colors.white),
                    SizedBox(width: 10),
                    Text(
                      'Melomaniac',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ],
                ),

                // Interactive Top Right Google / YouTube Music Profile Button
                Consumer(
                  builder: (context, ref, child) {
                    final account = ref.watch(authProvider);

                    return ApplePressable(
                      onTap: () {
                        if (account != null) {
                          showAccountModalSheet(context, ref);
                        } else {
                          // Directly open the Google Sign-In WebView on click
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const GoogleSignInScreen(),
                            ),
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(22),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: account != null
                                    ? AppColors.appleRed.withValues(alpha: 0.85)
                                    : Colors.white.withValues(alpha: 0.5),
                                width: 1.5,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: account != null
                                  ? AppColors.appleRed
                                  : AppColors.appleDarkSurfaceHigh,
                              backgroundImage: account?.avatarUrl != null
                                  ? NetworkImage(account!.avatarUrl!)
                                  : null,
                              child: account?.avatarUrl == null
                                  ? account != null
                                      ? Text(
                                          account.initials,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : const Icon(
                                          CupertinoIcons.person_crop_circle_fill,
                                          color: Colors.white,
                                          size: 24,
                                        )
                                  : null,
                            ),
                          ),
                          // Connected status dot indicator
                          if (account != null)
                            Positioned(
                              right: -1,
                              bottom: -1,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.black,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Section 1: "Top Picks for You" Hero Cards Carousel
          _buildTopPicksHeroSection(context, ref, data.heroCards),
          const SizedBox(height: 28),

          // Section 2: "Recents" (4-item vertical column horizontal paging)
          _build4ItemColumnsSection(
            context: context,
            ref: ref,
            title: 'Recents',
            songs: data.recents,
          ),
          const SizedBox(height: 28),

          // Section 3: "Find Your Mood" with "Show all"
          _buildFindYourMoodSection(context, data.moods),
          const SizedBox(height: 28),

          // Section 4: "Albums & singles"
          _buildAlbumsAndSinglesSection(context, ref, data.albumsAndSingles),
          const SizedBox(height: 28),

          // Section 5: "Music videos" (16:9 widescreen)
          _buildMusicVideosSection(context, ref, data.musicVideos),
          const SizedBox(height: 28),

          // Section 6: "Listen again" (listening history from playerProvider)
          if (playerState.recentlyPlayed.isNotEmpty) ...[
            _build4ItemColumnsSection(
              context: context,
              ref: ref,
              title: 'Listen again',
              subtitle: 'UTKARSH',
              songs: playerState.recentlyPlayed,
            ),
            const SizedBox(height: 28),
          ],

          // Section 7: "Quick picks" (4-item vertical column horizontal paging)
          _build4ItemColumnsSection(
            context: context,
            ref: ref,
            title: 'Quick picks',
            songs: data.quickPicks,
          ),
          const SizedBox(height: 28),

          // Section 8: "Your daily discover"
          _buildHorizontalSongCarousel(
            context: context,
            ref: ref,
            title: 'Your daily discover',
            songs: data.dailyDiscover,
          ),
          const SizedBox(height: 28),

          // Section 9: "Trending songs for you"
          _buildHorizontalSongCarousel(
            context: context,
            ref: ref,
            title: 'Trending songs for you',
            songs: data.trendingSongs,
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // HOME SCREEN SECTION WIDGETS
  // =========================================================================

  /// Top Picks Hero Section
  Widget _buildTopPicksHeroSection(
    BuildContext context,
    WidgetRef ref,
    List<HeroCardItem> heroCards,
  ) {
    if (heroCards.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Top Picks for You',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.6,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 290,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: heroCards.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final hero = heroCards[index];
              return _buildHeroCard(context, ref, hero);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeroCard(
    BuildContext context,
    WidgetRef ref,
    HeroCardItem hero,
  ) {
    final isShubhCard = hero.id.contains('shubh');

    return ApplePressable(
      onTap: () {
        if (hero.playTrack != null) {
          playSong(context, ref, hero.playTrack!, forceReload: true);
        } else {
          playHero(context, ref, hero);
        }
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 236,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: Color(hero.primaryColor ?? 0xFF1C1C1E),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              // Background Image or Solid/Gradient fill
              if (hero.imageUrl != null && !isShubhCard)
                Positioned.fill(
                  child: WavifyCachedImage(
                    imageUrl: hero.imageUrl!,
                    songId: hero.playTrack?.id,
                    fit: BoxFit.cover,
                    errorWidget: Container(
                      color: Color(hero.primaryColor ?? 0xFF2A2825),
                    ),
                  ),
                )
              else if (isShubhCard)
                // Shubh & Similar vibrant blue card with circular portraits
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF2575FC),
                          Color(0xFF1D64F2),
                          Color(0xFF0D47A1),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: 40,
                          left: 36,
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 2,
                              ),
                              image: hero.imageUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(hero.imageUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                              color: const Color(0xFF333333),
                            ),
                            child: hero.imageUrl == null
                                ? const Icon(
                                    CupertinoIcons.person_crop_circle,
                                    color: Colors.white70,
                                    size: 50,
                                  )
                                : null,
                          ),
                        ),
                        Positioned(
                          top: 110,
                          right: 28,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 2,
                              ),
                              color: const Color(0xFF222222),
                            ),
                            child: const Icon(
                              CupertinoIcons.person_crop_circle,
                              color: Colors.white70,
                              size: 40,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Gradient shading overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.92),
                      ],
                      stops: const [0.35, 0.65, 1.0],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),

              // Bottom card typography
              Positioned(
                left: 14,
                right: 14,
                bottom: 16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hero.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hero.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hero.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 4-Item Vertical Column with Horizontal Swiping (Recents / Quick picks / Listen again)
  Widget _build4ItemColumnsSection({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    String? subtitle,
    required List<SongItem> songs,
  }) {
    if (songs.isEmpty) return const SizedBox.shrink();

    // Chunk songs into lists of 4
    final chunked = <List<SongItem>>[];
    for (var i = 0; i < songs.length; i += 4) {
      final end = (i + 4 < songs.length) ? i + 4 : songs.length;
      chunked.add(songs.sublist(i, end));
    }

    // Responsively calculate height based on the maximum number of items in any column
    final maxPerColumn = chunked.fold<int>(
      0,
      (prev, col) => col.length > prev ? col.length : prev,
    );
    const rowHeight = 64.0;
    final totalHeight = maxPerColumn * rowHeight;

    final screenWidth = MediaQuery.of(context).size.width;
    final columnWidth = (screenWidth * 0.86).clamp(280.0, 440.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.6,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.appleSecondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: totalHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: chunked.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, columnIndex) {
              final columnSongs = chunked[columnIndex];
              return SizedBox(
                width: columnWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: columnSongs
                      .map((song) => _build4ItemRow(context, ref, song, contextQueue: songs))
                      .toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _build4ItemRow(
    BuildContext context,
    WidgetRef ref,
    SongItem song, {
    List<SongItem>? contextQueue,
  }) {
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isSelected = currentSong?.id == song.id;

    return SizedBox(
      height: 64,
      child: ApplePressable(
        onTap: () => playSong(context, ref, song, contextQueue: contextQueue, forceReload: true),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              // Artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: song.thumbnailUrl != null
                    ? WavifyCachedImage(
                        imageUrl: song.thumbnailUrl!,
                        songId: song.id,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorWidget: _fallbackSquareArt(),
                      )
                    : _fallbackSquareArt(),
              ),
              const SizedBox(width: 12),

              // Title & Artist
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isSelected ? AppColors.appleRed : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    ApplePressable(
                      onTap: () => openArtistScreen(context, artistName: song.artist),
                      child: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.appleSecondaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 3-dots Menu Icon
              IconButton(
                icon: const AnimatedCupertinoIcon(
                  icon: CupertinoIcons.ellipsis_vertical,
                  color: AppColors.appleSecondaryText,
                  size: 18,
                ),
                onPressed: () => showTrackOptionsModal(context, ref, song),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Find Your Mood Section with Line-Art Icons & 3-Wave Logo
  Widget _buildFindYourMoodSection(BuildContext context, List<MusicCategory> moods) {
    final moodDefs = [
      (title: 'Energy', color: const Color(0xFF00D26A), icon: 'lightning'),
      (title: 'Relax', color: const Color(0xFF3FA9F5), icon: 'zen'),
      (title: 'Feeling Blue', color: const Color(0xFF2B4CDE), icon: 'vortex'),
      (title: 'Workout', color: const Color(0xFFFF453A), icon: 'workout'),
      (title: 'Focus', color: const Color(0xFF5E5CE6), icon: 'focus'),
      (title: 'Party', color: const Color(0xFFAF52DE), icon: 'party'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Find Your Mood',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.6,
                ),
              ),
              GestureDetector(
                onTap: () {
                  onNavigateToTab?.call(1); // Switch to Explore Tab
                },
                child: const Text(
                  'Show all',
                  style: TextStyle(
                    color: AppColors.appleSecondaryText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 175,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: moodDefs.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final mood = moodDefs[index];
              return ApplePressable(
                onTap: () {
                  onSearch?.call(mood.title);
                },
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 136,
                      height: 136,
                      decoration: BoxDecoration(
                        color: mood.color,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Stack(
                        children: [
                          const Positioned(
                            top: 10,
                            right: 10,
                            child: WavifyLogo(size: 16, color: Colors.white70),
                          ),
                          Center(child: _buildMoodIcon(mood.icon)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      mood.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMoodIcon(String iconType) {
    switch (iconType) {
      case 'lightning':
        return const Icon(CupertinoIcons.bolt_fill, size: 58, color: Colors.white);
      case 'zen':
        return const ZenStonesIcon(size: 56, color: Colors.white);
      case 'vortex':
        return const VortexRingsIcon(size: 56, color: Colors.white);
      case 'workout':
        return const Icon(
          CupertinoIcons.flame_fill,
          size: 48,
          color: Colors.white,
        );
      case 'focus':
        return const Icon(
          CupertinoIcons.scope,
          size: 48,
          color: Colors.white,
        );
      case 'party':
        return const Icon(
          CupertinoIcons.sparkles,
          size: 48,
          color: Colors.white,
        );
      default:
        return const Icon(
          CupertinoIcons.music_note,
          size: 48,
          color: Colors.white,
        );
    }
  }

  /// Albums & Singles Horizontal Carousel
  Widget _buildAlbumsAndSinglesSection(
    BuildContext context,
    WidgetRef ref,
    List<AlbumItem> albums,
  ) {
    if (albums.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.38).clamp(136.0, 180.0);
    final cardHeight = cardWidth + 58.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Albums & singles',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.6,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: albums.length > 15 ? 15 : albums.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final album = albums[index];
              return ApplePressable(
                onTap: () => openAlbumScreen(context, album),
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: cardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: DynamicAlbumArtwork(
                          album: album,
                          size: cardWidth,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        album.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.appleSecondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 16:9 Music Videos Widescreen Carousel
  Widget _buildMusicVideosSection(
    BuildContext context,
    WidgetRef ref,
    List<VideoItem> videos,
  ) {
    if (videos.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final videoWidth = (screenWidth * 0.65).clamp(220.0, 320.0);
    final videoThumbnailHeight = videoWidth * (9 / 16);
    final videoCardHeight = videoThumbnailHeight + 58.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Music videos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.6,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: videoCardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: videos.length > 10 ? 10 : videos.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final video = videos[index];
              return ApplePressable(
                onTap: () {
                  playSong(
                    context,
                    ref,
                    SongItem(
                      id: video.id,
                      title: video.title,
                      artist: video.artist,
                      thumbnailUrl: video.thumbnailUrl,
                      durationSeconds: video.durationSeconds,
                    ),
                    forceReload: true,
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: videoWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          children: [
                            video.thumbnailUrl != null
                                ? WavifyCachedImage(
                                    imageUrl: video.thumbnailUrl!,
                                    songId: video.id,
                                    width: videoWidth,
                                    height: videoThumbnailHeight,
                                    fit: BoxFit.cover,
                                    errorWidget: Container(
                                      width: videoWidth,
                                      height: videoThumbnailHeight,
                                      color: AppColors.appleDarkSurfaceHigh,
                                      child: const Icon(
                                        CupertinoIcons.play_rectangle_fill,
                                        color: Colors.white24,
                                        size: 40,
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: videoWidth,
                                    height: videoThumbnailHeight,
                                    color: AppColors.appleDarkSurfaceHigh,
                                    child: const Icon(
                                      CupertinoIcons.play_rectangle_fill,
                                      color: Colors.white24,
                                      size: 40,
                                    ),
                                  ),
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  CupertinoIcons.play_fill,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        video.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        video.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.appleSecondaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Generic Horizontal Song Carousel
  Widget _buildHorizontalSongCarousel({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    required List<SongItem> songs,
  }) {
    if (songs.isEmpty) return const SizedBox.shrink();

    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.38).clamp(136.0, 180.0);
    final cardHeight = cardWidth + 58.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.6,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: songs.length > 12 ? 12 : songs.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final song = songs[index];
              final isCurrent = currentSong?.id == song.id;

              return ApplePressable(
                onTap: () => playSong(context, ref, song, contextQueue: songs, forceReload: true),
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: cardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: song.thumbnailUrl != null
                                ? WavifyCachedImage(
                                    imageUrl: song.thumbnailUrl!,
                                    songId: song.id,
                                    width: cardWidth,
                                    height: cardWidth,
                                    fit: BoxFit.cover,
                                    errorWidget: _fallbackSquareArt(size: cardWidth),
                                  )
                                : _fallbackSquareArt(size: cardWidth),
                          ),
                          if (isCurrent)
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: AppColors.appleRed,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(6),
                                child: const Icon(
                                  CupertinoIcons.waveform,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrent ? AppColors.appleRed : Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      ApplePressable(
                        onTap: () => openArtistScreen(context, artistName: song.artist),
                        child: Text(
                          song.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.appleSecondaryText,
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _fallbackSquareArt({
    double size = 48,
    IconData icon = CupertinoIcons.music_note,
  }) {
    return Container(
      width: size,
      height: size,
      color: AppColors.appleDarkSurfaceHigh,
      child: Icon(
        icon,
        color: Colors.white30,
        size: (size * 0.5).clamp(20.0, 48.0),
      ),
    );
  }
}


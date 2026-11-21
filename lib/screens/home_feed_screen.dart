import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../constants/apple_typography.dart';
import '../models/album_item.dart';
import '../models/artist_item.dart';
import '../models/hero_card_item.dart';
import '../models/home_data.dart';
import '../models/music_category.dart';
import '../models/playlist_item.dart';
import '../models/song_item.dart';
import '../models/video_item.dart';
import '../providers/home_data_provider.dart';
import '../providers/player_provider.dart';
import '../utils/playback_utils.dart';
import '../widgets/animated_cupertino_icon.dart';
import '../widgets/animated_equalizer_bars.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/dynamic_album_artwork.dart';
import '../widgets/top_status_bar_blur.dart';
import '../widgets/app_shimmer.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/wavify_cached_image.dart';
import '../widgets/wavify_logo.dart';

/// The Home Feed Tab screen featuring YouTube Music personalized top picks,
/// recents, mood cards, albums & singles, music videos, quick picks, and discover carousels.
class HomeFeedScreen extends ConsumerStatefulWidget {
  final ValueChanged<int>? onNavigateToTab;
  final ValueChanged<String>? onSearch;

  const HomeFeedScreen({super.key, this.onNavigateToTab, this.onSearch});

  @override
  ConsumerState<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends ConsumerState<HomeFeedScreen> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final homeDataAsync = ref.watch(homeDataProvider);
    final homeData = homeDataAsync.valueOrNull;

    // Seamless stale-while-revalidate: keep rendering existing content while refreshing in background
    if (homeData != null && !homeData.isEmpty) {
      return _buildHomeContent(context, ref, homeData);
    }

    if (homeDataAsync.isLoading) {
      return const HomeScreenSkeleton();
    }

    if (homeDataAsync.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_circle,
                size: 52,
                color: Colors.white70,
              ),
              const SizedBox(height: 12),
              Text(
                'Failed to load music: ${homeDataAsync.error}',
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
      );
    }

    return const HomeScreenSkeleton();
  }

  Widget _buildHomeContent(BuildContext context, WidgetRef ref, HomeData data) {
    final recentlyPlayed = ref.watch(
      playerProvider.select((s) => s.recentlyPlayed),
    );
    final topPadding = MediaQuery.of(context).padding.top;

    // Filter out any "Liked Music" that might appear in hero cards
    final cleanHeroCards = data.heroCards.where((c) {
      final t = c.title.toLowerCase();
      final s = c.subtitle.toLowerCase();
      final cap = c.caption.toLowerCase();
      return !t.contains('liked music') &&
          !t.contains('your likes') &&
          !s.contains('liked music') &&
          !cap.contains('liked music');
    }).toList();

    // Prepare authentic Recents: whatever we listen to on music should immediately be in recents at top,
    // merged with remote recents or quickPicks fallback
    final effectiveRecents = <SongItem>[
      ...recentlyPlayed,
      ...data.recents.where((r) => !recentlyPlayed.any((p) => p.id == r.id)),
    ];
    if (effectiveRecents.isEmpty) {
      effectiveRecents.addAll(data.quickPicks.take(8));
    }

    final sectionBuilders = <WidgetBuilder>[
      // Scrollable Brand Logo Header
      (context) => const Padding(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: CadmiumLogo(size: 56),
        ),
      ),

      // Section 1: "Top Picks for You" Hero Cards Carousel (No liked music)
      (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopPicksHeroSection(context, ref, cleanHeroCards),
          const SizedBox(height: AppleSpacing.sectionSpacing),
        ],
      ),

      // Section 2: "Recents" (Always directly below Top Picks for You)
      if (effectiveRecents.isNotEmpty)
        (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _build4ItemColumnsSection(
              context: context,
              ref: ref,
              title: 'Recents',
              songs: effectiveRecents,
            ),
            const SizedBox(height: AppleSpacing.sectionSpacing),
          ],
        ),

      // Section 3: "Find Your Mood"
      (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFindYourMoodSection(context, data.moods),
          const SizedBox(height: AppleSpacing.sectionSpacing),
        ],
      ),
    ];

    if (data.dynamicSections.isNotEmpty) {
      for (final section in data.dynamicSections) {
        if (section.isEmpty) continue;

        // Skip duplicate recents / listen again since we rendered it directly below Top Picks
        final sTitleLower = section.title.trim().toLowerCase();
        if ((sTitleLower == 'recents' || sTitleLower == 'listen again') &&
            effectiveRecents.isNotEmpty) {
          continue;
        }

        switch (section.layout) {
          case HomeSectionLayout.songColumns:
            sectionBuilders.add(
              (context) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _build4ItemColumnsSection(
                    context: context,
                    ref: ref,
                    title: section.title,
                    subtitle: section.subtitle,
                    songs: section.songs,
                  ),
                  const SizedBox(height: AppleSpacing.sectionSpacing),
                ],
              ),
            );
            break;

          case HomeSectionLayout.squareCards:
            sectionBuilders.add(
              (context) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSquareCardsSection(
                    context: context,
                    ref: ref,
                    title: section.title,
                    subtitle: section.subtitle,
                    albums: section.albums,
                    playlists: section.playlists,
                  ),
                  const SizedBox(height: AppleSpacing.sectionSpacing),
                ],
              ),
            );
            break;

          case HomeSectionLayout.videoCards:
            sectionBuilders.add(
              (context) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMusicVideosSection(
                    context,
                    ref,
                    section.videos,
                    title: section.title,
                    subtitle: section.subtitle,
                  ),
                  const SizedBox(height: AppleSpacing.sectionSpacing),
                ],
              ),
            );
            break;
        }
      }

      // Check for any core sections not covered in dynamicSections so ALL sections always load
      final hasAlbumsShelf = data.dynamicSections.any(
        (s) => s.albums.isNotEmpty,
      );
      final hasVideosShelf = data.dynamicSections.any(
        (s) => s.layout == HomeSectionLayout.videoCards || s.videos.isNotEmpty,
      );
      final hasQuickPicksShelf = data.dynamicSections.any(
        (s) => s.title.toLowerCase().contains('quick pick'),
      );
      final hasDiscoverShelf = data.dynamicSections.any(
        (s) => s.title.toLowerCase().contains('discover'),
      );
      final hasTrendingShelf = data.dynamicSections.any(
        (s) =>
            s.title.toLowerCase().contains('trend') ||
            s.title.toLowerCase().contains('chart'),
      );

      if (data.albumsAndSingles.isNotEmpty && !hasAlbumsShelf) {
        sectionBuilders.add(
          (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAlbumsAndSinglesSection(
                context,
                ref,
                data.albumsAndSingles,
              ),
              const SizedBox(height: AppleSpacing.sectionSpacing),
            ],
          ),
        );
      }
      if (data.musicVideos.isNotEmpty && !hasVideosShelf) {
        sectionBuilders.add(
          (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMusicVideosSection(context, ref, data.musicVideos),
              const SizedBox(height: AppleSpacing.sectionSpacing),
            ],
          ),
        );
      }
      if (data.quickPicks.isNotEmpty && !hasQuickPicksShelf) {
        sectionBuilders.add(
          (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _build4ItemColumnsSection(
                context: context,
                ref: ref,
                title: 'Quick picks',
                songs: data.quickPicks,
              ),
              const SizedBox(height: AppleSpacing.sectionSpacing),
            ],
          ),
        );
      }
      if (data.dailyDiscover.isNotEmpty && !hasDiscoverShelf) {
        sectionBuilders.add(
          (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHorizontalSongCarousel(
                context: context,
                ref: ref,
                title: 'Your daily discover',
                songs: data.dailyDiscover,
              ),
              const SizedBox(height: AppleSpacing.sectionSpacing),
            ],
          ),
        );
      }
      if (data.trendingSongs.isNotEmpty && !hasTrendingShelf) {
        sectionBuilders.add(
          (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHorizontalSongCarousel(
                context: context,
                ref: ref,
                title: 'Trending songs for you',
                songs: data.trendingSongs,
              ),
              const SizedBox(height: AppleSpacing.sectionSpacing),
            ],
          ),
        );
      }
    } else {
      // Fallback layout (offline, unauthenticated, tests)
      sectionBuilders.addAll([
        (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAlbumsAndSinglesSection(context, ref, data.albumsAndSingles),
            const SizedBox(height: AppleSpacing.sectionSpacing),
          ],
        ),
        (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMusicVideosSection(context, ref, data.musicVideos),
            const SizedBox(height: AppleSpacing.sectionSpacing),
          ],
        ),
        (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _build4ItemColumnsSection(
              context: context,
              ref: ref,
              title: 'Quick picks',
              songs: data.quickPicks,
            ),
            const SizedBox(height: AppleSpacing.sectionSpacing),
          ],
        ),
        if (data.mixedForYou.isNotEmpty)
          (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPlaylistCarousel(
                context: context,
                ref: ref,
                title: 'Mixed for You',
                playlists: data.mixedForYou,
              ),
              const SizedBox(height: AppleSpacing.sectionSpacing),
            ],
          ),
        if (data.myMixes.isNotEmpty)
          (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPlaylistCarousel(
                context: context,
                ref: ref,
                title: 'Your Mixes',
                playlists: data.myMixes,
              ),
              const SizedBox(height: AppleSpacing.sectionSpacing),
            ],
          ),
        if (data.featuredPlaylists.isNotEmpty)
          (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPlaylistCarousel(
                context: context,
                ref: ref,
                title: 'Featured Playlists',
                playlists: data.featuredPlaylists,
              ),
              const SizedBox(height: AppleSpacing.sectionSpacing),
            ],
          ),
        if (data.featuredArtists.isNotEmpty)
          (context) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFeaturedArtistsSection(context, ref, data.featuredArtists),
              const SizedBox(height: AppleSpacing.sectionSpacing),
            ],
          ),
        (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHorizontalSongCarousel(
              context: context,
              ref: ref,
              title: 'Your daily discover',
              songs: data.dailyDiscover,
            ),
            const SizedBox(height: AppleSpacing.sectionSpacing),
          ],
        ),
        (context) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHorizontalSongCarousel(
              context: context,
              ref: ref,
              title: 'Trending songs for you',
              songs: data.trendingSongs,
            ),
            const SizedBox(height: AppleSpacing.sectionSpacing),
          ],
        ),
      ]);
    }

    return Stack(
      children: [
        // 1. Scrollable Feed Body (extends edge-to-edge beyond the notification/battery bar)
        RefreshIndicator(
          color: Colors.white,
          backgroundColor: AppColors.appleDarkSurface,
          onRefresh: () => ref.read(homeDataProvider.notifier).refresh(),
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(0, topPadding + 6, 0, 160),
            itemCount: sectionBuilders.length,
            itemBuilder: (context, index) {
              return RepaintBoundary(child: sectionBuilders[index](context));
            },
          ),
        ),

        // 2. Subtle Top Status Bar Dissolve on Scroll
        TopStatusBarBlur(scrollController: _scrollController),
      ],
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

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.58).clamp(215.0, 240.0);
    const cardHeight = 305.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppleSpacing.horizontalPadding,
          ),
          child: Text('Top Picks for You', style: AppleTypography.sectionTitle),
        ),
        const SizedBox(height: AppleSpacing.sectionHeaderToContent),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: heroCards.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final hero = heroCards[index];
              return _buildHeroCard(context, ref, hero, cardWidth, cardHeight);
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
    double cardWidth,
    double cardHeight,
  ) {
    return RepaintBoundary(
      child: ApplePressable(
        onTap: () {
          if (hero.album != null) {
            final isSingle = hero.album!.type.toLowerCase() == 'single';
            if (isSingle && hero.playTrack != null) {
              playSong(
                context,
                ref,
                hero.playTrack!,
                forceReload: true,
                autoOpenPlayer: true,
              );
            } else {
              openAlbumScreen(context, hero.album!);
            }
          } else if (hero.artist != null) {
            openArtistScreen(
              context,
              artistId: hero.artist!.id,
              artistName: hero.artist!.name,
              thumbnailUrl: hero.artist!.thumbnailUrl,
            );
          } else if (hero.playlist != null) {
            openPlaylistScreen(context, ref, hero.playlist!);
          } else if (hero.playTrack != null) {
            playSong(
              context,
              ref,
              hero.playTrack!,
              forceReload: true,
              autoOpenPlayer: true,
            );
          } else {
            playHero(context, ref, hero);
          }
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: cardWidth,
          height: cardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: const Color(0xFF141414),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
              width: 0.8,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Dynamic Hero Background tailored to specific card style
                _buildHeroBackground(context, hero, cardWidth, cardHeight),

                // 2. Mix Badge on top-left for New Release Mix (Image 2)
                if (hero.style == 'mixWithBadge')
                  Positioned(
                    top: 14,
                    left: 14,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 0.8,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          CupertinoIcons.play_fill,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                  ),

                // 3. Signature 3-Wave Wavify Logo on top-right (Image 1, 3, 4)
                if (hero.style != 'mixWithBadge')
                  const Positioned(
                    top: 14,
                    right: 14,
                    child: WavifyLogo(size: 20),
                  ),

                // 4. Light frosted bottom blur (seamlessly starts without any straight line, lighter tint)
                // When it's a solid colour (similarArtists, userStation, discoveryStation, moodForYou):
                // NO blur! Solid colour remains intact with crisp white text.
                if (hero.style == 'fullBleed' ||
                    (hero.style != 'mixWithBadge' &&
                        hero.style != 'similarArtists' &&
                        hero.style != 'userStation' &&
                        hero.style != 'discoveryStation' &&
                        hero.style != 'moodForYou' &&
                        (hero.hdImageUrl != null || hero.imageUrl != null)))
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: cardHeight * 0.42,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(18),
                      ),
                      child: ShaderMask(
                        shaderCallback: (bounds) {
                          return const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Color(0x08000000), // near-invisible start
                              Color(0x28000000), // very faint
                              Color(0x72000000), // building
                              Colors.black,      // fully visible at base
                            ],
                            stops: [0.0, 0.25, 0.48, 0.72, 1.0],
                          ).createShader(bounds);
                        },
                        blendMode: BlendMode.dstIn,
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.06),
                                  Colors.black.withValues(alpha: 0.14),
                                ],
                                stops: const [0.0, 0.55, 1.0],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // 5. White Typography floating at bottom matching reference images
                Positioned(
                  left: 16,
                  right: 16,
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
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.82),
                          letterSpacing: 0.1,
                          shadows: hero.style == 'similarArtists' ||
                                  hero.style == 'userStation' ||
                                  hero.style == 'discoveryStation' ||
                                  hero.style == 'moodForYou'
                              ? null
                              : [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        hero.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.2,
                          height: 1.15,
                          shadows: hero.style == 'similarArtists' ||
                                  hero.style == 'userStation' ||
                                  hero.style == 'discoveryStation' ||
                                  hero.style == 'moodForYou'
                              ? null
                              : [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    blurRadius: 6,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                        ),
                      ),
                      if (hero.caption.isNotEmpty &&
                          hero.style != 'similarArtists' &&
                          hero.style != 'userStation' &&
                          hero.style != 'discoveryStation' &&
                          hero.style != 'moodForYou') ...[
                        const SizedBox(height: 2),
                        Text(
                          hero.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds the background graphics and layout for the 8 hero card types matching reference images
  Widget _buildHeroBackground(
    BuildContext context,
    HeroCardItem hero,
    double cardWidth,
    double cardHeight,
  ) {
    switch (hero.style) {
      case 'similarArtists':
        // Warm amber / burnt-orange gradient matching the Apple Music reference image
        final Color topColor;
        final Color botColor;
        if (hero.primaryColor != null &&
            hero.primaryColor != 0xFFD81B60 &&
            hero.primaryColor != 0xFFC04B02) {
          final c = Color(hero.primaryColor!);
          topColor = Color.lerp(c, Colors.black, 0.25)!;
          botColor = Color.lerp(c, Colors.orange, 0.40)!;
        } else {
          // Exact colors extracted from Apple Music reference image
          topColor = const Color(0xFF904100);
          botColor = const Color(0xFFFC690F);
        }

        final hdUrl = hero.hdImageUrl ?? hero.imageUrl;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                topColor,
                Color.lerp(topColor, botColor, 0.35)!,
                Color.lerp(topColor, botColor, 0.70)!,
                botColor,
              ],
              stops: const [0.0, 0.35, 0.70, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // 2. Medium right circular avatar (rendered behind Circle 1)
              Positioned(
                top: cardHeight * 0.28,
                right: 14,
                child: _buildAvatarCircle(
                  avatarUrl: hero.artistAvatars.length > 1
                      ? hero.artistAvatars[1]
                      : (hero.artistAvatars.isNotEmpty
                            ? hero.artistAvatars[0]
                            : null),
                  size: cardWidth * 0.38,
                ),
              ),
              // 1. Large top-left circular avatar (in front, dominant, matching Apple Music reference)
              Positioned(
                top: 14,
                left: 14,
                child: _buildAvatarCircle(
                  avatarUrl: hero.artistAvatars.isNotEmpty
                      ? hero.artistAvatars[0]
                      : hdUrl,
                  size: cardWidth * 0.56,
                ),
              ),
              // 3. Small circular avatar nestled below circle 1's bottom-right curve
              Positioned(
                top: cardHeight * 0.45,
                left: cardWidth * 0.34,
                child: _buildAvatarCircle(
                  avatarUrl: hero.artistAvatars.length > 2
                      ? hero.artistAvatars[2]
                      : (hero.artistAvatars.isNotEmpty
                            ? hero.artistAvatars[0]
                            : null),
                  size: cardWidth * 0.29,
                ),
              ),
            ],
          ),
        );

      case 'mixWithBadge':
        // New Release Mix matching Image 2 with top rectangular HD image and display typography
        final hdUrl = hero.hdImageUrl ?? hero.imageUrl;
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF5A1435), Color(0xFF380C20), Color(0xFF1C0510)],
              stops: [0.0, 0.60, 1.0],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Top rectangular artwork container (Image 2)
              if (hdUrl != null)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: cardHeight * 0.54,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      WavifyCachedImage(
                        imageUrl: hdUrl,
                        songId: hero.playTrack?.id,
                        width: cardWidth,
                        height: cardHeight * 0.54,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        filterQuality: FilterQuality.high,
                        placeholder: AppShimmer(
                          baseColor: const Color(0xFF1E1E22),
                          highlightColor: const Color(0xFF2E2E34),
                          child: Container(color: const Color(0xFF141414)),
                        ),
                      ),
                      // Smooth vertical gradient blend at bottom into card body
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.transparent,
                                const Color(0xFF380C20).withValues(alpha: 0.70),
                                const Color(0xFF380C20),
                              ],
                              stops: const [0.0, 0.40, 0.80, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Large stylized display title matching Image 2
              Positioned(
                top: cardHeight * 0.35,
                left: 14,
                right: 14,
                child: Text(
                  'New\nRelease\nMix',
                  style: TextStyle(
                    fontFamily: 'SF Pro Display',
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    height: 0.94,
                    letterSpacing: -0.8,
                    color: Colors.white.withValues(alpha: 0.95),
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.55),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );

      case 'userStation':
        // Right-pointing faceted chevrons matching Image 3 (Utkarsh's Station)
        return CustomPaint(
          size: Size(cardWidth, cardHeight),
          painter: _ChevronStationPainter(),
        );

      case 'discoveryStation':
        // Deep warm amber with concentric circular rings matching Image 4 left card
        final baseColor = Color(hero.primaryColor ?? 0xFFD84315);
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                baseColor,
                baseColor.withValues(alpha: 0.90),
                const Color(0xFF4A1000),
                const Color(0xFF1E0500),
              ],
              stops: const [0.0, 0.50, 0.85, 1.0],
            ),
          ),
          child: CustomPaint(
            size: Size(cardWidth, cardHeight),
            painter: const _ConcentricRingsPainter(ringColor: Colors.white),
          ),
        );

      case 'moodForYou':
        final baseColor = Color(hero.primaryColor ?? 0xFF00D26A);
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                baseColor,
                baseColor.withValues(alpha: 0.85),
                Colors.black.withValues(alpha: 0.95),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40),
              child: _buildMoodIcon(hero.iconType ?? 'lightning'),
            ),
          ),
        );

      default:
        // Studio HD full bleed cover artwork (Image 1 left peek) with proper shimmer placeholder
        final hdUrl = hero.hdImageUrl ?? hero.imageUrl;
        if (hdUrl != null) {
          return WavifyCachedImage(
            imageUrl: hdUrl,
            songId: hero.playTrack?.id,
            width: cardWidth,
            height: cardHeight,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
            placeholder: AppShimmer(
              baseColor: const Color(0xFF18181A),
              highlightColor: const Color(0xFF28282E),
              child: Container(
                width: cardWidth,
                height: cardHeight,
                color: const Color(0xFF141414),
              ),
            ),
            errorWidget: Container(
              color: const Color(0xFF141414),
              child: const Center(
                child: Icon(
                  CupertinoIcons.music_note,
                  color: Colors.white24,
                  size: 40,
                ),
              ),
            ),
          );
        } else {
          return Container(
            color: const Color(0xFF141414),
            child: const Center(
              child: Icon(
                CupertinoIcons.music_note,
                color: Colors.white24,
                size: 40,
              ),
            ),
          );
        }
    }
  }

  Widget _buildAvatarCircle({
    required String? avatarUrl,
    required double size,
  }) {
    final hdAvatar = avatarUrl != null
        ? (SongItem.upgradeThumbnail(avatarUrl, size: 500, quality: 95) ??
              avatarUrl)
        : null;

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: hdAvatar != null
            ? WavifyCachedImage(
                imageUrl: hdAvatar,
                width: size,
                height: size,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.high,
                placeholder: AppShimmer(
                  baseColor: const Color(0xFF1E1E22),
                  highlightColor: const Color(0xFF2E2E34),
                  child: Container(
                    width: size,
                    height: size,
                    decoration: const BoxDecoration(
                      color: Color(0xFF141414),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                errorWidget: Container(
                  color: AppColors.appleDarkSurfaceHigh,
                  child: const Icon(
                    CupertinoIcons.person_fill,
                    color: Colors.white30,
                    size: 24,
                  ),
                ),
              )
            : Container(
                color: AppColors.appleDarkSurfaceHigh,
                child: const Icon(
                  CupertinoIcons.person_fill,
                  color: Colors.white30,
                  size: 24,
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
    final validSongs = songs
        .where(
          (s) =>
              s.title.trim().isNotEmpty &&
              s.title.trim().toLowerCase() != 'untitled' &&
              s.title.trim().toLowerCase() != 'track',
        )
        .toList();
    if (validSongs.isEmpty) return const SizedBox.shrink();

    // Chunk songs into lists of 4
    final chunked = <List<SongItem>>[];
    for (var i = 0; i < validSongs.length; i += 4) {
      final end = (i + 4 < validSongs.length) ? i + 4 : validSongs.length;
      chunked.add(validSongs.sublist(i, end));
    }

    // Responsively calculate height based on the maximum number of items in any column
    final maxPerColumn = chunked.fold<int>(
      0,
      (prev, col) => col.length > prev ? col.length : prev,
    );
    const rowHeight = 64.0;
    final totalHeight = maxPerColumn * rowHeight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppleSpacing.horizontalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null) ...[
                Text(subtitle.toUpperCase(), style: AppleTypography.eyebrow),
                const SizedBox(height: 3),
              ],
              Text(title, style: AppleTypography.sectionTitle),
            ],
          ),
        ),
        const SizedBox(height: AppleSpacing.sectionHeaderToContent),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: _Snapping4ItemColumns(
            chunked: chunked,
            totalHeight: totalHeight,
            rowBuilder: (ctx, song) =>
                _build4ItemRow(ctx, ref, song, contextQueue: validSongs),
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
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isSelected = currentSong?.id == song.id;

    return SizedBox(
      key: ValueKey('row_${song.id}'),
      height: 64,
      child: ApplePressable(
        onTap: () {
          List<SongItem>? queue;
          List<SongItem>? history;
          if (contextQueue != null && contextQueue.isNotEmpty) {
            final idx = contextQueue.indexWhere((s) => s.id == song.id);
            history = idx > 0
                ? contextQueue.sublist(0, idx)
                : const <SongItem>[];
            queue = (idx >= 0 && idx < contextQueue.length - 1)
                ? contextQueue.sublist(idx + 1)
                : const <SongItem>[];
          }
          playSong(
            context,
            ref,
            song,
            contextQueue: queue,
            initialHistory: history,
            originalTracklist: contextQueue,
            forceReload: true,
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
          child: Row(
            children: [
              // Artwork with Equalizer overlay when playing
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    WavifyCachedImage(
                      imageUrl: song.thumbnailUrl ?? song.resolvedThumbnailUrl,
                      placeholderImageUrl:
                          song.resolvedThumbnailUrl ?? song.thumbnailUrl,
                      songId: song.id,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorWidget: _fallbackSquareArt(),
                    ),
                    if (isSelected && isPlaying)
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: AnimatedEqualizerBars(
                            size: 16,
                            color: Colors.white,
                            isPlaying: true,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Title & Artist (clean, not bold)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppleTypography.songTitle,
                    ),
                    const SizedBox(height: AppleSpacing.titleToSubtitle),
                    ApplePressable(
                      onTap: () =>
                          openArtistScreen(context, artistName: song.artist),
                      child: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppleTypography.songArtist,
                      ),
                    ),
                  ],
                ),
              ),

              // 3-dots Menu Icon at the very end
              IconButton(
                icon: const AnimatedCupertinoIcon(
                  icon: CupertinoIcons.ellipsis_vertical,
                  color: AppColors.appleSecondaryText,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 40),
                visualDensity: VisualDensity.compact,
                onPressed: () => showTrackOptionsModal(context, ref, song),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Find Your Mood Section with Line-Art Icons & 3-Wave Logo
  Widget _buildFindYourMoodSection(
    BuildContext context,
    List<MusicCategory> moods,
  ) {
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Find Your Mood', style: AppleTypography.sectionTitle),
              GestureDetector(
                onTap: () {
                  widget.onNavigateToTab?.call(1); // Switch to Explore Tab
                },
                child: const Text(
                  'Show all',
                  style: TextStyle(
                    color: AppColors.appleSecondaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 175,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: moodDefs.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final mood = moodDefs[index];
              return RepaintBoundary(
                child: ApplePressable(
                  onTap: () {
                    widget.onSearch?.call(mood.title);
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
                              child: WavifyLogo(size: 16),
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
        return const Icon(
          CupertinoIcons.bolt_fill,
          size: 58,
          color: Colors.white,
        );
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
        return const Icon(CupertinoIcons.scope, size: 48, color: Colors.white);
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

  /// Albums & Singles Horizontal Carousel with continuous fade scrim matching Top Picks
  Widget _buildAlbumsAndSinglesSection(
    BuildContext context,
    WidgetRef ref,
    List<AlbumItem> albums,
  ) {
    if (albums.isEmpty) return const SizedBox.shrink();

    // Filter and prioritize albums matching user's taste (from recently played & authentic listening history)
    final recentSongs = ref.watch(
      playerProvider.select((s) => s.recentlyPlayed),
    );
    final listenedArtists = <String>{};
    for (final s in recentSongs) {
      if (s.artist.trim().isNotEmpty) {
        listenedArtists.add(s.artist.toLowerCase().trim());
        final primary = s.artist
            .split(RegExp(r'[,&•/]'))
            .first
            .toLowerCase()
            .trim();
        if (primary.isNotEmpty) listenedArtists.add(primary);
      }
    }

    final displayAlbums = List<AlbumItem>.from(albums);
    if (listenedArtists.isNotEmpty) {
      displayAlbums.sort((a, b) {
        final aSub = a.subtitle.toLowerCase();
        final aTitle = a.title.toLowerCase();
        final bSub = b.subtitle.toLowerCase();
        final bTitle = b.title.toLowerCase();

        final aMatch = listenedArtists.any(
          (la) => aSub.contains(la) || aTitle.contains(la),
        );
        final bMatch = listenedArtists.any(
          (la) => bSub.contains(la) || bTitle.contains(la),
        );

        if (aMatch && !bMatch) return -1;
        if (!aMatch && bMatch) return 1;
        return 0;
      });
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.40).clamp(148.0, 190.0);
    final cardHeight = cardWidth + 54.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppleSpacing.horizontalPadding,
          ),
          child: Text('Albums & singles', style: AppleTypography.sectionTitle),
        ),
        const SizedBox(height: AppleSpacing.sectionHeaderToContent),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: displayAlbums.length > 15 ? 15 : displayAlbums.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final album = displayAlbums[index];
              final displaySubtitle =
                  (album.description != null &&
                      album.description!.trim().isNotEmpty)
                  ? album.description!.trim()
                  : (album.subtitle.isNotEmpty ? album.subtitle : album.artist);
              return RepaintBoundary(
                child: ApplePressable(
                  onTap: () => openAlbumScreen(context, album),
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: cardWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1:1 Aspect Ratio Square Box
                        Container(
                          width: cardWidth,
                          height: cardWidth,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: const Color(0xFF141414),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 0.6,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: DynamicAlbumArtwork(
                              album: album,
                              size: cardWidth,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Title below the artwork
                        Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppleTypography.cardTitle,
                        ),
                        // Subtitle below the title (natural case, no uppercase)
                        if (displaySubtitle.isNotEmpty) ...[
                          const SizedBox(height: AppleSpacing.titleToSubtitle),
                          Text(
                            displaySubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppleTypography.cardSubtitle,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Square Cards Horizontal Carousel (Dynamic InnerTube Shelves: Albums, Playlists, Mixes, Community)
  Widget _buildSquareCardsSection({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    String? subtitle,
    List<AlbumItem> albums = const [],
    List<PlaylistItem> playlists = const [],
  }) {
    if (albums.isEmpty && playlists.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.40).clamp(148.0, 190.0);
    final cardHeight = cardWidth + 54.0;

    final items = <_SquareItem>[
      ...albums.map((a) => _SquareItem.album(a)),
      ...playlists.map((p) => _SquareItem.playlist(p)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppleSpacing.horizontalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                Text(subtitle, style: AppleTypography.eyebrow),
                const SizedBox(height: 2),
              ],
              Text(title, style: AppleTypography.sectionTitle),
            ],
          ),
        ),
        const SizedBox(height: AppleSpacing.sectionHeaderToContent),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length > 15 ? 15 : items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final item = items[index];
              return RepaintBoundary(
                child: ApplePressable(
                  onTap: () {
                    if (item.album != null) {
                      openAlbumScreen(context, item.album!);
                    } else if (item.playlist != null) {
                      openPlaylistScreen(context, ref, item.playlist!);
                    }
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: cardWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1:1 Aspect Ratio Square Box for Album Art / Picture
                        Container(
                          width: cardWidth,
                          height: cardWidth,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: const Color(0xFF141414),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 0.6,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: item.isLikedMusic
                                ? Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF6B21A8),
                                          Color(0xFFEC4899),
                                        ],
                                      ),
                                    ),
                                    child: const Center(
                                      child: Icon(
                                        CupertinoIcons.hand_thumbsup_fill,
                                        color: Colors.white,
                                        size: 44,
                                      ),
                                    ),
                                  )
                                : item.album != null
                                ? DynamicAlbumArtwork(
                                    album: item.album!,
                                    size: cardWidth,
                                  )
                                : (item.imageUrl != null
                                      ? WavifyCachedImage(
                                          imageUrl: item.imageUrl!,
                                          fit: BoxFit.cover,
                                          errorWidget: _fallbackSquareArt(
                                            size: cardWidth,
                                            icon:
                                                CupertinoIcons.music_note_list,
                                          ),
                                        )
                                      : _fallbackSquareArt(
                                          size: cardWidth,
                                          icon: CupertinoIcons.music_note_list,
                                        )),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Text written below the artwork (natural case, no uppercase!)
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppleTypography.cardTitle,
                        ),
                        if (item.eyebrow.isNotEmpty) ...[
                          const SizedBox(height: AppleSpacing.titleToSubtitle),
                          Text(
                            item.eyebrow,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppleTypography.cardSubtitle,
                          ),
                        ],
                      ],
                    ),
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
    List<VideoItem> videos, {
    String title = 'Music Videos',
    String? subtitle,
  }) {
    if (videos.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final videoWidth = (screenWidth * 0.65).clamp(220.0, 320.0);
    final videoThumbnailHeight = videoWidth * (9 / 16);
    final videoCardHeight = videoThumbnailHeight + 58.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppleSpacing.horizontalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                Text(subtitle.toUpperCase(), style: AppleTypography.eyebrow),
                const SizedBox(height: 2),
              ],
              Text(title, style: AppleTypography.sectionTitle),
            ],
          ),
        ),
        const SizedBox(height: AppleSpacing.sectionHeaderToContent),
        SizedBox(
          height: videoCardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: videos.length > 10 ? 10 : videos.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final video = videos[index];
              return RepaintBoundary(
                child: ApplePressable(
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
                          style: AppleTypography.cardTitle,
                        ),
                        const SizedBox(height: AppleSpacing.titleToSubtitle),
                        Text(
                          video.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppleTypography.cardSubtitle,
                        ),
                      ],
                    ),
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
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.38).clamp(136.0, 180.0);
    final cardHeight = cardWidth + 58.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppleSpacing.horizontalPadding,
          ),
          child: Text(title, style: AppleTypography.sectionTitle),
        ),
        const SizedBox(height: AppleSpacing.sectionHeaderToContent),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: songs.length > 12 ? 12 : songs.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final song = songs[index];
              final isCurrent = currentSong?.id == song.id;

              return RepaintBoundary(
                child: ApplePressable(
                  onTap: () {
                    final history = index > 0
                        ? songs.sublist(0, index)
                        : const <SongItem>[];
                    final queue = (index < songs.length - 1)
                        ? songs.sublist(index + 1)
                        : const <SongItem>[];
                    playSong(
                      context,
                      ref,
                      song,
                      contextQueue: queue,
                      initialHistory: history,
                      originalTracklist: songs,
                      forceReload: true,
                    );
                  },
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
                                      errorWidget: _fallbackSquareArt(
                                        size: cardWidth,
                                      ),
                                    )
                                  : _fallbackSquareArt(size: cardWidth),
                            ),
                            if (isCurrent && isPlaying)
                              Positioned(
                                right: 8,
                                bottom: 8,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.2,
                                      ),
                                      width: 0.8,
                                    ),
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  child: const AnimatedEqualizerBars(
                                    size: 14,
                                    color: Colors.white,
                                    isPlaying: true,
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
                          style: AppleTypography.cardTitle,
                        ),
                        const SizedBox(height: AppleSpacing.titleToSubtitle),
                        ApplePressable(
                          onTap: () => openArtistScreen(
                            context,
                            artistName: song.artist,
                          ),
                          child: Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppleTypography.cardSubtitle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // =========================================================================
  // PERSONALIZED SECTION WIDGETS
  // =========================================================================

  /// Playlist Carousel — renders "Mixed for You", "Your Mixes", "Featured Playlists"
  Widget _buildPlaylistCarousel({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    required List<PlaylistItem> playlists,
  }) {
    if (playlists.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.40).clamp(148.0, 190.0);
    final cardHeight = cardWidth + 54.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppleSpacing.horizontalPadding,
          ),
          child: Text(title, style: AppleTypography.sectionTitle),
        ),
        const SizedBox(height: AppleSpacing.sectionHeaderToContent),
        SizedBox(
          height: cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: playlists.length > 12 ? 12 : playlists.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              final displaySubtitle =
                  (playlist.author.isNotEmpty &&
                      playlist.author.toLowerCase() != 'youtube music')
                  ? playlist.author
                  : (playlist.subtitle.isNotEmpty
                        ? playlist.subtitle
                        : 'Playlist');
              return RepaintBoundary(
                child: ApplePressable(
                  onTap: () => openPlaylistScreen(context, ref, playlist),
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: cardWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 1:1 Aspect Ratio Square Box for Playlist Artwork
                        Container(
                          width: cardWidth,
                          height: cardWidth,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: const Color(0xFF141414),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 0.6,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: playlist.thumbnailUrl != null
                                ? WavifyCachedImage(
                                    imageUrl: playlist.thumbnailUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: _fallbackSquareArt(
                                      size: cardWidth,
                                      icon: CupertinoIcons.music_note_list,
                                    ),
                                  )
                                : _fallbackSquareArt(
                                    size: cardWidth,
                                    icon: CupertinoIcons.music_note_list,
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Title below the artwork
                        Text(
                          playlist.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppleTypography.cardTitle,
                        ),
                        // Subtitle below the title (natural case, no uppercase!)
                        if (displaySubtitle.isNotEmpty) ...[
                          const SizedBox(height: AppleSpacing.titleToSubtitle),
                          Text(
                            displaySubtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppleTypography.cardSubtitle,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Featured Artists & Similar Artists — horizontal circular avatar carousel.
  Widget _buildFeaturedArtistsSection(
    BuildContext context,
    WidgetRef ref,
    List<ArtistItem> artists,
  ) {
    if (artists.isEmpty) return const SizedBox.shrink();

    const avatarSize = 86.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppleSpacing.horizontalPadding,
          ),
          child: Text('Featured Artists', style: AppleTypography.sectionTitle),
        ),
        const SizedBox(height: AppleSpacing.sectionHeaderToContent),
        SizedBox(
          height: avatarSize + 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: artists.length > 12 ? 12 : artists.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final artist = artists[index];
              return RepaintBoundary(
                child: ApplePressable(
                  onTap: () =>
                      openArtistScreen(context, artistName: artist.name),
                  borderRadius: BorderRadius.circular(avatarSize / 2 + 4),
                  child: SizedBox(
                    width: avatarSize + 8,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipOval(
                          child: artist.thumbnailUrl != null
                              ? WavifyCachedImage(
                                  imageUrl: artist.thumbnailUrl!,
                                  width: avatarSize,
                                  height: avatarSize,
                                  fit: BoxFit.cover,
                                  errorWidget: Container(
                                    width: avatarSize,
                                    height: avatarSize,
                                    color: AppColors.appleDarkSurfaceHigh,
                                    child: const Icon(
                                      CupertinoIcons.person_fill,
                                      color: Colors.white30,
                                      size: 36,
                                    ),
                                  ),
                                )
                              : Container(
                                  width: avatarSize,
                                  height: avatarSize,
                                  color: AppColors.appleDarkSurfaceHigh,
                                  child: const Icon(
                                    CupertinoIcons.person_fill,
                                    color: Colors.white30,
                                    size: 36,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          artist.name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.1,
                          ),
                        ),
                      ],
                    ),
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

/// Horizontal paging container that snaps 4-item song columns cleanly into place.
class _Snapping4ItemColumns extends StatefulWidget {
  final List<List<SongItem>> chunked;
  final double totalHeight;
  final Widget Function(BuildContext context, SongItem song) rowBuilder;

  const _Snapping4ItemColumns({
    required this.chunked,
    required this.totalHeight,
    required this.rowBuilder,
  });

  @override
  State<_Snapping4ItemColumns> createState() => _Snapping4ItemColumnsState();
}

class _Snapping4ItemColumnsState extends State<_Snapping4ItemColumns> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.94);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.totalHeight,
      child: PageView.builder(
        controller: _controller,
        padEnds: false,
        physics: const PageScrollPhysics(),
        itemCount: widget.chunked.length,
        itemBuilder: (context, columnIndex) {
          final columnSongs = widget.chunked[columnIndex];
          return Padding(
            padding: EdgeInsets.only(
              left: 12,
              right: columnIndex == widget.chunked.length - 1 ? 12 : 6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: columnSongs
                  .map(
                    (song) => KeyedSubtree(
                      key: ValueKey('song_col_${song.id}'),
                      child: widget.rowBuilder(context, song),
                    ),
                  )
                  .toList(),
            ),
          );
        },
      ),
    );
  }
}

class _SquareItem {
  final String title;
  final String eyebrow;
  final String? imageUrl;
  final AlbumItem? album;
  final PlaylistItem? playlist;
  final bool isLikedMusic;

  const _SquareItem._({
    required this.title,
    required this.eyebrow,
    this.imageUrl,
    this.album,
    this.playlist,
    this.isLikedMusic = false,
  });

  factory _SquareItem.album(AlbumItem album) {
    final desc = album.description?.trim();
    final eyebrow = (desc != null && desc.isNotEmpty)
        ? desc
        : (album.subtitle.isNotEmpty ? album.subtitle : album.artist);
    return _SquareItem._(
      title: album.title,
      eyebrow: eyebrow,
      imageUrl: album.thumbnailUrl,
      album: album,
    );
  }

  factory _SquareItem.playlist(PlaylistItem playlist) {
    final isLiked =
        playlist.id == 'LM' ||
        playlist.title.trim().toLowerCase() == 'liked music' ||
        playlist.title.trim().toLowerCase() == 'your likes';
    String subtitle = playlist.author.trim();
    if (isLiked) {
      subtitle = 'Auto playlist';
    } else if (subtitle.isEmpty || subtitle.toLowerCase() == 'youtube music') {
      subtitle = playlist.subtitle.isNotEmpty ? playlist.subtitle : 'Playlist';
    }
    return _SquareItem._(
      title: playlist.title,
      eyebrow: subtitle,
      imageUrl: playlist.thumbnailUrl,
      playlist: playlist,
      isLikedMusic: isLiked,
    );
  }
}

/// Custom painter for right-pointing faceted chevrons matching Image 3 (Utkarsh's Station)
class _ChevronStationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Base background gradient: Radiant rose / pink / magenta
    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFA2D65), Color(0xFFE01853), Color(0xFF880E4F)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), basePaint);

    // Chevron 3 (deep magenta/rose)
    final p3 = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.25, 0)
      ..lineTo(w * 0.88, h * 0.50)
      ..lineTo(w * 0.25, h)
      ..lineTo(0, h)
      ..lineTo(w * 0.63, h * 0.50)
      ..close();
    canvas.drawPath(
      p3,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFE91E63), Color(0xFFAD1457)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Chevron 2 (middle vibrant coral/pink)
    final p2 = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.12, 0)
      ..lineTo(w * 0.65, h * 0.50)
      ..lineTo(w * 0.12, h)
      ..lineTo(0, h)
      ..lineTo(w * 0.50, h * 0.50)
      ..close();
    canvas.drawPath(
      p2,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFF4081), Color(0xFFF50057)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Chevron 1 (leftmost warm coral/orange)
    final p1 = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.05, 0)
      ..lineTo(w * 0.45, h * 0.50)
      ..lineTo(w * 0.05, h)
      ..lineTo(0, h)
      ..lineTo(w * 0.38, h * 0.50)
      ..close();
    canvas.drawPath(
      p1,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomLeft,
          colors: [Color(0xFFFF6E40), Color(0xFFFF3D00)],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom painter for concentric rings on warm amber background matching Image 4 left card
class _ConcentricRingsPainter extends CustomPainter {
  final Color ringColor;
  const _ConcentricRingsPainter({this.ringColor = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(0, size.height * 0.45);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final radii = [
      size.width * 0.15,
      size.width * 0.30,
      size.width * 0.48,
      size.width * 0.68,
      size.width * 0.90,
    ];

    for (int i = 0; i < radii.length; i++) {
      paint.color = ringColor.withValues(
        alpha: (0.35 - i * 0.05).clamp(0.12, 0.40),
      );
      canvas.drawCircle(center, radii[i], paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

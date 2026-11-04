import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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
import '../widgets/animated_equalizer_bars.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/dynamic_album_artwork.dart';
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

    return homeDataAsync.when(
      loading: () => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Loading music...',
              style: TextStyle(
                color: AppColors.appleSecondaryText,
                fontSize: 14,
              ),
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
                color: Colors.white70,
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
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        // 1. Scrollable Feed Body (extends edge-to-edge beyond the notification/battery bar)
        RefreshIndicator(
          color: Colors.white,
          backgroundColor: AppColors.appleDarkSurface,
          onRefresh: () => ref.read(homeDataProvider.notifier).refresh(),
          child: ListView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(0, topPadding, 0, 160),
            children: [
                // Top Header: Melomaniac Logo on Left + Profile Avatar on Right
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
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
                            onTap: () => showAccountModalSheet(context, ref),
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
                                          ? Colors.white.withValues(alpha: 0.85)
                                          : Colors.white.withValues(alpha: 0.5),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: account != null
                                        ? Colors.white.withValues(alpha: 0.20)
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
                                                  CupertinoIcons
                                                      .person_crop_circle_fill,
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
                _buildAlbumsAndSinglesSection(
                  context,
                  ref,
                  data.albumsAndSingles,
                ),
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
          ),

          // 2. Subtle Top Status Bar Dissolve on Scroll (confined strictly to the battery & notification edge)
          AnimatedBuilder(
            animation: _scrollController,
            builder: (context, _) {
              final offset =
                  _scrollController.hasClients ? _scrollController.offset : 0.0;
              final progress = (offset / 32.0).clamp(0.0, 1.0);
              if (progress <= 0.001) {
                return const SizedBox.shrink();
              }

              // Confined strictly to the status bar / battery bar height
              final topBlurHeight = topPadding + 4.0;

              return Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: topBlurHeight,
                child: IgnorePointer(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Very delicate progressive blur directly at the top status bar edge
                      ProgressiveBlur(
                        maxSigma: 4.0 * progress,
                        direction: ProgressiveBlurDirection.topToBottom,
                        falloff: 2.0,
                      ),
                      // Soft darkening dissolve so content naturally fades away under the battery/clock
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.85 * progress),
                              Colors.black.withValues(alpha: 0.35 * progress),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.55, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
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
        const SizedBox(height: 12),
        SizedBox(
          height: 390,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: heroCards.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
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
    final screenWidth = MediaQuery.of(context).size.width;
    // Increased size: length & width for a flagship Apple Music presence
    final cardWidth = (screenWidth * 0.74).clamp(275.0, 340.0);
    const cardHeight = 390.0;

    return ApplePressable(
      onTap: () {
        if (hero.playTrack != null) {
          playSong(context, ref, hero.playTrack!, forceReload: true);
        } else {
          playHero(context, ref, hero);
        }
      },
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: const Color(0xFF141414), // Pure neutral dark: NO blue tint!
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.6,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Sharp Full-Bleed Cover Artwork
              if (hero.imageUrl != null)
                WavifyCachedImage(
                  imageUrl: hero.imageUrl!,
                  songId: hero.playTrack?.id,
                  fit: BoxFit.cover,
                  errorWidget: Container(
                    color: const Color(0xFF141414),
                    child: const Center(
                      child: Icon(
                        CupertinoIcons.music_note,
                        color: Colors.white24,
                        size: 48,
                      ),
                    ),
                  ),
                )
              else
                Container(
                  color: const Color(0xFF141414),
                  child: const Center(
                    child: Icon(
                      CupertinoIcons.music_note,
                      color: Colors.white24,
                      size: 48,
                    ),
                  ),
                ),

              // 2. Continuous Organic Blur Layer:
              // Seamlessly blends from sharp artwork into a lush frosted blur with ZERO hard dividing lines!
              if (hero.imageUrl != null)
                Positioned.fill(
                  child: ShaderMask(
                    shaderCallback: (bounds) {
                      return const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black,
                        ],
                        stops: [0.0, 0.40, 0.82],
                      ).createShader(bounds);
                    },
                    blendMode: BlendMode.dstIn,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: WavifyCachedImage(
                        imageUrl: hero.imageUrl!,
                        songId: hero.playTrack?.id,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),

              // 3. Smooth Deep Charcoal/OLED Gradient Scrim (No hard line, seamlessly mixing with the blur)
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        Color(0x66000000),
                        Color(0xE6000000),
                      ],
                      stops: [0.0, 0.42, 0.72, 1.0],
                    ),
                  ),
                ),
              ),

              // 4. White Typography naturally floating on the organic blur
              Positioned(
                left: 18,
                right: 18,
                bottom: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hero.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hero.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hero.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12.5,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
        _Snapping4ItemColumns(
          chunked: chunked,
          totalHeight: totalHeight,
          rowBuilder: (ctx, song) =>
              _build4ItemRow(ctx, ref, song, contextQueue: songs),
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
      height: 64,
      child: ApplePressable(
        onTap: () => playSong(
          context,
          ref,
          song,
          contextQueue: contextQueue,
          forceReload: true,
        ),
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
                    song.thumbnailUrl != null
                        ? WavifyCachedImage(
                            imageUrl: song.thumbnailUrl!,
                            songId: song.id,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorWidget: _fallbackSquareArt(),
                          )
                        : _fallbackSquareArt(),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.2,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    ApplePressable(
                      onTap: () =>
                          openArtistScreen(context, artistName: song.artist),
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
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  widget.onNavigateToTab?.call(1); // Switch to Explore Tab
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
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: moodDefs.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final mood = moodDefs[index];
              return ApplePressable(
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

  /// Albums & Singles Horizontal Carousel with Apple-style frosted blur
  Widget _buildAlbumsAndSinglesSection(
    BuildContext context,
    WidgetRef ref,
    List<AlbumItem> albums,
  ) {
    if (albums.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.40).clamp(148.0, 190.0);
    final cardHeight = cardWidth * 1.28;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: albums.length > 15 ? 15 : albums.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final album = albums[index];
              return ApplePressable(
                onTap: () => openAlbumScreen(context, album),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: cardWidth,
                  height: cardHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                      width: 0.8,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: DynamicAlbumArtwork(
                            album: album,
                            size: cardWidth,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(16),
                            ),
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(
                                sigmaX: 18,
                                sigmaY: 18,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.38),
                                  border: Border(
                                    top: BorderSide(
                                      color: Colors.white.withValues(
                                        alpha: 0.08,
                                      ),
                                      width: 0.8,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      album.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      album.subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(
                                          alpha: 0.65,
                                        ),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
          padding: EdgeInsets.symmetric(horizontal: 12),
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
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: videos.length > 10 ? 10 : videos.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
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
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.38).clamp(136.0, 180.0);
    final cardHeight = cardWidth + 58.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
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
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: songs.length > 12 ? 12 : songs.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final song = songs[index];
              final isCurrent = currentSong?.id == song.id;

              return ApplePressable(
                onTap: () => playSong(
                  context,
                  ref,
                  song,
                  contextQueue: songs,
                  forceReload: true,
                ),
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
                                    color: Colors.white.withValues(alpha: 0.2),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      ApplePressable(
                        onTap: () =>
                            openArtistScreen(context, artistName: song.artist),
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
                  .map((song) => widget.rowBuilder(context, song))
                  .toList(),
            ),
          );
        },
      ),
    );
  }
}

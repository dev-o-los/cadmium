import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../constants/apple_typography.dart';
import '../models/music_category.dart';
import '../models/song_item.dart';
import '../providers/home_data_provider.dart';
import '../providers/player_provider.dart';
import '../services/music_service.dart';
import '../utils/playback_utils.dart';
import '../widgets/animated_cupertino_icon.dart';
import '../widgets/animated_equalizer_bars.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/top_status_bar_blur.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/app_shimmer.dart';
import '../widgets/wavify_cached_image.dart';

/// The Explore Tab screen featuring Genres & Categories grid and Global Hits & Charts.
class ExploreScreen extends ConsumerStatefulWidget {
  final ValueChanged<String>? onSearch;

  const ExploreScreen({super.key, this.onSearch});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
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
    final trending = homeData?.trendingSongs ?? [];
    final topPadding = MediaQuery.of(context).padding.top;

    // Gather categories from homeData (moods & genres enriched with InnerTube image and subtitle)
    final allCategories = <MusicCategory>[
      ...?homeData?.moods,
      ...?homeData?.genres,
    ];

    final categories = allCategories.isNotEmpty
        ? allCategories
        : MusicService.curatedMoodMetadata.entries.map((e) {
            return MusicCategory(
              title: e.key,
              colorValue: e.value.color,
              params: e.value.params,
              imageUrl: e.value.imageUrl,
              subtitle: e.value.subtitle,
            );
          }).toList();

    return Stack(
      children: [
        ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(0, topPadding + 14, 0, 160),
          children: [
            // Body Content Large Title Header (leveled identically with Library)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Explore',
                style: AppleTypography.largeTitle,
              ),
            ),
            const SizedBox(height: 20),

            // 2-Column Grid of Mood & Genre Cards matching InnerTube aesthetic
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Builder(
                builder: (context) {
                  final screenWidth = MediaQuery.of(context).size.width - 40;
                  final crossAxisCount = screenWidth > 600 ? 3 : 2;
                  final cardWidth = (screenWidth - (crossAxisCount - 1) * 12) / crossAxisCount;

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: categories.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.85,
                    ),
                  itemBuilder: (context, index) {
                    final cat = categories[index];
                    final cardColor = cat.colorValue != null
                        ? Color(cat.colorValue!).withValues(alpha: 0.90)
                        : const Color(0xFF2C2C2E);

                    return RepaintBoundary(
                      child: ApplePressable(
                        onTap: () {
                          widget.onSearch?.call(cat.title);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: cardColor,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // InnerTube playlist artwork on the right with smooth color fade
                                if (cat.imageUrl != null && cat.imageUrl!.isNotEmpty)
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    bottom: 0,
                                    width: cardWidth * 0.65,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        WavifyCachedImage(
                                          imageUrl: cat.imageUrl!,
                                          fit: BoxFit.cover,
                                          errorWidget: const SizedBox.shrink(),
                                        ),
                                        Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                              colors: [
                                                cardColor,
                                                cardColor.withValues(alpha: 0.85),
                                                cardColor.withValues(alpha: 0.35),
                                                cardColor.withValues(alpha: 0.10),
                                              ],
                                              stops: const [0.0, 0.25, 0.65, 1.0],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                // Category Title at top-left
                                Positioned(
                                  top: 12,
                                  left: 12,
                                  right: cardWidth * 0.35,
                                  child: Text(
                                    cat.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                ),

                                // InnerTube playlist subtitle in bottom-right
                                if (cat.subtitle != null && cat.subtitle!.isNotEmpty)
                                  Positioned(
                                    right: 10,
                                    bottom: 10,
                                    left: cardWidth * 0.30,
                                    child: Text(
                                      cat.subtitle!,
                                      maxLines: 2,
                                      textAlign: TextAlign.right,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.88),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.1,
                                        shadows: const [
                                          Shadow(
                                            color: Color(0x99000000),
                                            offset: Offset(0, 1),
                                            blurRadius: 3,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 28),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Global Hits & Charts',
              style: AppleTypography.sectionTitle,
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: trending
                  .take(15)
                  .map((track) => _buildSongRow(context, ref, track, trending))
                  .toList(),
            ),
          ),
        ],
      ),
        // Dynamic Apple-style status bar blur & fading dissolve on scroll
        TopStatusBarBlur(scrollController: _scrollController),
      ],
    );
  }

  Widget _buildSongRow(
    BuildContext context,
    WidgetRef ref,
    SongItem song,
    List<SongItem> allTracks,
  ) {
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isSelected = currentSong?.id == song.id;

    return ApplePressable(
      onTap: () => playSong(
        context,
        ref,
        song,
        contextQueue: allTracks.where((t) => t.id != song.id).toList(),
        forceReload: true,
      ),
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    WavifyCachedImage(
                      imageUrl: song.thumbnailUrl,
                      songId: song.id,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.circular(8),
                      placeholder: const AppShimmer(
                        child: ShimmerBox(
                          width: 48,
                          height: 48,
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                      ),
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
                            isPlaying: true,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.appleSecondaryText,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
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

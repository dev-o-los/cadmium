import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/song_item.dart';
import '../providers/home_data_provider.dart';
import '../providers/player_provider.dart';
import '../utils/playback_utils.dart';
import '../widgets/animated_cupertino_icon.dart';
import '../widgets/animated_equalizer_bars.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/top_profile_avatar_button.dart';
import '../widgets/track_options_sheet.dart';

/// The Explore Tab screen featuring Genres & Categories grid and Global Hits & Charts.
class ExploreScreen extends ConsumerWidget {
  final ValueChanged<String>? onSearch;

  const ExploreScreen({super.key, this.onSearch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeDataAsync = ref.watch(homeDataProvider);
    final genres = homeDataAsync.valueOrNull?.genres ?? [];
    final trending = homeDataAsync.valueOrNull?.trendingSongs ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 160),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Explore',
              style: TextStyle(
                color: Colors.white,
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: -1.2,
              ),
            ),
            const TopProfileAvatarButton(),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          'Genres & Categories',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Builder(
          builder: (context) {
            final screenWidth = MediaQuery.of(context).size.width;
            final crossAxisCount = screenWidth > 600 ? 3 : 2;
            final childAspectRatio = screenWidth > 600 ? 3.0 : 2.4;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: genres.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: childAspectRatio,
              ),
              itemBuilder: (context, index) {
                final g = genres[index];
                final color = g.colorValue != null
                    ? Color(g.colorValue!).withValues(alpha: 0.85)
                    : AppColors.appleDarkSurfaceHigh;

                return ApplePressable(
                  onTap: () {
                    onSearch?.call(g.title);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: color,
                    ),
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      g.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 24),
        const Text(
          'Global Hits & Charts',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...trending
            .take(10)
            .map((track) => _buildSongRow(context, ref, track, trending)),
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
                    song.thumbnailUrl != null
                        ? Image.network(
                            song.thumbnailUrl!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _fallbackSquareArt(),
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

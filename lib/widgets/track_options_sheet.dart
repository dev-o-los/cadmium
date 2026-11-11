import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../models/album_item.dart';
import '../models/playlist_item.dart';
import '../models/song_item.dart';
import '../providers/favorites_provider.dart';
import '../providers/library_provider.dart';
import '../providers/music_service_provider.dart';
import '../providers/player_provider.dart';
import '../services/lyrics_service.dart';
import '../utils/playback_utils.dart';
import 'apple_glass_bottom_sheet.dart';
import 'apple_pressable.dart';

/// Shows the authentic 3-dots popup menu:
/// - Floating frosted glass card with blur and subtle highlight border
/// - Smooth and lagless opening animation anchored towards top-right
/// - Top row: Like, Dislike, Share
/// - Lyrics Provider selector
/// - Add to playlist, Start radio, Play next
/// - Open album, View Artist, Song Info
void showTrackOptionsModal(
  BuildContext context,
  WidgetRef ref,
  SongItem song, {
  Offset? tapPosition,
}) {
  final isFav = ref.read(favoritesProvider.notifier).isFavorite(song.id);

  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'TrackMenu',
    barrierColor: Colors.black.withValues(alpha: 0.10),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Material(
              color: Colors.transparent,
              child: _TrackMenuCard(
                song: song,
                isFavorite: isFav,
                onDismiss: () => Navigator.pop(dialogContext),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );

      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          alignment: const Alignment(0.85, -0.65),
          scale: Tween<double>(begin: 0.90, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Authentic Liquid Glass preset matching the bottom navigation dock exactly.
const kTrackMenuGlassSettings = LiquidGlassSettings(
  thickness: 30,
  blur: 3,
  chromaticAberration: 0.3,
  lightIntensity: 0.6,
  refractiveIndex: 1.59,
  saturation: 0.7,
  ambientStrength: 1,
  lightAngle: 0.75 * math.pi,
  glassColor: Color(0x3DFFFFFF),
);

class _TrackMenuCard extends ConsumerWidget {
  final SongItem song;
  final bool isFavorite;
  final VoidCallback onDismiss;

  const _TrackMenuCard({
    required this.song,
    required this.isFavorite,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxCardHeight = screenHeight * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 320,
        maxHeight: maxCardHeight,
      ),
      child: GlassContainer(
        useOwnLayer: true,
        shape: const LiquidRoundedSuperellipse(borderRadius: 24),
        color: Colors.transparent,
        settings: const LiquidGlassSettings(),
        child: AdaptiveLiquidGlassLayer(
          settings: const LiquidGlassSettings(),
          quality: GlassQuality.standard,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.22),
                width: 0.6,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),

                    // 1. Top Row: Like, Dislike, Share
                    _buildTopActionRow(context, ref),

                    _buildMenuDivider(),

                  // Lyrics Provider Selector
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Expanded(
                          child: Text(
                            'Lyrics Provider',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        Consumer(
                          builder: (context, ref, _) {
                            final currentProvider = ref.watch(
                              playerProvider.select((s) => s.selectedLyricsProvider),
                            );
                            return Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildProviderPill(
                                    ref: ref,
                                    label: 'lrc.red',
                                    type: LyricsProviderType.lrcRed,
                                    isSelected: currentProvider == LyricsProviderType.lrcRed,
                                  ),
                                  _buildProviderPill(
                                    ref: ref,
                                    label: 'YouTube',
                                    type: LyricsProviderType.youTube,
                                    isSelected: currentProvider == LyricsProviderType.youTube,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  _buildMenuDivider(),

                  // 2. Add to Playlist
                  _buildMenuItem(
                    icon: Icons.playlist_add_rounded,
                    title: 'Add to playlist',
                    onTap: () {
                      onDismiss();
                      _showAddToPlaylistSheet(context, ref);
                    },
                  ),

                  // 3. Start Radio
                  _buildMenuItem(
                    icon: Icons.podcasts_rounded,
                    title: 'Start radio',
                    onTap: () {
                      onDismiss();
                      ref.read(playerProvider.notifier).startRadio(song);
                      showWavifySnackBar(
                        context,
                        'Starting radio based on "${song.title}"',
                      );
                    },
                  ),

                  // 4. Play Next
                  _buildMenuItem(
                    icon: Icons.playlist_play_rounded,
                    title: 'Play next',
                    onTap: () {
                      onDismiss();
                      ref.read(playerProvider.notifier).playNext(song);
                      showWavifySnackBar(
                        context,
                        'Added "${song.title}" to play next',
                      );
                    },
                  ),

                  _buildMenuDivider(),

                  // 5. Open Album
                  _buildMenuItem(
                    icon: Icons.album_rounded,
                    title: 'Open album',
                    subtitle: (song.album != null && song.album!.trim().isNotEmpty)
                        ? song.album!.trim()
                        : song.title.trim(),
                    onTap: () {
                      onDismiss();
                      final albumName = (song.album != null && song.album!.trim().isNotEmpty)
                          ? song.album!.trim()
                          : song.title.trim();
                      openAlbumScreen(
                        context,
                        AlbumItem(
                          id: song.id,
                          title: albumName,
                          artist: song.artist,
                          thumbnailUrl: song.thumbnailUrl,
                        ),
                      );
                    },
                  ),

                  // 6. View Artist
                  _buildMenuItem(
                    icon: Icons.person_rounded,
                    title: 'View Artist: ${song.artist}',
                    onTap: () {
                      onDismiss();
                      openArtistScreen(context, artistName: song.artist);
                    },
                  ),

                  // 7. Song Info
                  _buildMenuItem(
                    icon: Icons.info_outline_rounded,
                    title: 'Song Info',
                    onTap: () {
                      onDismiss();
                      _showSongInfoDialog(context);
                    },
                  ),

                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildTopActionRow(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          // Like Action
          Expanded(
            child: _buildTopActionButton(
              icon: isFavorite ? CupertinoIcons.star_fill : CupertinoIcons.star,
              label: 'Like',
              isActive: isFavorite,
              onTap: () {
                ref.read(favoritesProvider.notifier).toggleFavorite(song);
                if (!isFavorite) {
                  ref.read(musicServiceProvider).likeSong(song.id);
                } else {
                  ref.read(musicServiceProvider).unlikeSong(song.id);
                }
                onDismiss();
                showWavifySnackBar(
                  context,
                  isFavorite
                      ? 'Removed "${song.title}" from favorites'
                      : 'Saved "${song.title}" to favorites',
                );
              },
            ),
          ),

          // Dislike Action
          Expanded(
            child: _buildTopActionButton(
              icon: Icons.heart_broken_rounded,
              label: 'Dislike',
              onTap: () {
                ref.read(musicServiceProvider).dislikeSong(song.id);
                onDismiss();
                showWavifySnackBar(
                  context,
                  'Marked "${song.title}" as disliked. Wavify will tune your recommendations.',
                );
              },
            ),
          ),

          // Share Action
          Expanded(
            child: _buildTopActionButton(
              icon: CupertinoIcons.share,
              label: 'Share',
              onTap: () {
                onDismiss();
                final shareUrl = 'https://music.youtube.com/watch?v=${song.id}';
                Clipboard.setData(ClipboardData(text: shareUrl));
                showWavifySnackBar(
                  context,
                  'Copied YouTube Music link for "${song.title}" to clipboard',
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopActionButton({
    required IconData icon,
    required String label,
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return ApplePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? const Color(0xFFFF2D55) : Colors.white,
              size: 24,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? const Color(0xFFFF2D55) : Colors.white,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderPill({
    required WidgetRef ref,
    required String label,
    required LyricsProviderType type,
    required bool isSelected,
  }) {
    return ApplePressable(
      onTap: () {
        ref.read(playerProvider.notifier).setLyricsProvider(type);
      },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.28)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white60,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ApplePressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: Center(
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w400,
                      letterSpacing: -0.2,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuDivider() {
    return Divider(
      height: 1.0,
      thickness: 0.5,
      color: Colors.white.withValues(alpha: 0.07),
      indent: 14,
      endIndent: 14,
    );
  }

  void _showAddToPlaylistSheet(BuildContext context, WidgetRef ref) {
    showAppleGlassBottomSheet(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final savedPlaylists = ref.watch(savedPlaylistsProvider);

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 14),
                child: Text(
                  'Add to playlist',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              AppleSheetActionTile(
                icon: CupertinoIcons.add,
                title: 'New Playlist',
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreatePlaylistDialog(context, ref);
                },
              ),
              const AppleSheetDivider(),
              AppleSheetActionTile(
                icon: CupertinoIcons.star_fill,
                title: 'Favorites',
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(favoritesProvider.notifier).toggleFavorite(song);
                  ref.read(musicServiceProvider).likeSong(song.id);
                  showWavifySnackBar(context, 'Added "${song.title}" to Favorites');
                },
              ),
              for (final pl in savedPlaylists) ...[
                const AppleSheetDivider(),
                AppleSheetActionTile(
                  icon: CupertinoIcons.music_albums,
                  title: pl.title,
                  subtitle: pl.author,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final success = await ref
                        .read(musicServiceProvider)
                        .addSongToPlaylist(pl.id, song.id);
                    if (context.mounted) {
                      showWavifySnackBar(
                        context,
                        success
                            ? 'Added "${song.title}" to ${pl.title}'
                            : 'Added "${song.title}" to ${pl.title} (Saved locally)',
                      );
                    }
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, WidgetRef ref) {
    final textController = TextEditingController();
    GlassDialog.show(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.10),
      settings: const LiquidGlassSettings(),
      title: 'New Playlist',
      message: 'Enter a title for this playlist.',
      maxWidth: 300,
      content: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: CupertinoTextField(
          controller: textController,
          autofocus: true,
          placeholder: 'Playlist title',
          placeholderStyle: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 14.5,
          ),
          style: const TextStyle(color: Colors.white, fontSize: 14.5),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 0.5,
            ),
          ),
        ),
      ),
      actions: [
        GlassDialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.pop(context),
        ),
        GlassDialogAction(
          label: 'Create',
          isPrimary: true,
          onPressed: () async {
            final title = textController.text.trim();
            if (title.isNotEmpty) {
              Navigator.pop(context);
              final playlistId = await ref.read(musicServiceProvider).createPlaylist(
                title,
                firstVideoId: song.id,
              ) ?? 'local_${DateTime.now().millisecondsSinceEpoch}';
              await ref.read(savedPlaylistsProvider.notifier).addPlaylist(
                PlaylistItem(
                  id: playlistId,
                  title: title,
                  author: 'You',
                  thumbnailUrl: song.thumbnailUrl,
                  trackCount: 1,
                ),
              );
              if (context.mounted) {
                showWavifySnackBar(context, 'Created playlist "$title"');
              }
            }
          },
        ),
      ],
    );
  }

  void _showSongInfoDialog(BuildContext context) {
    GlassDialog.show(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.10),
      settings: const LiquidGlassSettings(),
      title: 'Song Info',
      maxWidth: 320,
      content: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildInfoRow('Title', song.title),
            _buildInfoRow('Artist', song.artist),
            _buildInfoRow('Album', song.album ?? 'Single'),
            _buildInfoRow(
              'Duration',
              song.durationSeconds != null ? '${song.durationSeconds}s' : 'N/A',
            ),
            _buildInfoRow('Video ID', song.id),
            _buildInfoRow('Format', 'Opus Audio (bit-perfect)'),
            _buildInfoRow('Sample Rate', '48 kHz / 32-bit float'),
            _buildInfoRow('Bitrate', 'Up to 320 kbps High-Fidelity'),
          ],
        ),
      ),
      actions: [
        GlassDialogAction(
          label: 'Done',
          isPrimary: true,
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

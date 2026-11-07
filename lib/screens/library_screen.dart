import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../constants/apple_typography.dart';
import '../models/album_item.dart';
import '../models/artist_item.dart';
import '../models/playlist_item.dart';
import '../models/song_item.dart';
import '../providers/auth_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/home_data_provider.dart';
import '../providers/library_provider.dart';
import '../providers/music_service_provider.dart';
import '../providers/player_provider.dart';
import '../utils/playback_utils.dart';
import '../widgets/animated_equalizer_bars.dart';
import '../widgets/apple_glass_bottom_sheet.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/dynamic_album_artwork.dart';
import '../widgets/top_profile_avatar_button.dart';
import '../widgets/top_status_bar_blur.dart';
import '../widgets/app_shimmer.dart';
import '../widgets/wavify_cached_image.dart';

/// The Library Tab screen featuring personal collections:
/// Playlists, Liked Music, Saved Albums, Subscribed Artists, and Recently Played tracks.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
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
    final topPadding = MediaQuery.of(context).padding.top;
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth * 0.38).clamp(136.0, 180.0);
    final cardHeight = cardWidth + 58.0;

    final account = ref.watch(authProvider);
    final isLoggedIn = account != null;

    final playlistsAsync = ref.watch(userPlaylistsProvider);
    final albumsAsync = ref.watch(userAlbumsProvider);
    final artistsAsync = ref.watch(userArtistsProvider);
    final localFavorites = ref.watch(favoritesProvider);
    final ytLikesAsync = ref.watch(youtubeLikedSongsProvider);
    final recentlyPlayed = ref.watch(
      playerProvider.select((s) => s.recentlyPlayed),
    );
    final homeData = ref.watch(homeDataProvider).asData?.value;
    final trendingSongs = homeData?.trendingSongs ?? [];
    final recentHistory = recentlyPlayed.isNotEmpty
        ? recentlyPlayed
        : (homeData?.recents ?? []);

    final playlists = playlistsAsync.asData?.value ?? [];
    final albums = albumsAsync.asData?.value ?? [];
    final artists = artistsAsync.asData?.value ?? [];

    // Liked Music:
    // When logged in: Show ONLY user's YouTube Music account liked tracks merged with local favorites.
    // When logged out: Show local favorites.
    final List<SongItem> allLikedMusic;
    if (isLoggedIn) {
      final ytLikes = ytLikesAsync.asData?.value ?? [];
      final Map<String, SongItem> likedMap = {};
      for (final s in ytLikes) {
        likedMap[s.id] = s;
      }
      for (final s in localFavorites) {
        likedMap[s.id] = s;
      }
      allLikedMusic = likedMap.values.toList();
    } else {
      allLikedMusic = localFavorites;
    }

    return Stack(
      children: [
        ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: EdgeInsets.fromLTRB(0, topPadding + 14, 0, 160),
          children: [
            // 1. Library Title
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Library', style: AppleTypography.largeTitle),
                  TopProfileAvatarButton(),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 2. Playlists Section
            _buildLibrarySectionHeader(
              title: 'Playlists',
              count: playlists.length + 1,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: cardHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: playlists.length + 2,
                separatorBuilder: (context, index) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  // 0: Liked Music playlist card
                  if (index == 0) {
                    return _buildLikedMusicAlbumCard(
                      context,
                      ref,
                      cardWidth,
                      allLikedMusic,
                    );
                  }
                  // 1..playlists.length: User playlists
                  if (index <= playlists.length) {
                    final playlist = playlists[index - 1];
                    return _buildPlaylistSquareCard(
                      context,
                      ref,
                      playlist,
                      cardWidth,
                    );
                  }
                  // Last: Save Playlist action card
                  return _buildActionSquareCard(
                    cardWidth: cardWidth,
                    icon: CupertinoIcons.plus,
                    title: 'Save Playlist',
                    subtitle: 'From YouTube',
                    iconColor: Colors.white,
                    onTap: () => _showSavePlaylistSheet(context, ref),
                  );
                },
              ),
            ),
            const SizedBox(height: 28),

            // 4. Albums Section (Features Liked Music as an album + user's saved albums from YouTube)
            if (!isLoggedIn || albums.isNotEmpty) ...[
              _buildLibrarySectionHeader(title: 'Albums', count: albums.length),
              const SizedBox(height: 12),
              if (albums.isEmpty && !isLoggedIn)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildEmptySectionBanner(
                    icon: CupertinoIcons.music_albums,
                    title: 'No Saved Albums Found',
                    subtitle: 'Tap Add Album below to search and save albums to your library.',
                    actionButtonText: 'Add Album',
                    onActionTap: () => _showSearchAlbumSheet(context, ref),
                  ),
                )
              else
                SizedBox(
                  height: cardHeight,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: albums.length + 1,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      if (isLoggedIn) {
                        if (index < albums.length) {
                          final album = albums[index];
                          return _buildAlbumSquareCard(
                            context,
                            ref,
                            album,
                            cardWidth,
                          );
                        }
                        return _buildActionSquareCard(
                          cardWidth: cardWidth,
                          icon: CupertinoIcons.search,
                          title: 'Add Album',
                          subtitle: 'From YouTube',
                          iconColor: const Color(0xFFFF9500),
                          onTap: () => _showSearchAlbumSheet(context, ref),
                        );
                      }

                      if (index == 0) {
                        return _buildActionSquareCard(
                          cardWidth: cardWidth,
                          icon: CupertinoIcons.search,
                          title: 'Add Album',
                          subtitle: 'From YouTube',
                          iconColor: const Color(0xFFFF9500),
                          onTap: () => _showSearchAlbumSheet(context, ref),
                        );
                      }
                      final album = albums[index - 1];
                      return _buildAlbumSquareCard(
                        context,
                        ref,
                        album,
                        cardWidth,
                      );
                    },
                  ),
                ),
              const SizedBox(height: 28),
            ],

            // 5. Artists Section (Features user's subscribed artists from YouTube)
            if (!isLoggedIn || artists.isNotEmpty) ...[
              _buildLibrarySectionHeader(
                title: 'Artists',
                count: artists.length,
              ),
              const SizedBox(height: 12),
              if (artists.isEmpty && !isLoggedIn)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildEmptySectionBanner(
                    icon: CupertinoIcons.person_2_fill,
                    title: 'No Subscribed Artists Found',
                    subtitle: 'Tap Add Artist below to search and bookmark favorite artists.',
                    actionButtonText: 'Add Artist',
                    onActionTap: () => _showSearchArtistSheet(context, ref),
                  ),
                )
              else
                SizedBox(
                  height: cardHeight,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: artists.length + 1,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      if (isLoggedIn) {
                        if (index < artists.length) {
                          final artist = artists[index];
                          return _buildArtistSquareCard(
                            context,
                            ref,
                            artist,
                            cardWidth,
                          );
                        }
                        return _buildActionSquareCard(
                          cardWidth: cardWidth,
                          icon: CupertinoIcons.person_badge_plus,
                          title: 'Add Artist',
                          subtitle: 'From YouTube',
                          iconColor: const Color(0xFF00C7BE),
                          onTap: () => _showSearchArtistSheet(context, ref),
                        );
                      }

                      if (index == 0) {
                        return _buildActionSquareCard(
                          cardWidth: cardWidth,
                          icon: CupertinoIcons.person_badge_plus,
                          title: 'Add Artist',
                          subtitle: 'From YouTube',
                          iconColor: const Color(0xFF00C7BE),
                          onTap: () => _showSearchArtistSheet(context, ref),
                        );
                      }
                      final artist = artists[index - 1];
                      return _buildArtistSquareCard(
                        context,
                        ref,
                        artist,
                        cardWidth,
                      );
                    },
                  ),
                ),
              const SizedBox(height: 28),
            ],

            // 6. Recents Section (Just like homepage)
            if (recentHistory.isNotEmpty) ...[
              _buildLibrarySectionHeader(
                title: 'Recents',
                count: recentHistory.length,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: cardHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: recentHistory.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final song = recentHistory[index];
                    return _buildSongSquareCard(
                      context,
                      ref,
                      song,
                      cardWidth,
                      recentHistory,
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
            ],

            // 7. Trending in Your Region Section (Just like homepage)
            if (trendingSongs.isNotEmpty) ...[
              _buildLibrarySectionHeader(
                title: 'Trending in Your Region',
                count: trendingSongs.length,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: cardHeight,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: trendingSongs.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 14),
                  itemBuilder: (context, index) {
                    final song = trendingSongs[index];
                    return _buildSongSquareCard(
                      context,
                      ref,
                      song,
                      cardWidth,
                      trendingSongs,
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),
            ],
          ],
        ),
        // Dynamic Apple-style status bar blur & fading dissolve on scroll
        TopStatusBarBlur(scrollController: _scrollController),
      ],
    );
  }

  Widget _buildLibrarySectionHeader({required String title, int? count}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppleTypography.sectionTitle),
          if (count != null && count > 0)
            Text(
              '$count',
              style: const TextStyle(
                color: AppColors.appleSecondaryText,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaylistSquareCard(
    BuildContext context,
    WidgetRef ref,
    PlaylistItem playlist,
    double cardWidth,
  ) {
    return ApplePressable(
      onTap: () => playPlaylist(context, ref, playlist),
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: WavifyCachedImage(
                imageUrl: playlist.thumbnailUrl,
                width: cardWidth,
                height: cardWidth,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(14),
                placeholder: AppShimmer(
                  child: ShimmerBox(
                    width: cardWidth,
                    height: cardWidth,
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
                errorWidget: _fallbackSquareArt(
                  size: cardWidth,
                  icon: CupertinoIcons.music_note_list,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              playlist.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppleTypography.cardTitle,
            ),
            const SizedBox(height: AppleSpacing.titleToSubtitle),
            Text(
              playlist.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppleTypography.cardSubtitle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLikedMusicAlbumCard(
    BuildContext context,
    WidgetRef ref,
    double cardWidth,
    List<SongItem> songs,
  ) {
    final firstThumb = songs.isNotEmpty ? songs.first.thumbnailUrl : null;
    final likedAlbum = AlbumItem(
      id: 'LM',
      title: 'Liked Music',
      artist: '',
      thumbnailUrl: firstThumb,
      type: 'Playlist',
      year: DateTime.now().year,
    );

    return ApplePressable(
      onTap: () => openAlbumScreen(context, likedAlbum),
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: WavifyCachedImage(
                    imageUrl: firstThumb,
                    width: cardWidth,
                    height: cardWidth,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(14),
                    placeholder: AppShimmer(
                      child: ShimmerBox(
                        width: cardWidth,
                        height: cardWidth,
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                    ),
                    errorWidget: _buildLikedAlbumCover(cardWidth),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.heart_fill,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Liked Music',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppleTypography.cardTitle,
            ),
            const SizedBox(height: AppleSpacing.titleToSubtitle),
            Text(
              'Playlist • ${songs.length} tracks',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppleTypography.cardSubtitle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLikedAlbumCover(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2C2C2E), Color(0xFF141416)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(CupertinoIcons.heart_fill, color: Colors.white, size: 36),
      ),
    );
  }

  Widget _buildSongSquareCard(
    BuildContext context,
    WidgetRef ref,
    SongItem song,
    double cardWidth,
    List<SongItem> queue,
  ) {
    final isCurrent = ref.watch(
      playerProvider.select((s) => s.currentSong?.id == song.id),
    );
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));

    return ApplePressable(
      onTap: () {
        playSong(
          context,
          ref,
          song,
          contextQueue: queue.where((s) => s.id != song.id).toList(),
          forceReload: true,
        );
      },
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: WavifyCachedImage(
                    imageUrl: song.thumbnailUrl,
                    songId: song.id,
                    width: cardWidth,
                    height: cardWidth,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(14),
                    placeholder: AppShimmer(
                      child: ShimmerBox(
                        width: cardWidth,
                        height: cardWidth,
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                      ),
                    ),
                    errorWidget: _fallbackSquareArt(size: cardWidth),
                  ),
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
  }

  Widget _buildAlbumSquareCard(
    BuildContext context,
    WidgetRef ref,
    AlbumItem album,
    double cardWidth,
  ) {
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
              child: DynamicAlbumArtwork(album: album, size: cardWidth),
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
  }

  Widget _buildArtistSquareCard(
    BuildContext context,
    WidgetRef ref,
    ArtistItem artist,
    double cardWidth,
  ) {
    return ApplePressable(
      onTap: () => openArtistScreen(
        context,
        artistId: artist.id,
        artistName: artist.name,
        thumbnailUrl: artist.thumbnailUrl,
      ),
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: WavifyCachedImage(
                imageUrl: artist.thumbnailUrl,
                width: cardWidth,
                height: cardWidth,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(14),
                placeholder: AppShimmer(
                  child: ShimmerBox(
                    width: cardWidth,
                    height: cardWidth,
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
                errorWidget: _fallbackSquareArt(
                  size: cardWidth,
                  icon: CupertinoIcons.person_solid,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
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
              artist.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
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
  }

  Widget _buildActionSquareCard({
    required double cardWidth,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = Colors.white,
  }) {
    return ApplePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: cardWidth,
              height: cardWidth,
              decoration: BoxDecoration(
                color: const Color(0xFF18181C),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 28),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
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
              subtitle,
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
  }

  Widget _buildEmptySectionBanner({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionButtonText,
    VoidCallback? onActionTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: AppColors.appleSecondaryText,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.appleSecondaryText,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (actionButtonText != null && onActionTap != null) ...[
            const SizedBox(height: 14),
            ApplePressable(
              onTap: onActionTap,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.plus,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      actionButtonText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showSavePlaylistSheet(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    bool isLoading = false;
    String? errorMessage;

    showAppleGlassBottomSheet(
      context: context,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Save from YouTube',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Paste a YouTube Music or YouTube playlist link or ID to save it directly to your library.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 0.85,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.link,
                        color: Colors.white,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          autofocus: true,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'https://music.youtube.com/playlist?list=...',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.55),
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      if (controller.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            setModalState(() {
                              controller.clear();
                            });
                          },
                          child: const Icon(
                            CupertinoIcons.clear_circled_solid,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorMessage!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: ApplePressable(
                        onTap: () => Navigator.pop(modalCtx),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                              width: 0.7,
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ApplePressable(
                        onTap: isLoading
                            ? null
                            : () async {
                                final input = controller.text.trim();
                                if (input.isEmpty) {
                                  setModalState(() {
                                    errorMessage =
                                        'Please enter a playlist URL or ID.';
                                  });
                                  return;
                                }

                                setModalState(() {
                                  isLoading = true;
                                  errorMessage = null;
                                });

                                try {
                                  final musicService = ref.read(
                                    musicServiceProvider,
                                  );
                                  final playlist = await musicService
                                      .fetchYouTubePlaylist(input);

                                  if (playlist != null) {
                                    ref
                                        .read(savedPlaylistsProvider.notifier)
                                        .addPlaylist(playlist);
                                    if (modalCtx.mounted) {
                                      Navigator.pop(modalCtx);
                                    }
                                    if (context.mounted) {
                                      showWavifySnackBar(
                                        context,
                                        'Saved "${playlist.title}" to Playlists',
                                      );
                                    }
                                  } else {
                                    setModalState(() {
                                      isLoading = false;
                                      errorMessage = 'Could not resolve playlist. Check link and try again.';
                                    });
                                  }
                                } catch (e) {
                                  setModalState(() {
                                    isLoading = false;
                                    errorMessage = 'Error saving playlist: $e';
                                  });
                                }
                              },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.black,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Save Playlist',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSearchArtistSheet(BuildContext context, WidgetRef ref) {
    final searchController = TextEditingController();
    List<ArtistItem> searchResults = [];
    bool isSearching = false;

    showAppleGlassBottomSheet(
      context: context,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final savedArtists = ref.watch(savedArtistsProvider);

            Future<void> executeSearch(String q) async {
              if (q.trim().isEmpty) return;
              setModalState(() {
                isSearching = true;
              });
              try {
                final musicService = ref.read(musicServiceProvider);
                final results = await musicService.searchArtists(q);
                setModalState(() {
                  searchResults = results;
                  isSearching = false;
                });
              } catch (e) {
                setModalState(() {
                  isSearching = false;
                });
              }
            }

            final maxHeight = MediaQuery.sizeOf(modalCtx).height * 0.72;
            return SizedBox(
              height: maxHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Add Favorite Artist',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.4,
                        ),
                      ),
                      ApplePressable(
                        onTap: () => Navigator.pop(modalCtx),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.xmark,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 0.85,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.search,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            autofocus: true,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search artists on YouTube...',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                            ),
                            onSubmitted: executeSearch,
                          ),
                        ),
                        if (isSearching)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        else if (searchController.text.isNotEmpty)
                          GestureDetector(
                            onTap: () => executeSearch(searchController.text),
                            child: const Text(
                              'Search',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: searchResults.isEmpty && !isSearching
                        ? const Center(
                            child: Text(
                              'Search for an artist and tap + to add them to your library.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 14,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: searchResults.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final artist = searchResults[index];
                              final isSaved = savedArtists.any(
                                (a) => a.id == artist.id,
                              );

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.10),
                                    width: 0.6,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(22),
                                      child: WavifyCachedImage(
                                        imageUrl: artist.thumbnailUrl,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        borderRadius:
                                            BorderRadius.circular(22),
                                        placeholder: const AppShimmer(
                                          child: ShimmerBox.circle(size: 44),
                                        ),
                                        errorWidget: _fallbackSquareArt(
                                          size: 44,
                                          icon: CupertinoIcons.person_solid,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            artist.name,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            artist.subtitle,
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.85,
                                              ),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        isSaved
                                            ? CupertinoIcons
                                                  .checkmark_circle_fill
                                            : CupertinoIcons.plus_circle,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                      onPressed: () {
                                        ref
                                            .read(savedArtistsProvider.notifier)
                                            .toggleArtist(artist);
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showSearchAlbumSheet(BuildContext context, WidgetRef ref) {
    final searchController = TextEditingController();
    List<AlbumItem> searchResults = [];
    bool isSearching = false;

    showAppleGlassBottomSheet(
      context: context,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final savedAlbums = ref.watch(savedAlbumsProvider);

            Future<void> executeSearch(String q) async {
              if (q.trim().isEmpty) return;
              setModalState(() {
                isSearching = true;
              });
              try {
                final musicService = ref.read(musicServiceProvider);
                final results = await musicService.searchAlbums(q);
                setModalState(() {
                  searchResults = results;
                  isSearching = false;
                });
              } catch (e) {
                setModalState(() {
                  isSearching = false;
                });
              }
            }

            final maxHeight = MediaQuery.sizeOf(modalCtx).height * 0.72;
            return SizedBox(
              height: maxHeight,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Add Favorite Album',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.4,
                        ),
                      ),
                      ApplePressable(
                        onTap: () => Navigator.pop(modalCtx),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.xmark,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 0.85,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(
                          CupertinoIcons.search,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: searchController,
                            autofocus: true,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search albums on YouTube...',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                            ),
                            onSubmitted: executeSearch,
                          ),
                        ),
                        if (isSearching)
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        else if (searchController.text.isNotEmpty)
                          GestureDetector(
                            onTap: () => executeSearch(searchController.text),
                            child: const Text(
                              'Search',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: searchResults.isEmpty && !isSearching
                        ? const Center(
                            child: Text(
                              'Search for an album and tap + to add it to your library.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 14,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: searchResults.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final album = searchResults[index];
                              final isSaved = savedAlbums.any(
                                (a) => a.id == album.id,
                              );

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.10),
                                    width: 0.6,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: WavifyCachedImage(
                                        imageUrl: album.thumbnailUrl,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        borderRadius:
                                            BorderRadius.circular(8),
                                        placeholder: const AppShimmer(
                                          child: ShimmerBox(
                                            width: 44,
                                            height: 44,
                                            borderRadius: BorderRadius.all(
                                                Radius.circular(8)),
                                          ),
                                        ),
                                        errorWidget: _fallbackSquareArt(
                                          size: 44,
                                          icon: CupertinoIcons.music_albums,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            album.title,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            album.subtitle,
                                            style: TextStyle(
                                              color: Colors.white.withValues(
                                                alpha: 0.85,
                                              ),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        isSaved
                                            ? CupertinoIcons
                                                  .checkmark_circle_fill
                                            : CupertinoIcons.plus_circle,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                      onPressed: () {
                                        ref
                                            .read(savedAlbumsProvider.notifier)
                                            .toggleAlbum(album);
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
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

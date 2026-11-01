import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/album_item.dart';
import '../models/artist_item.dart';
import '../models/playlist_item.dart';
import '../models/song_item.dart';
import '../providers/auth_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/library_provider.dart';
import '../providers/music_service_provider.dart';
import '../providers/player_provider.dart';
import '../utils/playback_utils.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/dynamic_album_artwork.dart';

/// The Library Tab screen featuring personal collections:
/// Playlists, Liked Music, Saved Albums, Subscribed Artists, and Recently Played tracks.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

    final playlists = playlistsAsync.value ?? [];
    final albums = albumsAsync.value ?? [];
    final artists = artistsAsync.value ?? [];

    // Liked Music:
    // When logged in: Show ONLY user's YouTube Music account liked tracks merged with local favorites.
    // When logged out: Show local favorites.
    final List<SongItem> allLikedMusic;
    if (isLoggedIn) {
      final ytLikes = ytLikesAsync.value ?? [];
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 160),
      children: [
        // 1. Library Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Library',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -1.2,
                ),
              ),
              if (account != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.checkmark_seal_fill,
                        color: Colors.greenAccent,
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        account.displayName.split(' ').first,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 2. Playlists Section
        _buildLibrarySectionHeader(title: 'Playlists', count: playlists.length),
        const SizedBox(height: 12),
        if (playlists.isEmpty && isLoggedIn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildEmptySectionBanner(
              icon: CupertinoIcons.music_note_list,
              title: 'No Playlists Found',
              subtitle:
                  'Tap Save Playlist below to import any YouTube playlist.',
              actionButtonText: 'Save Playlist',
              onActionTap: () => _showSavePlaylistSheet(context, ref),
            ),
          )
        else
          SizedBox(
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: playlists.length + 1,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _buildActionSquareCard(
                    cardWidth: cardWidth,
                    icon: CupertinoIcons.plus,
                    title: 'Save Playlist',
                    subtitle: 'From YouTube',
                    iconColor: AppColors.appleRed,
                    onTap: () => _showSavePlaylistSheet(context, ref),
                  );
                }
                final playlist = playlists[index - 1];
                return _buildPlaylistSquareCard(
                  context,
                  ref,
                  playlist,
                  cardWidth,
                );
              },
            ),
          ),
        const SizedBox(height: 28),

        // 3. Liked Music Section
        _buildLibrarySectionHeader(
          title: 'Liked Music',
          count: allLikedMusic.length,
        ),
        const SizedBox(height: 12),
        if (allLikedMusic.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildEmptySectionBanner(
              icon: CupertinoIcons.heart,
              title: isLoggedIn ? 'No Liked Music Found' : 'No Liked Music Yet',
              subtitle: isLoggedIn
                  ? 'Tracks you like on YouTube Music or star in Wavify will appear here.'
                  : 'Star songs locally or sign in with YouTube Music to import your liked tracks.',
            ),
          )
        else
          SizedBox(
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: allLikedMusic.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final song = allLikedMusic[index];
                return _buildSongSquareCard(
                  context,
                  ref,
                  song,
                  cardWidth,
                  allLikedMusic,
                );
              },
            ),
          ),
        const SizedBox(height: 28),

        // 4. Albums Section
        _buildLibrarySectionHeader(title: 'Albums', count: albums.length),
        const SizedBox(height: 12),
        if (albums.isEmpty && isLoggedIn)
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
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
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
                return _buildAlbumSquareCard(context, ref, album, cardWidth);
              },
            ),
          ),
        const SizedBox(height: 28),

        // 5. Artists Section
        _buildLibrarySectionHeader(title: 'Artists', count: artists.length),
        const SizedBox(height: 12),
        if (artists.isEmpty && isLoggedIn)
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
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
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
                return _buildArtistSquareCard(context, ref, artist, cardWidth);
              },
            ),
          ),
        const SizedBox(height: 28),

        // 6. Recently Played Section
        if (recentlyPlayed.isNotEmpty) ...[
          _buildLibrarySectionHeader(
            title: 'Recently Played',
            count: recentlyPlayed.length,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: cardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: recentlyPlayed.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final song = recentlyPlayed[index];
                return _buildSongSquareCard(
                  context,
                  ref,
                  song,
                  cardWidth,
                  recentlyPlayed,
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLibrarySectionHeader({required String title, int? count}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              child: playlist.thumbnailUrl != null
                  ? Image.network(
                      playlist.thumbnailUrl!,
                      width: cardWidth,
                      height: cardWidth,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _fallbackSquareArt(
                            size: cardWidth,
                            icon: CupertinoIcons.music_note_list,
                          ),
                    )
                  : _fallbackSquareArt(
                      size: cardWidth,
                      icon: CupertinoIcons.music_note_list,
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              playlist.title,
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
              playlist.subtitle,
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
                  child: song.thumbnailUrl != null
                      ? Image.network(
                          song.thumbnailUrl!,
                          width: cardWidth,
                          height: cardWidth,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _fallbackSquareArt(size: cardWidth),
                        )
                      : _fallbackSquareArt(size: cardWidth),
                ),
                if (isCurrent && isPlaying)
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
                        size: 14,
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
            Text(
              song.artist,
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
      onTap: () => playArtist(context, ref, artist),
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: artist.thumbnailUrl != null
                  ? Image.network(
                      artist.thumbnailUrl!,
                      width: cardWidth,
                      height: cardWidth,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _fallbackSquareArt(
                            size: cardWidth,
                            icon: CupertinoIcons.person_solid,
                          ),
                    )
                  : _fallbackSquareArt(
                      size: cardWidth,
                      icon: CupertinoIcons.person_solid,
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
    Color iconColor = AppColors.appleRed,
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
                      color: AppColors.appleRed,
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalCtx).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                decoration: const BoxDecoration(
                  color: Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Save from YouTube',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Paste a YouTube Music or YouTube playlist link or ID to save it directly to your library.',
                      style: TextStyle(
                        color: AppColors.appleSecondaryText,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(
                            CupertinoIcons.link,
                            color: AppColors.appleSecondaryText,
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
                              decoration: const InputDecoration(
                                hintText: 'https://music.youtube.com/playlist?list=...',
                                hintStyle: TextStyle(
                                  color: Colors.white38,
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
                                color: AppColors.appleSecondaryText,
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
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: ApplePressable(
                            onTap: () => Navigator.pop(modalCtx),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
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
                                        errorMessage = 'Please enter a playlist URL or ID.';
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
                                            .read(
                                              savedPlaylistsProvider.notifier,
                                            )
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
                                        errorMessage =
                                            'Error saving playlist: $e';
                                      });
                                    }
                                  },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppColors.appleRed,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    )
                                  : const Text(
                                      'Save Playlist',
                                      style: TextStyle(
                                        color: Colors.white,
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
                ),
              ),
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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

            return Container(
              height: MediaQuery.of(modalCtx).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Color(0xFF1C1C1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Add Favorite Artist',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            CupertinoIcons.xmark_circle_fill,
                            color: Colors.white54,
                          ),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(
                            CupertinoIcons.search,
                            color: AppColors.appleSecondaryText,
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
                              decoration: const InputDecoration(
                                hintText: 'Search artists on YouTube...',
                                hintStyle: TextStyle(
                                  color: Colors.white38,
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
                                color: AppColors.appleRed,
                              ),
                            )
                          else if (searchController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () => executeSearch(searchController.text),
                              child: const Text(
                                'Search',
                                style: TextStyle(
                                  color: AppColors.appleRed,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
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
                                color: AppColors.appleSecondaryText,
                                fontSize: 14,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            itemCount: searchResults.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
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
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(22),
                                      child: artist.thumbnailUrl != null
                                          ? Image.network(
                                              artist.thumbnailUrl!,
                                              width: 44,
                                              height: 44,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => _fallbackSquareArt(
                                                    size: 44,
                                                    icon: CupertinoIcons
                                                        .person_solid,
                                                  ),
                                            )
                                          : _fallbackSquareArt(
                                              size: 44,
                                              icon: CupertinoIcons.person_solid,
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
                                            style: const TextStyle(
                                              color:
                                                  AppColors.appleSecondaryText,
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
                                        color: isSaved
                                            ? Colors.greenAccent
                                            : AppColors.appleRed,
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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

            return Container(
              height: MediaQuery.of(modalCtx).size.height * 0.75,
              decoration: const BoxDecoration(
                color: Color(0xFF1C1C1E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Add Favorite Album',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            CupertinoIcons.xmark_circle_fill,
                            color: Colors.white54,
                          ),
                          onPressed: () => Navigator.pop(modalCtx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(
                            CupertinoIcons.search,
                            color: AppColors.appleSecondaryText,
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
                              decoration: const InputDecoration(
                                hintText: 'Search albums on YouTube...',
                                hintStyle: TextStyle(
                                  color: Colors.white38,
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
                                color: AppColors.appleRed,
                              ),
                            )
                          else if (searchController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () => executeSearch(searchController.text),
                              child: const Text(
                                'Search',
                                style: TextStyle(
                                  color: AppColors.appleRed,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
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
                                color: AppColors.appleSecondaryText,
                                fontSize: 14,
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            itemCount: searchResults.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
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
                                  color: Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: album.thumbnailUrl != null
                                          ? Image.network(
                                              album.thumbnailUrl!,
                                              width: 44,
                                              height: 44,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => _fallbackSquareArt(
                                                    size: 44,
                                                    icon: CupertinoIcons
                                                        .music_albums,
                                                  ),
                                            )
                                          : _fallbackSquareArt(
                                              size: 44,
                                              icon: CupertinoIcons.music_albums,
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
                                            style: const TextStyle(
                                              color:
                                                  AppColors.appleSecondaryText,
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
                                        color: isSaved
                                            ? Colors.greenAccent
                                            : AppColors.appleRed,
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

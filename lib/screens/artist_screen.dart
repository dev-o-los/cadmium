import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../constants/app_colors.dart';
import '../models/album_item.dart';
import '../models/artist_details.dart';
import '../models/artist_item.dart';
import '../models/playlist_item.dart';
import '../models/song_item.dart';
import '../models/user_account.dart';
import '../models/video_item.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../providers/music_service_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/player_provider.dart';
import '../utils/playback_utils.dart';
import '../widgets/account_modal_sheet.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/liquid_glass_bottom_bar.dart';
import '../widgets/player_controls.dart';
import '../widgets/track_options_sheet.dart';

/// Full-Page Artist View matching the Apple Music aesthetic and YouTube Music data:
/// - Sticky ambient top bar with floating back button, share, and account avatar
/// - Large artist hero banner with smooth progressive blur dissolve into OLED black
/// - Artist name, subscriber & monthly audience pill badges, Shuffle & Radio action row
/// - Spotlight card for recent single / latest release
/// - Top songs numbered list with drag indicators, explicit [E] badges, and 3-dots menus
/// - Horizontal carousels for Albums, Singles & EPs, Videos, Featured on, Playlists by Artist, and Fans might also like
/// - Expandable "About the artist" biography with subscriber and monthly listeners pills
/// - Floating liquid glass mini player dock at the bottom
class ArtistScreen extends ConsumerStatefulWidget {
  final String? artistId;
  final String? artistName;
  final String? initialThumbnailUrl;

  const ArtistScreen({
    super.key,
    this.artistId,
    this.artistName,
    this.initialThumbnailUrl,
  });

  @override
  ConsumerState<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends ConsumerState<ArtistScreen> {
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  ArtistDetails? _artistDetails;
  bool _isDescriptionExpanded = false;

  // Mini player dock crawl / minimization state
  bool _isMiniPlayerCrawled = false;
  double _accumulatedScrollDelta = 0.0;
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadArtistDetails();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    setState(() {
      _scrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final pixels = notification.metrics.pixels;
    if (pixels <= 25) {
      if (_isMiniPlayerCrawled) {
        setState(() => _isMiniPlayerCrawled = false);
      }
      _accumulatedScrollDelta = 0;
      return false;
    }

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.reverse && !_isMiniPlayerCrawled) {
        setState(() => _isMiniPlayerCrawled = true);
      } else if (notification.direction == ScrollDirection.forward && _isMiniPlayerCrawled) {
        setState(() => _isMiniPlayerCrawled = false);
      }
    } else if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;
      if (delta > 0) {
        _accumulatedScrollDelta =
            (_accumulatedScrollDelta > 0 ? _accumulatedScrollDelta : 0) + delta;
        if (_accumulatedScrollDelta > 20 && !_isMiniPlayerCrawled) {
          setState(() => _isMiniPlayerCrawled = true);
        }
      } else if (delta < 0) {
        _accumulatedScrollDelta =
            (_accumulatedScrollDelta < 0 ? _accumulatedScrollDelta : 0) + delta;
        if (_accumulatedScrollDelta < -12 && _isMiniPlayerCrawled) {
          setState(() => _isMiniPlayerCrawled = false);
        }
      }
    }

    return false;
  }

  Future<void> _loadArtistDetails() async {
    final musicService = ref.read(musicServiceProvider);
    final queryIdOrName = widget.artistId ?? widget.artistName ?? '';

    try {
      final details = await musicService.getArtistDetails(
        queryIdOrName,
        fallbackName: widget.artistName,
      );
      if (mounted) {
        setState(() {
          _artistDetails = details;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading artist details: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String get _displayName {
    return _artistDetails?.name ?? widget.artistName ?? 'Artist';
  }

  String? get _heroBannerUrl {
    return _artistDetails?.bannerUrl ??
        _artistDetails?.thumbnailUrl ??
        widget.initialThumbnailUrl;
  }

  void _shuffleArtistTracks() {
    final tracks = _artistDetails?.topSongs ?? [];
    if (tracks.isEmpty) {
      showWavifySnackBar(context, 'No playable tracks for $_displayName');
      return;
    }
    final shuffled = List<SongItem>.from(tracks)..shuffle();
    final firstTrack = shuffled.first;
    final queue = shuffled.length > 1 ? shuffled.sublist(1) : <SongItem>[];

    playSong(
      context,
      ref,
      firstTrack,
      contextQueue: queue,
      autoOpenPlayer: false,
      forceReload: true,
    );
    showWavifySnackBar(context, 'Shuffling $_displayName top tracks');
  }

  bool get _isPlayingThisArtist {
    final playerState = ref.watch(playerProvider);
    if (!playerState.isPlaying || playerState.currentSong == null) return false;
    final current = playerState.currentSong!.artist.toLowerCase();
    final target = _displayName.toLowerCase();
    return current.contains(target) || target.contains(current);
  }

  void _togglePlayArtist() {
    final playerState = ref.read(playerProvider);
    if (playerState.currentSong != null) {
      final current = playerState.currentSong!.artist.toLowerCase();
      final target = _displayName.toLowerCase();
      if (current.contains(target) || target.contains(current)) {
        ref.read(playerProvider.notifier).togglePlayPause();
        return;
      }
    }
    final tracks = _artistDetails?.topSongs ?? [];
    if (tracks.isEmpty) {
      showWavifySnackBar(context, 'No playable tracks for $_displayName');
      return;
    }
    playSong(
      context,
      ref,
      tracks.first,
      contextQueue: tracks.length > 1 ? tracks.sublist(1) : [],
      autoOpenPlayer: false,
      forceReload: true,
    );
    showWavifySnackBar(context, 'Playing $_displayName');
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final currentSong = playerState.currentSong;
    final currentTabIndex = ref.watch(currentTabProvider);
    final userAccount = ref.watch(authProvider);

    final artistId = _artistDetails?.id ?? widget.artistId ?? '';
    final isSaved = ref.watch(savedArtistsProvider.select((list) {
      return list.any((a) => a.id == artistId || (a.name.toLowerCase() == _displayName.toLowerCase()));
    }));

    // Find any albums from library matching this artist
    final savedAlbums = ref.watch(savedAlbumsProvider);
    final matchingLibraryAlbums = savedAlbums.where((a) {
      return a.artist.toLowerCase().contains(_displayName.toLowerCase()) ||
          _displayName.toLowerCase().contains(a.artist.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Background ambient artwork and scrollable content
          NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                // Top Ambient Banner / Hero Artwork with smooth dissolve
                _buildSliverHeroHeader(),

                // Main Artist Content Sections
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Artist Metadata & Action Buttons Row
                        _buildHeroMetadata(isSaved),

                        const SizedBox(height: 16),

                        // Spotlight Recent Single / Release Card (Screenshot 4)
                        if (_artistDetails?.recentRelease != null) ...[
                          _buildRecentReleaseCard(_artistDetails!.recentRelease!),
                          const SizedBox(height: 24),
                        ],

                        // Top Songs Section (Screenshot 4)
                        _buildTopSongsSection(),

                        const SizedBox(height: 28),

                        // Albums Carousel (Screenshot 3 & 4)
                        if (_artistDetails?.albums.isNotEmpty == true) ...[
                          _buildAlbumsSection(_artistDetails!.albums),
                          const SizedBox(height: 28),
                        ],

                        // Singles & EPs Carousel (Screenshot 3 & 4)
                        if (_artistDetails?.singles.isNotEmpty == true) ...[
                          _buildSinglesSection(_artistDetails!.singles),
                          const SizedBox(height: 28),
                        ],

                        // Music Videos Carousel (Screenshot 3 & 5)
                        if (_artistDetails?.videos.isNotEmpty == true) ...[
                          _buildVideosSection(_artistDetails!.videos),
                          const SizedBox(height: 28),
                        ],

                        // From Your Library Section (Screenshot 3 & 5)
                        if (matchingLibraryAlbums.isNotEmpty) ...[
                          _buildLibrarySection(matchingLibraryAlbums),
                          const SizedBox(height: 28),
                        ],

                        // Featured On Carousel (Screenshot 5 & 1)
                        if (_artistDetails?.featuredOn.isNotEmpty == true) ...[
                          _buildFeaturedOnSection(_artistDetails!.featuredOn),
                          const SizedBox(height: 28),
                        ],

                        // Playlists by Artist Carousel (Screenshot 1 & 5)
                        if (_artistDetails?.playlistsByArtist.isNotEmpty == true) ...[
                          _buildPlaylistsByArtistSection(_artistDetails!.playlistsByArtist),
                          const SizedBox(height: 28),
                        ],

                        // Fans Might Also Like Carousel (Screenshot 1 & 2)
                        if (_artistDetails?.similarArtists.isNotEmpty == true) ...[
                          _buildFansMightLikeSection(_artistDetails!.similarArtists),
                          const SizedBox(height: 28),
                        ],

                        // About the Artist Description & Stat Pills (Screenshot 1 & 2)
                        _buildAboutArtistSection(),

                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Floating Top Navigation Bar with Back, Sticky Title, and Right Actions
          _buildFloatingTopNavBar(userAccount),

          // Floating Mini Player + Liquid Glass Bottom Dock
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: LiquidGlassBottomBar(
                currentIndex: currentTabIndex,
                isCrawled: _isMiniPlayerCrawled,
                onTabSelected: (index) {
                  ref.read(currentTabProvider.notifier).state = index;
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
                onExpand: () {
                  setState(() => _isMiniPlayerCrawled = false);
                },
                bottomAccessory: currentSong != null
                    ? PlayerControls(
                        onTap: () => openPlayerScreen(context),
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Sliver Hero Banner with ambient progressive blur dissolve into deep dark background
  Widget _buildSliverHeroHeader() {
    final banner = _heroBannerUrl;
    final topPadding = MediaQuery.of(context).padding.top;
    final bannerHeight = 380.0 + topPadding;

    return SliverToBoxAdapter(
      child: SizedBox(
        height: bannerHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background Artwork Image with Bicubic Filtering
            if (banner != null)
              Image.network(
                banner,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) => _fallbackBanner(),
              )
            else
              _fallbackBanner(),

            // Multi-stop progressive gradient mask dissolving cleanly into OLED black
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.40, 0.75, 1.0],
                    colors: [
                      Colors.black.withValues(alpha: 0.25),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                      Colors.black,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Floating Top Navigation Bar: Back button, Sticky title on scroll, and Share/Account actions
  Widget _buildFloatingTopNavBar(UserAccount? account) {
    final topPadding = MediaQuery.of(context).padding.top;
    final showStickyTitle = _scrollOffset > 240;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: topPadding + 54,
        padding: EdgeInsets.fromLTRB(16, topPadding, 16, 6),
        decoration: BoxDecoration(
          color: showStickyTitle ? Colors.black.withValues(alpha: 0.88) : Colors.transparent,
        ),
        child: Row(
          children: [
            // Floating circular Liquid Glass Back button
            GlassIconButton(
              icon: const Icon(
                CupertinoIcons.chevron_back,
                color: Colors.white,
                size: 22,
              ),
              onPressed: () => Navigator.maybePop(context),
              size: 42,
              iconSize: 22,
              shape: GlassIconButtonShape.circle,
              useOwnLayer: true,
              settings: const LiquidGlassSettings(
                glassColor: Color(0x33FFFFFF),
                thickness: 20,
                blur: 24,
                refractiveIndex: 1.15,
                lightIntensity: 0.45,
                specularSharpness: GlassSpecularSharpness.sharp,
              ),
            ),

            const SizedBox(width: 12),

            // Animated Sticky Title dissolving in when scrolling
            Expanded(
              child: AnimatedOpacity(
                opacity: showStickyTitle ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                child: Text(
                  _displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Right Action Pill in Liquid Glass: Share Button + User Avatar Circle
            GlassContainer(
              height: 42,
              shape: const LiquidRoundedSuperellipse(borderRadius: 21),
              color: const Color(0x33FFFFFF),
              useOwnLayer: true,
              settings: const LiquidGlassSettings(
                thickness: 20,
                blur: 24,
                refractiveIndex: 1.18,
                lightIntensity: 0.45,
                specularSharpness: GlassSpecularSharpness.sharp,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Share button
                    ApplePressable(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        showWavifySnackBar(context, 'Sharing $_displayName');
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Icon(
                          CupertinoIcons.share,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Account Avatar circle
                    ApplePressable(
                      onTap: () => showAccountModalSheet(context, ref),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.8),
                            width: 1.5,
                          ),
                        ),
                        child: ClipOval(
                          child: account?.avatarUrl != null
                              ? Image.network(
                                  account!.avatarUrl!,
                                  width: 30,
                                  height: 30,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(CupertinoIcons.person_crop_circle, color: Colors.white, size: 20),
                                )
                              : const Icon(CupertinoIcons.person_crop_circle, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Artist Header Metadata & Centered Action Row (Shuffle, Play, Star)
  Widget _buildHeroMetadata(bool isSaved) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Centered Artist Title
          Center(
            child: Text(
              _displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.6,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Center Liquid Glass Action Row: [Shuffle] [Large Play] [Star]
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. Shuffle (Liquid Glass circular button)
              GlassIconButton(
                icon: const Icon(
                  CupertinoIcons.shuffle,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: _shuffleArtistTracks,
                size: 56,
                iconSize: 22,
                shape: GlassIconButtonShape.circle,
                useOwnLayer: true,
                settings: const LiquidGlassSettings(
                  glassColor: Color(0x33FFFFFF),
                  thickness: 22,
                  blur: 24,
                  refractiveIndex: 1.15,
                  lightIntensity: 0.45,
                  specularSharpness: GlassSpecularSharpness.sharp,
                ),
              ),

              const SizedBox(width: 22),

              // 2. Center Prominent Play Button (74px White Circle)
              ApplePressable(
                onTap: _togglePlayArtist,
                borderRadius: BorderRadius.circular(37),
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.15),
                        blurRadius: 18,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      _isPlayingThisArtist ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                      color: Colors.black,
                      size: 32,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 22),

              // 3. Star / Favorite (Liquid Glass circular button)
              GlassIconButton(
                icon: Icon(
                  CupertinoIcons.star_fill,
                  color: isSaved ? AppColors.appleRed : Colors.white,
                  size: 22,
                ),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  final item = ArtistItem(
                    id: _artistDetails?.id ?? widget.artistId ?? 'artist_${_displayName.hashCode}',
                    name: _displayName,
                    thumbnailUrl: _heroBannerUrl,
                    subscribers: _artistDetails?.subscribers,
                    isCustom: true,
                  );
                  final added = await ref.read(savedArtistsProvider.notifier).toggleArtist(item);
                  if (mounted) {
                    showWavifySnackBar(
                      context,
                      added ? 'Added $_displayName to your Library' : 'Removed $_displayName from Library',
                    );
                  }
                },
                size: 56,
                iconSize: 22,
                shape: GlassIconButtonShape.circle,
                useOwnLayer: true,
                settings: const LiquidGlassSettings(
                  glassColor: Color(0x33FFFFFF),
                  thickness: 22,
                  blur: 24,
                  refractiveIndex: 1.15,
                  lightIntensity: 0.45,
                  specularSharpness: GlassSpecularSharpness.sharp,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Spotlight Card for Recent Single / Latest Release (matching screenshot)
  Widget _buildRecentReleaseCard(AlbumItem recent) {
    final isRecentSaved = ref.watch(savedAlbumsProvider.select((list) {
      return list.any((a) => a.id == recent.id);
    }));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ApplePressable(
        onTap: () => openAlbumScreen(context, recent),
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: const Color(0xFF1E1E26),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.5),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: recent.thumbnailUrl != null
                    ? Image.network(
                        recent.thumbnailUrl!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                        errorBuilder: (context, error, stackTrace) => _fallbackSquareArt(72),
                      )
                    : _fallbackSquareArt(72),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      recent.year != null ? 'Single • ${recent.year}' : 'Single',
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      recent.title,
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
                    const Text(
                      'Recent Single',
                      style: TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              // Liquid Glass Circular [+] button
              GlassIconButton(
                icon: Icon(
                  isRecentSaved ? CupertinoIcons.checkmark_alt : CupertinoIcons.plus,
                  color: isRecentSaved ? AppColors.appleRed : Colors.white,
                  size: 20,
                ),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  final added = await ref.read(savedAlbumsProvider.notifier).toggleAlbum(recent);
                  if (mounted) {
                    showWavifySnackBar(
                      context,
                      added ? 'Saved "${recent.title}" to Library' : 'Removed "${recent.title}" from Library',
                    );
                  }
                },
                size: 40,
                iconSize: 20,
                shape: GlassIconButtonShape.circle,
                useOwnLayer: true,
                settings: const LiquidGlassSettings(
                  glassColor: Color(0x33FFFFFF),
                  thickness: 20,
                  blur: 20,
                  refractiveIndex: 1.15,
                  lightIntensity: 0.40,
                  specularSharpness: GlassSpecularSharpness.sharp,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Top Songs Section: 4-Item Vertical Stack Column with horizontal paging (matching screenshot)
  Widget _buildTopSongsSection() {
    final songs = _artistDetails?.topSongs ?? [];
    if (songs.isEmpty && !_isLoading) {
      return const SizedBox.shrink();
    }

    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));

    // Chunk songs into columns of 4 (matches YouTube Music / screenshot horizontal paging layout)
    final columns = <List<SongItem>>[];
    for (var i = 0; i < songs.length; i += 4) {
      columns.add(songs.sublist(i, math.min(i + 4, songs.length)));
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final columnWidth = screenWidth > 60 ? screenWidth - 48 : 320.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Top songs',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.6,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoading && songs.isEmpty)
          _buildTopSongsSkeleton()
        else
          SizedBox(
            height: 248,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: columns.length,
              separatorBuilder: (context, index) => const SizedBox(width: 14),
              itemBuilder: (context, columnIndex) {
                final columnSongs = columns[columnIndex];
                return SizedBox(
                  width: columns.length > 1 ? columnWidth : (screenWidth > 60 ? screenWidth - 40 : 340.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: columnSongs.map((song) {
                      final isCurrent = currentSong?.id == song.id;

                      return ApplePressable(
                        onTap: () => playSong(context, ref, song, contextQueue: songs),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              // Artwork thumbnail
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Stack(
                                  children: [
                                    song.thumbnailUrl != null
                                        ? Image.network(
                                            song.thumbnailUrl!,
                                            width: 48,
                                            height: 48,
                                            fit: BoxFit.cover,
                                            filterQuality: FilterQuality.medium,
                                            errorBuilder: (context, error, stackTrace) =>
                                                _fallbackSquareArt(48),
                                          )
                                        : _fallbackSquareArt(48),
                                    if (isCurrent)
                                      Positioned.fill(
                                        child: Container(
                                          color: Colors.black.withValues(alpha: 0.55),
                                          child: Center(
                                            child: Icon(
                                              isPlaying
                                                  ? CupertinoIcons.speaker_2_fill
                                                  : CupertinoIcons.pause_fill,
                                              color: AppColors.appleRed,
                                              size: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Title & Artist metadata
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        // Explicit Badge [E]
                                        _buildExplicitBadge(),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            song.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: isCurrent ? AppColors.appleRed : Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      song.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Color(0xFF8E8E93),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Liquid Glass 3-dots action button
                              GlassIconButton(
                                icon: const Icon(
                                  CupertinoIcons.ellipsis_vertical,
                                  color: Color(0xFF8E8E93),
                                  size: 18,
                                ),
                                onPressed: () => showTrackOptionsModal(context, ref, song),
                                size: 36,
                                iconSize: 18,
                                shape: GlassIconButtonShape.circle,
                                useOwnLayer: true,
                                settings: const LiquidGlassSettings(
                                  glassColor: Color(0x22FFFFFF),
                                  thickness: 16,
                                  blur: 16,
                                  refractiveIndex: 1.12,
                                  lightIntensity: 0.35,
                                  specularSharpness: GlassSpecularSharpness.sharp,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// Albums Section Carousel with Show All (Screenshot 3 & 4)
  Widget _buildAlbumsSection(List<AlbumItem> albums) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Albums', onShowAll: () => _openAlbumListModal('Albums', albums)),
        const SizedBox(height: 12),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: albums.length > 12 ? 12 : albums.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final album = albums[index];
              return _buildAlbumCard(album);
            },
          ),
        ),
      ],
    );
  }

  /// Singles & EPs Section Carousel with Show All (Screenshot 3 & 4)
  Widget _buildSinglesSection(List<AlbumItem> singles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Singles & EPs', onShowAll: () => _openAlbumListModal('Singles & EPs', singles)),
        const SizedBox(height: 12),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: singles.length > 12 ? 12 : singles.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final single = singles[index];
              return _buildAlbumCard(single);
            },
          ),
        ),
      ],
    );
  }

  /// Videos Section Widescreen 16:9 Carousel (Screenshot 3 & 5)
  Widget _buildVideosSection(List<VideoItem> videos) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Videos'),
        const SizedBox(height: 12),
        SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: videos.length > 10 ? 10 : videos.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final video = videos[index];
              const cardWidth = 220.0;
              const cardHeight = 124.0;

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
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: cardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          children: [
                            video.thumbnailUrl != null
                                ? Image.network(
                                    video.thumbnailUrl!,
                                    width: cardWidth,
                                    height: cardHeight,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.medium,
                                    errorBuilder: (context, error, stackTrace) =>
                                        _fallbackWidescreenArt(cardWidth, cardHeight),
                                  )
                                : _fallbackWidescreenArt(cardWidth, cardHeight),
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
                                  size: 12,
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
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        video.views != null ? '${video.artist} • ${video.views}' : video.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
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

  /// From Your Library Section (Screenshot 3 & 5)
  Widget _buildLibrarySection(List<AlbumItem> libraryAlbums) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'From your library',
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
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: libraryAlbums.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) => _buildAlbumCard(libraryAlbums[index]),
          ),
        ),
      ],
    );
  }

  /// Featured On Playlist Carousel (Screenshot 5 & 1)
  Widget _buildFeaturedOnSection(List<PlaylistItem> playlists) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Featured on'),
        const SizedBox(height: 12),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: playlists.length > 10 ? 10 : playlists.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return _buildPlaylistCard(playlist);
            },
          ),
        ),
      ],
    );
  }

  /// Playlists by Artist Carousel (Screenshot 1 & 5)
  Widget _buildPlaylistsByArtistSection(List<PlaylistItem> playlists) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Playlists by $_displayName'),
        const SizedBox(height: 12),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: playlists.length > 10 ? 10 : playlists.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return _buildPlaylistCard(playlist);
            },
          ),
        ),
      ],
    );
  }

  /// Fans Might Also Like Carousel with Monthly Audience (Screenshot 1 & 2)
  Widget _buildFansMightLikeSection(List<ArtistItem> artists) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Fans might also like'),
        const SizedBox(height: 12),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: artists.length > 12 ? 12 : artists.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final artist = artists[index];
              const cardWidth = 140.0;

              return ApplePressable(
                onTap: () {
                  openArtistScreen(
                    context,
                    artistId: artist.id,
                    artistName: artist.name,
                    thumbnailUrl: artist.thumbnailUrl,
                  );
                },
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: cardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Square artist photo with rounded corners (matches Screenshot 1)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: artist.thumbnailUrl != null
                            ? Image.network(
                                artist.thumbnailUrl!,
                                width: cardWidth,
                                height: cardWidth,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.medium,
                                errorBuilder: (context, error, stackTrace) =>
                                    _fallbackSquareArt(cardWidth),
                              )
                            : _fallbackSquareArt(cardWidth),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        artist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        artist.subscribers ?? 'Artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
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

  /// "About the artist" Description & Stat Badges Section (Screenshot 1 & 2)
  Widget _buildAboutArtistSection() {
    final description = _artistDetails?.description;
    final subscribers = _artistDetails?.subscribers;
    final listeners = _artistDetails?.monthlyListeners;

    if (description == null && subscribers == null && listeners == null && !_isLoading) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'About the artist',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 12),

          // Multi-line bio description with expandable More / Less toggle
          if (description != null && description.isNotEmpty) ...[
            Text(
              description,
              maxLines: _isDescriptionExpanded ? null : 3,
              overflow: _isDescriptionExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFD1D1D6),
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () {
                setState(() => _isDescriptionExpanded = !_isDescriptionExpanded);
              },
              behavior: HitTestBehavior.opaque,
              child: Text(
                _isDescriptionExpanded ? 'Less' : 'More',
                style: const TextStyle(
                  color: AppColors.appleBlue,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Pill Stat Badges (Subscribers & Monthly Listeners)
          if (subscribers != null) ...[
            _buildStatPill(
              icon: CupertinoIcons.person_fill,
              text: subscribers,
            ),
            const SizedBox(height: 8),
          ],
          if (listeners != null) ...[
            _buildStatPill(
              icon: CupertinoIcons.waveform,
              text: listeners,
            ),
          ],
        ],
      ),
    );
  }

  // --- Helper Widget Builders ---

  Widget _buildSectionHeader(String title, {VoidCallback? onShowAll}) {
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
          if (onShowAll != null)
            ApplePressable(
              onTap: onShowAll,
              child: GlassContainer(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const LiquidRoundedSuperellipse(borderRadius: 14),
                color: const Color(0x22FFFFFF),
                useOwnLayer: true,
                settings: const LiquidGlassSettings(
                  thickness: 16,
                  blur: 16,
                  refractiveIndex: 1.12,
                  lightIntensity: 0.35,
                  specularSharpness: GlassSpecularSharpness.sharp,
                ),
                child: const Center(
                  child: Text(
                    'Show all',
                    style: TextStyle(
                      color: Color(0xFFD1D1D6),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAlbumCard(AlbumItem album) {
    const cardWidth = 140.0;
    return ApplePressable(
      onTap: () => openAlbumScreen(context, album),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: album.thumbnailUrl != null
                  ? Image.network(
                      album.thumbnailUrl!,
                      width: cardWidth,
                      height: cardWidth,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (context, error, stackTrace) =>
                          _fallbackSquareArt(cardWidth),
                    )
                  : _fallbackSquareArt(cardWidth),
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
              ),
            ),
            const SizedBox(height: 2),
            Text(
              album.year != null
                  ? (album.type == 'Single' ? 'Single • ${album.year}' : '${album.year}')
                  : (album.type.isNotEmpty ? album.type : 'Album'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaylistCard(PlaylistItem playlist) {
    const cardWidth = 140.0;
    return ApplePressable(
      onTap: () => playPlaylist(context, ref, playlist),
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: playlist.thumbnailUrl != null
                  ? Image.network(
                      playlist.thumbnailUrl!,
                      width: cardWidth,
                      height: cardWidth,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (context, error, stackTrace) =>
                          _fallbackSquareArt(cardWidth),
                    )
                  : _fallbackSquareArt(cardWidth),
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
              ),
            ),
            const SizedBox(height: 2),
            Text(
              playlist.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill({required IconData icon, required String text}) {
    return GlassContainer(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      shape: const LiquidRoundedSuperellipse(borderRadius: 18),
      color: const Color(0x2AFFFFFF),
      useOwnLayer: true,
      settings: const LiquidGlassSettings(
        thickness: 16,
        blur: 20,
        refractiveIndex: 1.15,
        lightIntensity: 0.40,
        specularSharpness: GlassSpecularSharpness.sharp,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExplicitBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: const Color(0xFF8E8E93),
        borderRadius: BorderRadius.circular(2.5),
      ),
      child: const Text(
        'E',
        style: TextStyle(
          color: Colors.black,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          height: 1.0,
        ),
      ),
    );
  }

  Widget _buildTopSongsSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: List.generate(
          5,
          (index) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 140,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 90,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
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

  void _openAlbumListModal(String title, List<AlbumItem> items) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(CupertinoIcons.xmark_circle_fill, color: Color(0xFF8E8E93)),
                      ),
                    ],
                  ),
                ),
                const Divider(color: Color(0xFF2C2C2E)),
                Expanded(
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: item.thumbnailUrl != null
                              ? Image.network(
                                  item.thumbnailUrl!,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => _fallbackSquareArt(44),
                                )
                              : _fallbackSquareArt(44),
                        ),
                        title: Text(item.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          item.year != null ? '${item.type.isNotEmpty ? item.type : 'Release'} • ${item.year}' : item.type,
                          style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          openAlbumScreen(context, item);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _fallbackBanner() {
    return Container(
      color: const Color(0xFF1C1C1E),
      child: const Center(
        child: Icon(
          CupertinoIcons.person_crop_circle_fill,
          color: Colors.white24,
          size: 72,
        ),
      ),
    );
  }

  Widget _fallbackSquareArt(double size) {
    return Container(
      width: size,
      height: size,
      color: const Color(0xFF2C2C2E),
      child: Icon(
        CupertinoIcons.music_note,
        color: Colors.white30,
        size: size * 0.45,
      ),
    );
  }

  Widget _fallbackWidescreenArt(double width, double height) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF2C2C2E),
      child: const Center(
        child: Icon(
          CupertinoIcons.play_rectangle_fill,
          color: Colors.white30,
          size: 32,
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../constants/app_colors.dart';
import '../constants/apple_typography.dart';
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
import '../widgets/animated_cupertino_icon.dart';
import '../widgets/animated_equalizer_bars.dart';
import '../widgets/apple_glass_bottom_sheet.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/liquid_glass_bottom_bar.dart';
import '../widgets/player_controls.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/top_status_bar_blur.dart';
import '../widgets/app_shimmer.dart';
import '../widgets/wavify_cached_image.dart';
import '../services/artwork_color_service.dart';

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
  Color? _primaryColor;
  Color? _secondaryColor;

  // Mini player dock crawl / minimization state
  bool _isMiniPlayerCrawled = false;
  double _accumulatedScrollDelta = 0.0;

  @override
  void initState() {
    super.initState();
    _updateArtistColors();
    _loadArtistDetails();
  }

  Future<void> _updateArtistColors() async {
    final banner = _heroBannerUrl;
    final primary = await ArtworkColorService.instance.extractAttractiveColor(
      banner,
      fallbackSeed: _displayName,
    );
    final secondary = await ArtworkColorService.instance.extractSecondaryColor(
      banner,
      fallbackSeed: _displayName,
    );
    if (mounted) {
      setState(() {
        _primaryColor = primary;
        _secondaryColor = secondary;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
      if (notification.direction == ScrollDirection.reverse &&
          !_isMiniPlayerCrawled) {
        setState(() => _isMiniPlayerCrawled = true);
      } else if (notification.direction == ScrollDirection.forward &&
          _isMiniPlayerCrawled) {
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
        _updateArtistColors();
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
    ref.read(playerProvider.notifier).setShuffle(true);
    final shuffled = List<SongItem>.from(tracks)..shuffle();
    final firstTrack = shuffled.first;
    final queue = shuffled.length > 1 ? shuffled.sublist(1) : <SongItem>[];

    playSong(
      context,
      ref,
      firstTrack,
      contextQueue: queue,
      initialHistory: const [],
      originalTracklist: tracks,
      autoOpenPlayer: false,
      forceReload: true,
    );
    showWavifySnackBar(context, 'Shuffling $_displayName top tracks');
  }

  bool get _isPlayingThisArtist {
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    if (!isPlaying || currentSong == null) return false;
    final current = currentSong.artist.toLowerCase();
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
      initialHistory: const [],
      originalTracklist: tracks,
      autoOpenPlayer: false,
      forceReload: true,
    );
    showWavifySnackBar(context, 'Playing $_displayName');
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final currentTabIndex = ref.watch(currentTabProvider);
    final userAccount = ref.watch(authProvider);

    final artistId = _artistDetails?.id ?? widget.artistId ?? '';
    final isSaved = ref.watch(
      savedArtistsProvider.select((list) {
        return list.any(
          (a) =>
              a.id == artistId ||
              (a.name.toLowerCase() == _displayName.toLowerCase()),
        );
      }),
    );

    // Find any albums from library matching this artist
    final savedAlbums = ref.watch(savedAlbumsProvider);
    final matchingLibraryAlbums = savedAlbums.where((a) {
      return a.artist.toLowerCase().contains(_displayName.toLowerCase()) ||
          _displayName.toLowerCase().contains(a.artist.toLowerCase());
    }).toList();

    final topPadding = MediaQuery.of(context).padding.top;
    final bannerHeight = 360.0 + topPadding;

    final resolvedPrimary =
        _primaryColor ??
        ArtworkColorService.instance.getCachedColor(_heroBannerUrl ?? '') ??
        ArtworkColorService.instance.getFallbackBestColor(_displayName);
    final resolvedSecondary =
        _secondaryColor ??
        ArtworkColorService.instance.getCachedSecondaryColor(
          _heroBannerUrl ?? '',
        ) ??
        ArtworkColorService.instance.getFallbackSecondaryColor(_displayName);
    final deeperSecondary = ArtworkColorService.instance.computeDeeperTone(
      resolvedSecondary,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Dynamic atmosphere background:
          // Top ~50% is framed by the hero banner, bottom ~50% layout dissolves into a rich,
          // deep secondary color tone rather than flat black!
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black,
                    Colors.black.withValues(alpha: 0.85),
                    Color.lerp(
                      resolvedPrimary,
                      deeperSecondary,
                      0.65,
                    )!.withValues(alpha: 0.40),
                    deeperSecondary.withValues(alpha: 0.70),
                    Colors.black,
                  ],
                  stops: const [0.0, 0.38, 0.65, 0.88, 1.0],
                ),
              ),
            ),
          ),

          // Scrollable Hero Artwork: scrolls with the body when scrolling up, stretches when pulling down
          _buildScrollableHeroHeader(bannerHeight, deeperSecondary),

          // Scrollable content starting from artist name downward
          NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                // Spacing to align start of content with the hero gradient
                SliverToBoxAdapter(child: SizedBox(height: bannerHeight - 70)),

                // Main Artist Content Sections (or Rich Shimmer while loading)
                SliverToBoxAdapter(
                  child: _isLoading && _artistDetails == null
                      ? _buildArtistLoadingContent()
                      : Padding(
                          padding: const EdgeInsets.only(bottom: 120),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Artist Metadata & Action Buttons Row
                              _buildHeroMetadata(isSaved),

                              const SizedBox(height: 16),

                              // Spotlight Recent Single / Release Card (Screenshot 4)
                              if (_artistDetails?.recentRelease != null) ...[
                                _buildRecentReleaseCard(
                                  _artistDetails!.recentRelease!,
                                ),
                                const SizedBox(height: 24),
                              ],

                              // Top Songs Section (Screenshot 4)
                              _buildTopSongsSection(),

                              const SizedBox(height: 28),

                              // Albums Carousel (Screenshot 3 & 4)
                              if (_artistDetails?.albums.isNotEmpty ==
                                  true) ...[
                                _buildAlbumsSection(_artistDetails!.albums),
                                const SizedBox(height: 28),
                              ],

                              // Singles & EPs Carousel (Screenshot 3 & 4)
                              if (_artistDetails?.singles.isNotEmpty ==
                                  true) ...[
                                _buildSinglesSection(_artistDetails!.singles),
                                const SizedBox(height: 28),
                              ],

                              // Music Videos Carousel (Screenshot 3 & 5)
                              if (_artistDetails?.videos.isNotEmpty ==
                                  true) ...[
                                _buildVideosSection(_artistDetails!.videos),
                                const SizedBox(height: 28),
                              ],

                              // From Your Library Section (Screenshot 3 & 5)
                              if (matchingLibraryAlbums.isNotEmpty) ...[
                                _buildLibrarySection(matchingLibraryAlbums),
                                const SizedBox(height: 28),
                              ],

                              // Featured On Carousel (Screenshot 5 & 1)
                              if (_artistDetails?.featuredOn.isNotEmpty ==
                                  true) ...[
                                _buildFeaturedOnSection(
                                  _artistDetails!.featuredOn,
                                ),
                                const SizedBox(height: 28),
                              ],

                              // Playlists by Artist Carousel (Screenshot 1 & 5)
                              if (_artistDetails
                                      ?.playlistsByArtist
                                      .isNotEmpty ==
                                  true) ...[
                                _buildPlaylistsByArtistSection(
                                  _artistDetails!.playlistsByArtist,
                                ),
                                const SizedBox(height: 28),
                              ],

                              // Fans Might Also Like Carousel (Screenshot 1 & 2)
                              if (_artistDetails?.similarArtists.isNotEmpty ==
                                  true) ...[
                                _buildFansMightLikeSection(
                                  _artistDetails!.similarArtists,
                                ),
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

          // Top Progressive Blur & Shader Scrim: smoothly blurs out content only as it scrolls up (AlbumScreen inspired)
          TopStatusBarBlur(
            scrollController: _scrollController,
            extraHeight: 68.0,
            maxSigma: 26.0,
            triggerOffset: 60.0,
            falloff: 1.2,
          ),

          // Floating Top Action Controls: Circular Back button on left, Frosted Share & Account capsule on right
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
                    ? PlayerControls(onTap: () => openPlayerScreen(context))
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Scrollable Hero Banner: moves 1:1 with the scroll offset when scrolling up so it gets away,
  /// and anchors to top: 0 with bounce stretch when pulling down.
  Widget _buildScrollableHeroHeader(double bannerHeight, Color secondaryTone) {
    final banner = _heroBannerUrl;

    return AnimatedBuilder(
      animation: _scrollController,
      builder: (context, _) {
        final scrollOffset = _scrollController.hasClients
            ? _scrollController.offset
            : 0.0;
        final topOffset = -math.max(0.0, scrollOffset);
        final pullDown = math.max(0.0, -scrollOffset);

        return Positioned(
          top: topOffset,
          left: 0,
          right: 0,
          height: bannerHeight + pullDown,
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
                  errorBuilder: (context, error, stackTrace) =>
                      _fallbackBanner(),
                )
              else
                _fallbackBanner(),

              // Multi-stop progressive gradient mask dissolving cleanly into deep secondary tone & OLED black
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
                        secondaryTone.withValues(alpha: 0.45),
                        Colors.black,
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Floating Top Action Controls: Circular Back button on left, Frosted Share & Account capsule on right
  Widget _buildFloatingTopNavBar(UserAccount? account) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        height: topPadding + 54,
        padding: EdgeInsets.fromLTRB(16, topPadding, 16, 6),
        color: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                glassColor: Color(0x18FFFFFF),
                thickness: 26,
                blur: 24,
                refractiveIndex: 1.25,
                lightIntensity: 0.75,
                specularSharpness: GlassSpecularSharpness.sharp,
                fresnelStrength: 1.30,
                rimLight: 0.45,
              ),
            ),

            // Right Action Pill in Liquid Glass: Share Button + User Avatar Circle
            GlassContainer(
              height: 42,
              shape: const LiquidRoundedSuperellipse(borderRadius: 21),
              color: const Color(0x18FFFFFF),
              useOwnLayer: true,
              settings: const LiquidGlassSettings(
                thickness: 26,
                blur: 24,
                refractiveIndex: 1.25,
                lightIntensity: 0.75,
                specularSharpness: GlassSpecularSharpness.sharp,
                fresnelStrength: 1.30,
                rimLight: 0.45,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
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
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
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
                                      const Icon(
                                        CupertinoIcons.person_crop_circle,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                )
                              : const Icon(
                                  CupertinoIcons.person_crop_circle,
                                  color: Colors.white,
                                  size: 20,
                                ),
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
                  glassColor: Color(0x18FFFFFF),
                  thickness: 26,
                  blur: 24,
                  refractiveIndex: 1.25,
                  lightIntensity: 0.75,
                  specularSharpness: GlassSpecularSharpness.sharp,
                  fresnelStrength: 1.30,
                  rimLight: 0.45,
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
                      _isPlayingThisArtist
                          ? CupertinoIcons.pause_fill
                          : CupertinoIcons.play_fill,
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
                  color: isSaved
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.6),
                  size: 22,
                ),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  final item = ArtistItem(
                    id:
                        _artistDetails?.id ??
                        widget.artistId ??
                        'artist_${_displayName.hashCode}',
                    name: _displayName,
                    thumbnailUrl: _heroBannerUrl,
                    subscribers: _artistDetails?.subscribers,
                    isCustom: true,
                  );
                  final added = await ref
                      .read(savedArtistsProvider.notifier)
                      .toggleArtist(item);
                  if (mounted) {
                    showWavifySnackBar(
                      context,
                      added
                          ? 'Added $_displayName to your Library'
                          : 'Removed $_displayName from Library',
                    );
                  }
                },
                size: 56,
                iconSize: 22,
                shape: GlassIconButtonShape.circle,
                useOwnLayer: true,
                settings: const LiquidGlassSettings(
                  glassColor: Color(0x18FFFFFF),
                  thickness: 26,
                  blur: 24,
                  refractiveIndex: 1.25,
                  lightIntensity: 0.75,
                  specularSharpness: GlassSpecularSharpness.sharp,
                  fresnelStrength: 1.30,
                  rimLight: 0.45,
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
    final isRecentSaved = ref.watch(
      savedAlbumsProvider.select((list) {
        return list.any((a) => a.id == recent.id);
      }),
    );

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
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: WavifyCachedImage(
                  imageUrl: recent.thumbnailUrl,
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(14),
                  placeholder: const AppShimmer(
                    child: ShimmerBox(
                      width: 72,
                      height: 72,
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                  errorWidget: _fallbackSquareArt(72),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      recent.year != null
                          ? 'Single • ${recent.year}'
                          : 'Single',
                      style: const TextStyle(
                        color: AppColors.appleSecondaryText,
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
                        color: AppColors.appleSecondaryText,
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
                  isRecentSaved
                      ? CupertinoIcons.checkmark_alt
                      : CupertinoIcons.plus,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () async {
                  HapticFeedback.lightImpact();
                  final added = await ref
                      .read(savedAlbumsProvider.notifier)
                      .toggleAlbum(recent);
                  if (mounted) {
                    showWavifySnackBar(
                      context,
                      added
                          ? 'Saved "${recent.title}" to Library'
                          : 'Removed "${recent.title}" from Library',
                    );
                  }
                },
                size: 40,
                iconSize: 20,
                shape: GlassIconButtonShape.circle,
                useOwnLayer: true,
                settings: const LiquidGlassSettings(
                  glassColor: Color(0x18FFFFFF),
                  thickness: 24,
                  blur: 20,
                  refractiveIndex: 1.25,
                  lightIntensity: 0.70,
                  specularSharpness: GlassSpecularSharpness.sharp,
                  fresnelStrength: 1.25,
                  rimLight: 0.40,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text('Top songs', style: AppleTypography.sectionTitle),
        ),
        const SizedBox(height: AppleSpacing.sectionHeaderToContent),
        if (_isLoading && songs.isEmpty)
          _buildTopSongsSkeleton()
        else
          _ArtistSnappingTopSongsColumns(
            columns: columns,
            songRowBuilder: (context, song) {
              final isCurrent = currentSong?.id == song.id;

              return ApplePressable(
                onTap: () {
                  final idx = songs.indexWhere((s) => s.id == song.id);
                  final history = idx > 0 ? songs.sublist(0, idx) : const <SongItem>[];
                  final queue = (idx >= 0 && idx < songs.length - 1)
                      ? songs.sublist(idx + 1)
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
                                    errorBuilder: (
                                      context,
                                      error,
                                      stackTrace,
                                    ) => _fallbackSquareArt(48),
                                  )
                                : _fallbackSquareArt(48),
                            if (isCurrent && isPlaying)
                              Positioned.fill(
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  child: const Center(
                                    child: AnimatedEqualizerBars(
                                      size: 16,
                                      color: Colors.white,
                                      isPlaying: true,
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
                                    style: AppleTypography.songTitle,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(
                              height: AppleSpacing.titleToSubtitle,
                            ),
                            Text(
                              song.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppleTypography.songArtist,
                            ),
                          ],
                        ),
                      ),

                      // 3-dots action button matching HomeScreen recent
                      IconButton(
                        icon: const AnimatedCupertinoIcon(
                          icon: CupertinoIcons.ellipsis_vertical,
                          color: AppColors.appleSecondaryText,
                          size: 18,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 40,
                        ),
                        onPressed: () =>
                            showTrackOptionsModal(context, ref, song),
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

  /// Albums Section Carousel with Show All (Screenshot 3 & 4)
  Widget _buildAlbumsSection(List<AlbumItem> albums) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'Albums',
          onShowAll: () => _openAlbumListModal('Albums', albums),
        ),
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
        _buildSectionHeader(
          'Singles & EPs',
          onShowAll: () => _openAlbumListModal('Singles & EPs', singles),
        ),
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          children: [
                            WavifyCachedImage(
                              imageUrl: video.resolvedThumbnailUrl,
                              songId: video.id,
                              width: cardWidth,
                              height: cardHeight,
                              fit: BoxFit.cover,
                              borderRadius: BorderRadius.circular(12),
                              placeholder: const AppShimmer(
                                child: ShimmerBox(
                                  width: cardWidth,
                                  height: cardHeight,
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                              ),
                              errorWidget: _fallbackWidescreenArt(
                                cardWidth,
                                cardHeight,
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
                        video.views != null
                            ? '${video.artist} • ${video.views}'
                            : video.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.appleSecondaryText,
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
          child: Text('From your library', style: AppleTypography.sectionTitle),
        ),
        const SizedBox(height: AppleSpacing.sectionHeaderToContent),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: libraryAlbums.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) =>
                _buildAlbumCard(libraryAlbums[index]),
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
                          color: AppColors.appleSecondaryText,
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

    if (description == null &&
        subscribers == null &&
        listeners == null &&
        !_isLoading) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('About the artist', style: AppleTypography.sectionTitle),
          const SizedBox(height: AppleSpacing.sectionHeaderToContent),

          // Multi-line bio description with expandable More / Less toggle
          if (description != null && description.isNotEmpty) ...[
            Text(
              description,
              maxLines: _isDescriptionExpanded ? null : 3,
              overflow: _isDescriptionExpanded
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
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
                setState(
                  () => _isDescriptionExpanded = !_isDescriptionExpanded,
                );
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
            _buildStatPill(icon: CupertinoIcons.person_fill, text: subscribers),
            const SizedBox(height: 8),
          ],
          if (listeners != null) ...[
            _buildStatPill(icon: CupertinoIcons.waveform, text: listeners),
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
          Text(title, style: AppleTypography.sectionTitle),
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
              child: WavifyCachedImage(
                imageUrl: album.thumbnailUrl,
                width: cardWidth,
                height: cardWidth,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(12),
                placeholder: const AppShimmer(
                  child: ShimmerBox(
                    width: cardWidth,
                    height: cardWidth,
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
                errorWidget: _fallbackSquareArt(cardWidth),
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
              ),
            ),
            const SizedBox(height: 2),
            Text(
              album.year != null
                  ? (album.type == 'Single'
                        ? 'Single • ${album.year}'
                        : '${album.year}')
                  : (album.type.isNotEmpty ? album.type : 'Album'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.appleSecondaryText,
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
                color: AppColors.appleSecondaryText,
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
        color: AppColors.appleSecondaryText,
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

  Widget _buildArtistLoadingContent() {
    return AppShimmer(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Center Artist Title & Action row placeholder
            Center(
              child: Column(
                children: [
                  const ShimmerBox(
                    width: 190,
                    height: 34,
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      ShimmerBox(
                        width: 56,
                        height: 56,
                        borderRadius: BorderRadius.all(Radius.circular(28)),
                      ),
                      SizedBox(width: 22),
                      ShimmerBox(
                        width: 74,
                        height: 74,
                        borderRadius: BorderRadius.all(Radius.circular(37)),
                      ),
                      SizedBox(width: 22),
                      ShimmerBox(
                        width: 56,
                        height: 56,
                        borderRadius: BorderRadius.all(Radius.circular(28)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),

            // Top Songs Section header + skeleton
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Top songs', style: AppleTypography.sectionTitle),
            ),
            const SizedBox(height: AppleSpacing.sectionHeaderToContent),
            _buildTopSongsSkeleton(),
            const SizedBox(height: 32),

            // Albums Section header + skeleton
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Albums', style: AppleTypography.sectionTitle),
            ),
            const SizedBox(height: AppleSpacing.sectionHeaderToContent),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: 4,
                separatorBuilder: (context, index) => const SizedBox(width: 14),
                itemBuilder: (context, index) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    ShimmerBox(
                      width: 140,
                      height: 140,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    SizedBox(height: 8),
                    ShimmerBox(
                      width: 100,
                      height: 12,
                      borderRadius: BorderRadius.all(Radius.circular(4)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Singles Section header + skeleton
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('Singles & EPs', style: AppleTypography.sectionTitle),
            ),
            const SizedBox(height: AppleSpacing.sectionHeaderToContent),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: 4,
                separatorBuilder: (context, index) => const SizedBox(width: 14),
                itemBuilder: (context, index) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    ShimmerBox(
                      width: 140,
                      height: 140,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    SizedBox(height: 8),
                    ShimmerBox(
                      width: 90,
                      height: 12,
                      borderRadius: BorderRadius.all(Radius.circular(4)),
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

  Widget _buildTopSongsSkeleton() {
    return const AppShimmer(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  ShimmerBox(width: 48, height: 48),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBox(width: 140, height: 14),
                        SizedBox(height: 6),
                        ShimmerBox(width: 90, height: 10),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  ShimmerBox(width: 48, height: 48),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBox(width: 160, height: 14),
                        SizedBox(height: 6),
                        ShimmerBox(width: 100, height: 10),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  ShimmerBox(width: 48, height: 48),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBox(width: 130, height: 14),
                        SizedBox(height: 6),
                        ShimmerBox(width: 80, height: 10),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  ShimmerBox(width: 48, height: 48),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBox(width: 150, height: 14),
                        SizedBox(height: 6),
                        ShimmerBox(width: 95, height: 10),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openAlbumListModal(String title, List<AlbumItem> items) {
    showAppleGlassBottomSheet(
      context: context,
      builder: (modalCtx) {
        final maxHeight = MediaQuery.sizeOf(modalCtx).height * 0.72;
        return SizedBox(
          height: maxHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
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
              ),
              Expanded(
                child: AppleSheetGroup(
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const AppleSheetDivider(),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return AppleSheetActionTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: WavifyCachedImage(
                            imageUrl: item.thumbnailUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            borderRadius: BorderRadius.circular(6),
                            placeholder: const AppShimmer(
                              child: ShimmerBox(
                                width: 44,
                                height: 44,
                                borderRadius: BorderRadius.all(
                                  Radius.circular(6),
                                ),
                              ),
                            ),
                            errorWidget: _fallbackSquareArt(44),
                          ),
                        ),
                        title: item.title,
                        subtitle: item.year != null
                            ? '${item.type.isNotEmpty ? item.type : 'Release'} • ${item.year}'
                            : item.type,
                        trailing: const Icon(
                          CupertinoIcons.chevron_right,
                          color: Colors.white38,
                          size: 16,
                        ),
                        onTap: () {
                          Navigator.pop(modalCtx);
                          openAlbumScreen(context, item);
                        },
                      );
                    },
                  ),
                ),
              ),
            ],
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

/// Horizontal snapping carousel for 4-song vertical stacks (matches homepage PageScrollPhysics)
class _ArtistSnappingTopSongsColumns extends StatefulWidget {
  final List<List<SongItem>> columns;
  final Widget Function(BuildContext, SongItem) songRowBuilder;

  const _ArtistSnappingTopSongsColumns({
    required this.columns,
    required this.songRowBuilder,
  });

  @override
  State<_ArtistSnappingTopSongsColumns> createState() =>
      _ArtistSnappingTopSongsColumnsState();
}

class _ArtistSnappingTopSongsColumnsState
    extends State<_ArtistSnappingTopSongsColumns> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.92);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 248,
      child: PageView.builder(
        controller: _controller,
        padEnds: false,
        physics: const PageScrollPhysics(),
        itemCount: widget.columns.length,
        itemBuilder: (context, columnIndex) {
          final columnSongs = widget.columns[columnIndex];
          return Padding(
            padding: EdgeInsets.only(
              left: columnIndex == 0 ? 20 : 10,
              right: columnIndex == widget.columns.length - 1 ? 20 : 6,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: columnSongs
                  .map((song) => widget.songRowBuilder(context, song))
                  .toList(),
            ),
          );
        },
      ),
    );
  }
}

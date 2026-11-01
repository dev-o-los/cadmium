import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_item.dart';
import '../models/album_item.dart';
import '../models/video_item.dart';
import '../models/hero_card_item.dart';
import '../models/music_category.dart';
import '../models/home_data.dart';
import '../models/playlist_item.dart';
import '../models/artist_item.dart';
import '../providers/music_service_provider.dart';
import '../providers/home_data_provider.dart';
import '../providers/player_provider.dart';
import '../providers/favorites_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../widgets/animated_cupertino_icon.dart';
import '../widgets/player_controls.dart';
import '../widgets/liquid_glass_bottom_bar.dart';
import '../widgets/wavify_logo.dart';
import '../widgets/apple_pressable.dart';
import 'player_screen.dart';
import 'google_signin_screen.dart';

/// Main Home Screen featuring Apple Music-inspired dark theme UI,
/// multi-section home feed from YouTube Music, floating liquid glass dock,
/// and reactive Riverpod state management.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  // 4 tabs: 0: Home, 1: Explore, 2: Library, 3: Search
  int _currentTabIndex = 0;

  // Crawl / Minimization state for floating mini player and bottom bar
  bool _isMiniPlayerCrawled = false;
  double _accumulatedScrollDelta = 0.0;

  // Search tab state
  List<SongItem> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;
  bool _hasSearched = false;

  // Accent & Surface Colors
  static const Color appleRed = Color(0xFFFA243C);
  static const Color appleDarkSurface = Color(0xFF1C1C1E);
  static const Color appleDarkSurfaceHigh = Color(0xFF2C2C2E);
  static const Color appleSecondaryText = Color(0xFF8E8E93);

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
        _accumulatedScrollDelta = (_accumulatedScrollDelta > 0 ? _accumulatedScrollDelta : 0) + delta;
        if (_accumulatedScrollDelta > 20 && !_isMiniPlayerCrawled) {
          setState(() => _isMiniPlayerCrawled = true);
        }
      } else if (delta < 0) {
        _accumulatedScrollDelta = (_accumulatedScrollDelta < 0 ? _accumulatedScrollDelta : 0) + delta;
        if (_accumulatedScrollDelta < -12 && _isMiniPlayerCrawled) {
          setState(() => _isMiniPlayerCrawled = false);
        }
      }
    }

    return false;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isPlayerOpen = false;

  void _openPlayerScreen() {
    if (_isPlayerOpen || !mounted) return;
    _isPlayerOpen = true;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: false, // Extends player to whole screen up behind the status bar
      backgroundColor: Colors.transparent,
      builder: (context) => const PlayerScreen(),
    ).whenComplete(() {
      _isPlayerOpen = false;
    });
  }

  void _onSongSelected(
    SongItem song, {
    List<SongItem>? contextQueue,
    bool autoOpenPlayer = true,
  }) {
    ref
        .read(playerProvider.notifier)
        .playSong(song, contextQueue: contextQueue);
    if (autoOpenPlayer) {
      _openPlayerScreen();
    }
  }

  Future<void> _playAlbumOrSingle(AlbumItem album) async {
    // Directly open the music player screen with instant feedback
    _openPlayerScreen();

    // Prepare optimistic song in player state immediately
    final placeholder = SongItem(
      id: 'album_${album.id}',
      title: album.title,
      artist: album.artist,
      thumbnailUrl: album.thumbnailUrl,
      album: album.title,
    );
    ref.read(playerProvider.notifier).prepareSong(placeholder);

    try {
      final musicService = ref.read(musicServiceProvider);
      final tracks = await musicService.getAlbumSongs(
        album.id,
        queryFallback: '${album.title} ${album.artist}',
      );

      if (!mounted) return;

      if (tracks.isNotEmpty) {
        final firstTrack = tracks.first;
        final queue = tracks.length > 1 ? tracks.sublist(1) : <SongItem>[];
        ref.read(playerProvider.notifier).playSong(
          firstTrack,
          contextQueue: queue,
          forceReload: true,
        );
      } else {
        _showSnackBar('No playable tracks found for "${album.title}"');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Unable to load "${album.title}": $e');
    }
  }

  Future<void> _playHero(HeroCardItem hero) async {
    _openPlayerScreen();

    final placeholder = SongItem(
      id: 'hero_${hero.id}',
      title: hero.title,
      artist: hero.subtitle.isNotEmpty ? hero.subtitle : hero.caption,
      thumbnailUrl: hero.imageUrl,
    );
    ref.read(playerProvider.notifier).prepareSong(placeholder);

    try {
      final musicService = ref.read(musicServiceProvider);
      final tracks = await musicService.searchSongs(hero.title);

      if (!mounted) return;

      if (tracks.isNotEmpty) {
        final firstTrack = tracks.first;
        final queue = tracks.length > 1 ? tracks.sublist(1) : <SongItem>[];
        ref.read(playerProvider.notifier).playSong(
          firstTrack,
          contextQueue: queue,
          forceReload: true,
        );
      } else {
        _showSnackBar('No tracks found for "${hero.title}"');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Unable to play "${hero.title}": $e');
    }
  }

  Future<void> _playPlaylist(PlaylistItem playlist) async {
    _openPlayerScreen();

    final placeholder = SongItem(
      id: 'playlist_${playlist.id}',
      title: playlist.title,
      artist: playlist.author,
      thumbnailUrl: playlist.thumbnailUrl,
      album: playlist.title,
    );
    ref.read(playerProvider.notifier).prepareSong(placeholder);

    try {
      final musicService = ref.read(musicServiceProvider);
      final tracks = await musicService.getPlaylistTracks(
        playlist.id,
        queryFallback: '${playlist.title} ${playlist.author}',
      );

      if (!mounted) return;

      if (tracks.isNotEmpty) {
        final firstTrack = tracks.first;
        final queue = tracks.length > 1 ? tracks.sublist(1) : <SongItem>[];
        ref.read(playerProvider.notifier).playSong(
          firstTrack,
          contextQueue: queue,
          forceReload: true,
        );
      } else {
        _showSnackBar('No playable tracks found for "${playlist.title}"');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Unable to load "${playlist.title}": $e');
    }
  }

  Future<void> _playArtist(ArtistItem artist) async {
    _openPlayerScreen();

    final placeholder = SongItem(
      id: 'artist_${artist.id}',
      title: artist.name,
      artist: 'Artist',
      thumbnailUrl: artist.thumbnailUrl,
    );
    ref.read(playerProvider.notifier).prepareSong(placeholder);

    try {
      final musicService = ref.read(musicServiceProvider);
      final tracks = await musicService.getArtistSongs(
        artist.id,
        artistName: artist.name,
      );

      if (!mounted) return;

      if (tracks.isNotEmpty) {
        final firstTrack = tracks.first;
        final queue = tracks.length > 1 ? tracks.sublist(1) : <SongItem>[];
        ref.read(playerProvider.notifier).playSong(
          firstTrack,
          contextQueue: queue,
          forceReload: true,
        );
      } else {
        _showSnackBar('No playable tracks found for "${artist.name}"');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Unable to load "${artist.name}": $e');
    }
  }

  Future<void> _handleSearch([String? initialQuery]) async {
    final query = initialQuery ?? _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _searchError = null;
      _hasSearched = true;
      _currentTabIndex = 3; // Switch to Search tab
    });

    try {
      final musicService = ref.read(musicServiceProvider);
      final results = await musicService.searchSongs(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } on SocketException {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = 'Network error. Please check your connection.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = 'Search failed: ${e.toString()}';
      });
    }
  }

  void _showTrackOptions(SongItem song) {
    final isFav = ref.read(favoritesProvider.notifier).isFavorite(song.id);

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
                ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: song.thumbnailUrl != null
                        ? Image.network(
                            song.thumbnailUrl!,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _fallbackSquareArt(),
                          )
                        : _fallbackSquareArt(),
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: appleSecondaryText,
                      fontSize: 13,
                    ),
                  ),
                ),
                const Divider(color: Color(0xFF2C2C2E)),
                ListTile(
                  leading: const Icon(
                    CupertinoIcons.text_badge_plus,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Play Next',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Added "${song.title}" to play next');
                  },
                ),
                ListTile(
                  leading: const Icon(
                    CupertinoIcons.list_bullet_indent,
                    color: Colors.white,
                  ),
                  title: const Text(
                    'Add to Queue',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Added "${song.title}" to queue');
                  },
                ),
                ListTile(
                  leading: Icon(
                    isFav ? CupertinoIcons.star_fill : CupertinoIcons.star,
                    color: isFav ? appleRed : Colors.white,
                  ),
                  title: Text(
                    isFav ? 'Remove from Favorites' : 'Add to Favorites',
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    ref.read(favoritesProvider.notifier).toggleFavorite(song);
                    _showSnackBar(isFav
                        ? 'Removed "${song.title}" from favorites'
                        : 'Saved "${song.title}" to favorites');
                  },
                ),
                ListTile(
                  leading: const Icon(CupertinoIcons.share, color: Colors.white),
                  title: const Text(
                    'Share Song',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showSnackBar('Sharing link for "${song.title}"');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: appleDarkSurfaceHigh,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showAccountModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final account = ref.watch(authProvider);

            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(context).viewInsets.bottom + 28,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Modal Grabber
                  Center(
                    child: Container(
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (account != null) ...[
                    // Signed In Account Overview
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: appleRed,
                          backgroundImage: account.avatarUrl != null
                              ? NetworkImage(account.avatarUrl!)
                              : null,
                          child: account.avatarUrl == null
                              ? Text(
                                  account.initials,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                account.displayName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (account.email.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  account.email,
                                  style: const TextStyle(
                                    color: appleSecondaryText,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.greenAccent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'YouTube Music Connected',
                                    style: TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Personalized Recommendations Switch
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: appleDarkSurfaceHigh,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            CupertinoIcons.sparkles,
                            color: appleRed,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'Personalized Feed',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Home feed is tailored to your YouTube Music account',
                                  style: TextStyle(
                                    color: appleSecondaryText,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          CupertinoSwitch(
                            value: account.isPersonalizedEnabled,
                            activeTrackColor: appleRed,
                            onChanged: (val) {
                              ref
                                  .read(authProvider.notifier)
                                  .togglePersonalizedRecommendations(val);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        CupertinoIcons.arrow_2_circlepath,
                        color: Colors.white,
                      ),
                      title: const Text(
                        'Refresh Recommendations',
                        style: TextStyle(color: Colors.white),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        ref.read(homeDataProvider.notifier).refresh();
                        _showSnackBar('Refreshing your YouTube Music feed...');
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        CupertinoIcons.arrow_right_arrow_left,
                        color: Colors.white,
                      ),
                      title: const Text(
                        'Switch Google Account',
                        style: TextStyle(color: Colors.white),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const GoogleSignInScreen(),
                          ),
                        );
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        CupertinoIcons.square_arrow_right,
                        color: appleRed,
                      ),
                      title: const Text(
                        'Sign Out of Google Account',
                        style: TextStyle(
                          color: appleRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        ref.read(authProvider.notifier).signOut();
                        _showSnackBar('Signed out of YouTube Music account');
                      },
                    ),
                  ] else ...[
                    // Not Signed In: Connect Promotion
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: appleRed.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.music_note_list,
                          color: appleRed,
                          size: 38,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Sign In with Google Account',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Sign in with your Google account that uses YouTube Music to get recommendations according to your specific account.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: appleSecondaryText,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ApplePressable(
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const GoogleSignInScreen(),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: appleRed,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              CupertinoIcons.play_circle_fill,
                              color: Colors.white,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Sign in with Google (YouTube Music)',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
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
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);

    // Listen for audio stream resolution errors
    ref.listen<String?>(playerProvider.select((s) => s.errorMessage), (
      prev,
      error,
    ) {
      if (error != null) {
        _showSnackBar(error);
        ref.read(playerProvider.notifier).clearErrorMessage();
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Active Tab Page View with Scroll-driven Crawl Observer
          SafeArea(
            bottom: false,
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: IndexedStack(
                index: _currentTabIndex,
                children: [
                  _buildHomeTab(),
                  _buildExploreTab(),
                  _buildLibraryTab(),
                  _buildSearchTab(),
                ],
              ),
            ),
          ),

          // Floating Player + Floating Liquid Glass Navigation Dock
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: LiquidGlassBottomBar(
                currentIndex: _currentTabIndex,
                isCrawled: _isMiniPlayerCrawled,
                onTabSelected: (index) {
                  setState(() {
                    _currentTabIndex = index;
                    _isMiniPlayerCrawled = false;
                  });
                },
                onExpand: () {
                  setState(() {
                    _isMiniPlayerCrawled = false;
                  });
                },
                bottomAccessory: playerState.currentSong != null
                    ? PlayerControls(onTap: _openPlayerScreen)
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 1: HOME (Exact match with reference screenshots)
  // =========================================================================
  Widget _buildHomeTab() {
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
              style: TextStyle(color: appleSecondaryText, fontSize: 14),
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
                color: appleRed,
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
                  backgroundColor: appleDarkSurfaceHigh,
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
      data: (data) => _buildHomeContent(data),
    );
  }

  Widget _buildHomeContent(HomeData data) {
    final playerState = ref.watch(playerProvider);

    return RefreshIndicator(
      color: Colors.white,
      backgroundColor: appleDarkSurface,
      onRefresh: () => ref.read(homeDataProvider.notifier).refresh(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 160),
        children: [
          // Top Header: 3-Wave Sound Logo on Left + Profile Avatar on Right
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Signature 3-wave sound logo
                const WavifyLogo(size: 32, color: Colors.white),

                // Interactive Top Right Google / YouTube Music Profile Button
                Consumer(
                  builder: (context, ref, child) {
                    final account = ref.watch(authProvider);

                    return ApplePressable(
                      onTap: () {
                        if (account != null) {
                          _showAccountModal(context);
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
                                    ? appleRed.withValues(alpha: 0.85)
                                    : Colors.white.withValues(alpha: 0.5),
                                width: 1.5,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 18,
                              backgroundColor: account != null
                                  ? appleRed
                                  : appleDarkSurfaceHigh,
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
          _buildTopPicksHeroSection(data.heroCards),
          const SizedBox(height: 28),

          // Section 2: "Recents" (4-item vertical column horizontal paging)
          _build4ItemColumnsSection(title: 'Recents', songs: data.recents),
          const SizedBox(height: 28),

          // Section 3: "Find Your Mood" with "Show all"
          _buildFindYourMoodSection(data.moods),
          const SizedBox(height: 28),

          // Section 4: "Albums & singles"
          _buildAlbumsAndSinglesSection(data.albumsAndSingles),
          const SizedBox(height: 28),

          // Section 5: "Music videos" (16:9 widescreen)
          _buildMusicVideosSection(data.musicVideos),
          const SizedBox(height: 28),

          // Section 6: "Listen again" (listening history from playerProvider)
          if (playerState.recentlyPlayed.isNotEmpty) ...[
            _build4ItemColumnsSection(
              title: 'Listen again',
              subtitle: 'UTKARSH',
              songs: playerState.recentlyPlayed,
            ),
            const SizedBox(height: 28),
          ],

          // Section 7: "Quick picks" (4-item vertical column horizontal paging)
          _build4ItemColumnsSection(
            title: 'Quick picks',
            songs: data.quickPicks,
          ),
          const SizedBox(height: 28),

          // Section 8: "Your daily discover"
          _buildHorizontalSongCarousel(
            title: 'Your daily discover',
            songs: data.dailyDiscover,
          ),
          const SizedBox(height: 28),

          // Section 9: "Trending songs for you"
          _buildHorizontalSongCarousel(
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

  /// Top Picks Hero Section with Karan Aujla, Shubh, The Weeknd cards
  Widget _buildTopPicksHeroSection(List<HeroCardItem> heroCards) {
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
              return _buildHeroCard(hero);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeroCard(HeroCardItem hero) {
    final isShubhCard = hero.id.contains('shubh');

    return ApplePressable(
      onTap: () {
        if (hero.playTrack != null) {
          _onSongSelected(hero.playTrack!);
        } else {
          _playHero(hero);
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
                  child: Image.network(
                    hero.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
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
                        // Overlapping circular artist avatars
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
    // When a column only has 2 elements, it renders dynamically with proportional height
    // rather than staying stuck at the rigid 4-element height (256px).
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
                    color: appleSecondaryText,
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
                      .map((song) => _build4ItemRow(song, contextQueue: songs))
                      .toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _build4ItemRow(SongItem song, {List<SongItem>? contextQueue}) {
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isSelected = currentSong?.id == song.id;

    return SizedBox(
      height: 64,
      child: ApplePressable(
        onTap: () => _onSongSelected(song, contextQueue: contextQueue),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              // Artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: song.thumbnailUrl != null
                    ? Image.network(
                        song.thumbnailUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _fallbackSquareArt(),
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
                        color: isSelected ? appleRed : Colors.white,
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
                        color: appleSecondaryText,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),

              // 3-dots Menu Icon
              IconButton(
                icon: const AnimatedCupertinoIcon(
                  icon: CupertinoIcons.ellipsis_vertical,
                  color: appleSecondaryText,
                  size: 18,
                ),
                onPressed: () => _showTrackOptions(song),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Find Your Mood Section with Line-Art Icons & 3-Wave Logo
  Widget _buildFindYourMoodSection(List<MusicCategory> moods) {
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
                  setState(() => _currentTabIndex = 1);
                },
                child: const Text(
                  'Show all',
                  style: TextStyle(
                    color: appleSecondaryText,
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
                  _searchController.text = mood.title;
                  _handleSearch(mood.title);
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
  Widget _buildAlbumsAndSinglesSection(List<AlbumItem> albums) {
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
                onTap: () => _playAlbumOrSingle(album),
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: cardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: _DynamicAlbumArtwork(
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
                          color: appleSecondaryText,
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
  Widget _buildMusicVideosSection(List<VideoItem> videos) {
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
                  _onSongSelected(
                    SongItem(
                      id: video.id,
                      title: video.title,
                      artist: video.artist,
                      thumbnailUrl: video.thumbnailUrl,
                      durationSeconds: video.durationSeconds,
                    ),
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
                                ? Image.network(
                                    video.thumbnailUrl!,
                                    width: videoWidth,
                                    height: videoThumbnailHeight,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                              width: videoWidth,
                                              height: videoThumbnailHeight,
                                              color: appleDarkSurfaceHigh,
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
                                    color: appleDarkSurfaceHigh,
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
                          color: appleSecondaryText,
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
                onTap: () => _onSongSelected(song, contextQueue: songs),
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
                                ? Image.network(
                                    song.thumbnailUrl!,
                                    width: cardWidth,
                                    height: cardWidth,
                                    fit: BoxFit.cover,
                                    errorBuilder: (
                                      context,
                                      error,
                                      stackTrace,
                                    ) => _fallbackSquareArt(size: cardWidth),
                                  )
                                : _fallbackSquareArt(size: cardWidth),
                          ),
                          if (isCurrent)
                            Positioned(
                              right: 8,
                              bottom: 8,
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: appleRed,
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
                          color: isCurrent ? appleRed : Colors.white,
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
                          color: appleSecondaryText,
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

  Widget _fallbackSquareArt({
    double size = 48,
    IconData icon = CupertinoIcons.music_note,
  }) {
    return Container(
      width: size,
      height: size,
      color: appleDarkSurfaceHigh,
      child: Icon(
        icon,
        color: Colors.white30,
        size: (size * 0.5).clamp(20.0, 48.0),
      ),
    );
  }

  // =========================================================================
  // TAB 2: EXPLORE (Genres, Moods, Global Hits)
  // =========================================================================
  Widget _buildExploreTab() {
    final homeDataAsync = ref.watch(homeDataProvider);
    final genres = homeDataAsync.valueOrNull?.genres ?? [];
    final trending = homeDataAsync.valueOrNull?.trendingSongs ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 160),
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
                    : appleDarkSurfaceHigh;

                return ApplePressable(
                  onTap: () {
                    _searchController.text = g.title;
                    _handleSearch(g.title);
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
        ...trending.take(10).map((track) => _buildSongRow(track)),
      ],
    );
  }

  // =========================================================================
  // TAB 3: LIBRARY (Albums, Playlists, Liked Music & Artists - Square Cards)
  // =========================================================================
  Widget _buildLibraryTab() {
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

        // 2. Playlists Section (Horizontal album cards with Save from YouTube button)
        _buildLibrarySectionHeader(
          title: 'Playlists',
          count: playlists.length,
        ),
        const SizedBox(height: 12),
        if (playlists.isEmpty && isLoggedIn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildEmptySectionBanner(
              icon: CupertinoIcons.music_note_list,
              title: 'No Playlists Found',
              subtitle: 'Tap Save Playlist below to import any YouTube playlist.',
              actionButtonText: 'Save Playlist',
              onActionTap: () => _showSavePlaylistSheet(context),
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
                    iconColor: appleRed,
                    onTap: () => _showSavePlaylistSheet(context),
                  );
                }
                final playlist = playlists[index - 1];
                return _buildPlaylistSquareCard(playlist, cardWidth);
              },
            ),
          ),
        const SizedBox(height: 28),

        // 3. Liked Music Section (Horizontal album cards - no list style)
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
                return _buildSongSquareCard(song, cardWidth, allLikedMusic);
              },
            ),
          ),
        const SizedBox(height: 28),

        // 4. Albums Section (Horizontal album cards)
        _buildLibrarySectionHeader(
          title: 'Albums',
          count: albums.length,
        ),
        const SizedBox(height: 12),
        if (albums.isEmpty && isLoggedIn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildEmptySectionBanner(
              icon: CupertinoIcons.music_albums,
              title: 'No Saved Albums Found',
              subtitle: 'Tap Add Album below to search and save albums to your library.',
              actionButtonText: 'Add Album',
              onActionTap: () => _showSearchAlbumSheet(context),
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
                    onTap: () => _showSearchAlbumSheet(context),
                  );
                }
                final album = albums[index - 1];
                return _buildAlbumSquareCard(album, cardWidth);
              },
            ),
          ),
        const SizedBox(height: 28),

        // 5. Artists Section (Horizontal artist cards)
        _buildLibrarySectionHeader(
          title: 'Artists',
          count: artists.length,
        ),
        const SizedBox(height: 12),
        if (artists.isEmpty && isLoggedIn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildEmptySectionBanner(
              icon: CupertinoIcons.person_2_fill,
              title: 'No Subscribed Artists Found',
              subtitle: 'Tap Add Artist below to search and bookmark favorite artists.',
              actionButtonText: 'Add Artist',
              onActionTap: () => _showSearchArtistSheet(context),
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
                    onTap: () => _showSearchArtistSheet(context),
                  );
                }
                final artist = artists[index - 1];
                return _buildArtistSquareCard(artist, cardWidth);
              },
            ),
          ),
        const SizedBox(height: 28),

        // 6. Recently Played Section (Horizontal square cards - no list style)
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
                return _buildSongSquareCard(song, cardWidth, recentlyPlayed);
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
                color: appleSecondaryText,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaylistSquareCard(PlaylistItem playlist, double cardWidth) {
    return ApplePressable(
      onTap: () => _playPlaylist(playlist),
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
                          _fallbackSquareArt(size: cardWidth, icon: CupertinoIcons.music_note_list),
                    )
                  : _fallbackSquareArt(size: cardWidth, icon: CupertinoIcons.music_note_list),
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
                color: appleSecondaryText,
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
    SongItem song,
    double cardWidth,
    List<SongItem> queue,
  ) {
    final isCurrent =
        ref.watch(playerProvider.select((s) => s.currentSong?.id == song.id));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));

    return ApplePressable(
      onTap: () {
        _openPlayerScreen();
        ref.read(playerProvider.notifier).playSong(
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
                        color: appleRed,
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
                color: isCurrent ? appleRed : Colors.white,
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
                color: appleSecondaryText,
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

  Widget _buildAlbumSquareCard(AlbumItem album, double cardWidth) {
    return ApplePressable(
      onTap: () => _playAlbumOrSingle(album),
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: cardWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _DynamicAlbumArtwork(
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
                color: appleSecondaryText,
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

  Widget _buildArtistSquareCard(ArtistItem artist, double cardWidth) {
    return ApplePressable(
      onTap: () => _playArtist(artist),
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
                          _fallbackSquareArt(size: cardWidth, icon: CupertinoIcons.person_solid),
                    )
                  : _fallbackSquareArt(size: cardWidth, icon: CupertinoIcons.person_solid),
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
                color: appleSecondaryText,
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
    Color iconColor = appleRed,
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
                color: appleSecondaryText,
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
                child: Icon(icon, color: appleSecondaryText, size: 24),
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
                        color: appleSecondaryText,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.plus, color: appleRed, size: 16),
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

  void _showSavePlaylistSheet(BuildContext context) {
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
                        color: appleSecondaryText,
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
                            color: appleSecondaryText,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              autofocus: true,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 14),
                              decoration: const InputDecoration(
                                hintText:
                                    'https://music.youtube.com/playlist?list=...',
                                hintStyle: TextStyle(
                                    color: Colors.white38, fontSize: 13),
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
                                color: appleSecondaryText,
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
                            color: Colors.redAccent, fontSize: 12),
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
                                      final musicService =
                                          ref.read(musicServiceProvider);
                                      final playlist = await musicService
                                          .fetchYouTubePlaylist(input);

                                      if (playlist != null) {
                                        ref
                                            .read(
                                                savedPlaylistsProvider.notifier)
                                            .addPlaylist(playlist);
                                        if (modalCtx.mounted) {
                                          Navigator.pop(modalCtx);
                                        }
                                        _showSnackBar(
                                          'Saved "${playlist.title}" to Playlists',
                                        );
                                      } else {
                                        setModalState(() {
                                          isLoading = false;
                                          errorMessage =
                                              'Could not resolve playlist. Check link and try again.';
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
                                color: appleRed,
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
                                                Colors.white),
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

  void _showSearchArtistSheet(BuildContext context) {
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
                          icon: const Icon(CupertinoIcons.xmark_circle_fill,
                              color: Colors.white54),
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
                          const Icon(CupertinoIcons.search,
                              color: appleSecondaryText, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: searchController,
                              autofocus: true,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15),
                              decoration: const InputDecoration(
                                hintText: 'Search artists on YouTube...',
                                hintStyle: TextStyle(
                                    color: Colors.white38, fontSize: 14),
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
                                  strokeWidth: 2, color: appleRed),
                            )
                          else if (searchController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () =>
                                  executeSearch(searchController.text),
                              child: const Text('Search',
                                  style: TextStyle(
                                      color: appleRed,
                                      fontWeight: FontWeight.bold)),
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
                                  color: appleSecondaryText, fontSize: 14),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            itemCount: searchResults.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final artist = searchResults[index];
                              final isSaved =
                                  savedArtists.any((a) => a.id == artist.id);

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 12),
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
                                              errorBuilder: (context, error, stackTrace) =>
                                                  _fallbackSquareArt(
                                                      size: 44,
                                                      icon: CupertinoIcons
                                                          .person_solid),
                                            )
                                          : _fallbackSquareArt(
                                              size: 44,
                                              icon: CupertinoIcons.person_solid),
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
                                              color: appleSecondaryText,
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
                                            : appleRed,
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

  void _showSearchAlbumSheet(BuildContext context) {
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
                          icon: const Icon(CupertinoIcons.xmark_circle_fill,
                              color: Colors.white54),
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
                          const Icon(CupertinoIcons.search,
                              color: appleSecondaryText, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: searchController,
                              autofocus: true,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15),
                              decoration: const InputDecoration(
                                hintText: 'Search albums on YouTube...',
                                hintStyle: TextStyle(
                                    color: Colors.white38, fontSize: 14),
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
                                  strokeWidth: 2, color: appleRed),
                            )
                          else if (searchController.text.isNotEmpty)
                            GestureDetector(
                              onTap: () =>
                                  executeSearch(searchController.text),
                              child: const Text('Search',
                                  style: TextStyle(
                                      color: appleRed,
                                      fontWeight: FontWeight.bold)),
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
                                  color: appleSecondaryText, fontSize: 14),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 8),
                            itemCount: searchResults.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final album = searchResults[index];
                              final isSaved =
                                  savedAlbums.any((a) => a.id == album.id);

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 8, horizontal: 12),
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
                                              errorBuilder: (context, error, stackTrace) =>
                                                  _fallbackSquareArt(
                                                      size: 44,
                                                      icon: CupertinoIcons
                                                          .music_albums),
                                            )
                                          : _fallbackSquareArt(
                                              size: 44,
                                              icon: CupertinoIcons
                                                  .music_albums),
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
                                              color: appleSecondaryText,
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
                                            : appleRed,
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

  // =========================================================================
  // TAB 4: SEARCH
  // =========================================================================
  Widget _buildSearchTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 10),
          child: Text(
            'Search',
            style: TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
              letterSpacing: -1.2,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: appleDarkSurfaceHigh,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.search,
                  color: appleSecondaryText,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(
                      hintText: 'Artists, Songs, Lyrics, and More',
                      hintStyle: TextStyle(
                        color: appleSecondaryText,
                        fontSize: 15,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onSubmitted: (_) => _handleSearch(),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() {
                        _searchResults.clear();
                        _hasSearched = false;
                      });
                    },
                    child: const AnimatedCupertinoIcon(
                      icon: CupertinoIcons.clear_thick_circled,
                      color: appleSecondaryText,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _isSearching
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _hasSearched
              ? _buildSearchResultsList()
              : _buildSearchExploration(),
        ),
      ],
    );
  }

  Widget _buildSearchResultsList() {
    if (_searchError != null) {
      return Center(
        child: Text(_searchError!, style: const TextStyle(color: appleRed)),
      );
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Text(
          'No results found.',
          style: TextStyle(color: appleSecondaryText),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) =>
          const Divider(color: Color(0xFF2C2C2E), height: 1, indent: 62),
      itemBuilder: (context, index) {
        final song = _searchResults[index];
        return _buildSongRow(song);
      },
    );
  }

  Widget _buildSearchExploration() {
    final homeDataAsync = ref.watch(homeDataProvider);
    final genres = homeDataAsync.valueOrNull?.genres ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
      children: [
        const Text(
          'Browse Categories',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: genres.take(16).map((g) {
            return GestureDetector(
              onTap: () {
                _searchController.text = g.title;
                _handleSearch(g.title);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: appleDarkSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Text(
                  g.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSongRow(SongItem song, {List<SongItem>? contextQueue}) {
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isSelected = currentSong?.id == song.id;

    return ApplePressable(
      onTap: () => _onSongSelected(song, contextQueue: contextQueue),
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 58),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: song.thumbnailUrl != null
                    ? Image.network(
                        song.thumbnailUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _fallbackSquareArt(),
                      )
                    : _fallbackSquareArt(),
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
                      style: TextStyle(
                        color: isSelected ? appleRed : Colors.white,
                        fontSize: 15,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
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
                        color: appleSecondaryText,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected) ...[
                const Icon(CupertinoIcons.waveform, color: appleRed, size: 20),
                const SizedBox(width: 6),
              ],
              IconButton(
                icon: const AnimatedCupertinoIcon(
                  icon: CupertinoIcons.ellipsis_vertical,
                  color: appleSecondaryText,
                  size: 18,
                ),
                onPressed: () => _showTrackOptions(song),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dynamically resolves and displays real cover artwork for an album.
/// If the album already has a valid image, it renders it with Image.network.
/// If missing or if network loading fails, it dynamically queries YouTube Music
/// to grab the image for that specific album, caching and persisting it.
/// If and only if no image is available, it gracefully renders the fallback icon.
class _DynamicAlbumArtwork extends ConsumerStatefulWidget {
  final AlbumItem album;
  final double size;

  const _DynamicAlbumArtwork({
    required this.album,
    required this.size,
  });

  @override
  ConsumerState<_DynamicAlbumArtwork> createState() =>
      _DynamicAlbumArtworkState();
}

class _DynamicAlbumArtworkState extends ConsumerState<_DynamicAlbumArtwork> {
  String? _resolvedUrl;
  bool _isFetching = false;
  bool _hasAttemptedFetch = false;

  @override
  void initState() {
    super.initState();
    _resolvedUrl = _sanitizeUrl(widget.album.thumbnailUrl);
    if (_resolvedUrl == null || _resolvedUrl!.isEmpty) {
      _fetchArtwork();
    }
  }

  @override
  void didUpdateWidget(covariant _DynamicAlbumArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.id != widget.album.id ||
        oldWidget.album.thumbnailUrl != widget.album.thumbnailUrl) {
      _resolvedUrl = _sanitizeUrl(widget.album.thumbnailUrl);
      _hasAttemptedFetch = false;
      if (_resolvedUrl == null || _resolvedUrl!.isEmpty) {
        _fetchArtwork();
      }
    }
  }

  String? _sanitizeUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final trimmed = url.trim();
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    if (trimmed.contains('s6_19N3N1z') || trimmed.contains('s4_90Q2N1z')) {
      return null;
    }
    return trimmed;
  }

  Future<void> _fetchArtwork() async {
    if (_hasAttemptedFetch || _isFetching) return;
    _isFetching = true;
    _hasAttemptedFetch = true;

    try {
      final musicService = ref.read(musicServiceProvider);
      final artwork = await musicService.getAlbumArtwork(
        widget.album.id,
        title: widget.album.title,
        artist: widget.album.artist,
      );

      if (!mounted) return;

      if (artwork != null && artwork.isNotEmpty) {
        setState(() {
          _resolvedUrl = artwork;
          _isFetching = false;
        });

        // Persist the grabbed real image in local storage
        ref
            .read(savedAlbumsProvider.notifier)
            .updateAlbumThumbnail(widget.album.id, artwork);
      } else {
        setState(() {
          _isFetching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isFetching = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvedUrl != null && _resolvedUrl!.isNotEmpty) {
      return Image.network(
        _resolvedUrl!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          if (!_hasAttemptedFetch) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fetchArtwork();
            });
          }
          return Container(
            width: widget.size,
            height: widget.size,
            color: _HomeScreenState.appleDarkSurfaceHigh,
            child: Icon(
              CupertinoIcons.music_albums,
              color: Colors.white30,
              size: (widget.size * 0.5).clamp(20.0, 48.0),
            ),
          );
        },
      );
    }

    if (_isFetching) {
      return Container(
        width: widget.size,
        height: widget.size,
        color: _HomeScreenState.appleDarkSurfaceHigh,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white24),
            ),
          ),
        ),
      );
    }

    return Container(
      width: widget.size,
      height: widget.size,
      color: _HomeScreenState.appleDarkSurfaceHigh,
      child: Icon(
        CupertinoIcons.music_albums,
        color: Colors.white30,
        size: (widget.size * 0.5).clamp(20.0, 48.0),
      ),
    );
  }
}

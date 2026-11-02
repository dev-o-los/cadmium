import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_item.dart';
import '../providers/navigation_provider.dart';
import '../providers/player_provider.dart';
import '../utils/playback_utils.dart';
import '../widgets/liquid_glass_bottom_bar.dart';
import '../widgets/player_controls.dart';
import 'explore_screen.dart';
import 'home_feed_screen.dart';
import 'library_screen.dart';
import 'search_screen.dart';

export 'album_screen.dart';
export 'artist_screen.dart';
export 'explore_screen.dart';
export 'home_feed_screen.dart';
export 'library_screen.dart';
export 'search_screen.dart';

/// Main Home Screen featuring Apple Music-inspired dark theme UI,
/// floating liquid glass dock, and reactive tab management hosting
/// Home, Explore, Library, and Search screens.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<SearchScreenState> _searchKey = GlobalKey<SearchScreenState>();

  // Crawl / Minimization state for floating mini player and bottom bar
  bool _isMiniPlayerCrawled = false;
  double _accumulatedScrollDelta = 0.0;

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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openPlayerScreen() {
    if (!mounted) return;
    openPlayerScreen(context);
  }

  void _navigateToSearchWithQuery(String query) {
    ref.read(currentTabProvider.notifier).state = 3;
    setState(() {
      _isMiniPlayerCrawled = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchKey.currentState?.search(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(playerProvider);
    final currentTabIndex = ref.watch(currentTabProvider);

    // Listen for audio stream resolution errors
    ref.listen<String?>(playerProvider.select((s) => s.errorMessage), (
      prev,
      error,
    ) {
      if (error != null) {
        showWavifySnackBar(context, error);
        ref.read(playerProvider.notifier).clearErrorMessage();
      }
    });

    // Ensure floating mini player bar expands into view when a new song starts playing
    ref.listen<SongItem?>(playerProvider.select((s) => s.currentSong), (
      prev,
      current,
    ) {
      if (current != null && prev?.id != current.id) {
        if (_isMiniPlayerCrawled) {
          setState(() {
            _isMiniPlayerCrawled = false;
          });
        }
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
                index: currentTabIndex,
                children: [
                  HomeFeedScreen(
                    onNavigateToTab: (index) {
                      ref.read(currentTabProvider.notifier).state = index;
                      setState(() {
                        _isMiniPlayerCrawled = false;
                      });
                    },
                    onSearch: _navigateToSearchWithQuery,
                  ),
                  ExploreScreen(
                    onSearch: _navigateToSearchWithQuery,
                  ),
                  const LibraryScreen(),
                  SearchScreen(
                    key: _searchKey,
                    searchController: _searchController,
                  ),
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
                currentIndex: currentTabIndex,
                isCrawled: _isMiniPlayerCrawled,
                onTabSelected: (index) {
                  ref.read(currentTabProvider.notifier).state = index;
                  setState(() {
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
}

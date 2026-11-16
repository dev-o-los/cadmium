import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/song_item.dart';
import '../providers/navigation_provider.dart';
import '../providers/player_provider.dart';
import '../utils/notification_permission.dart';
import '../utils/playback_utils.dart';
import '../widgets/liquid_glass_bottom_bar.dart';
import '../widgets/player_controls.dart';
import '../widgets/top_profile_avatar_button.dart';
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

  // Crawl / Minimization state for floating mini player and bottom bar using ValueNotifier
  // to avoid triggering rebuilds of the entire HomeScreen and active tab during vertical scrolling
  final ValueNotifier<bool> _miniPlayerCrawledNotifier = ValueNotifier<bool>(false);
  double _accumulatedScrollDelta = 0.0;

  // Track loaded tabs lazily so Explore, Library, and Search screens are not mounted on first render
  final Set<int> _loadedTabs = {0};

  @override
  void initState() {
    super.initState();
    // Prompt for notification permission on Android 13+ after Activity is focused
    WidgetsBinding.instance.addPostFrameCallback((_) {
      requestNotificationPermissionIfNeeded();
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }

    final pixels = notification.metrics.pixels;
    if (pixels <= 25) {
      if (_miniPlayerCrawledNotifier.value) {
        _miniPlayerCrawledNotifier.value = false;
      }
      _accumulatedScrollDelta = 0;
      return false;
    }

    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.reverse &&
          !_miniPlayerCrawledNotifier.value) {
        _miniPlayerCrawledNotifier.value = true;
      } else if (notification.direction == ScrollDirection.forward &&
          _miniPlayerCrawledNotifier.value) {
        _miniPlayerCrawledNotifier.value = false;
      }
    } else if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;
      if (delta > 0) {
        _accumulatedScrollDelta =
            (_accumulatedScrollDelta > 0 ? _accumulatedScrollDelta : 0) + delta;
        if (_accumulatedScrollDelta > 45 && !_miniPlayerCrawledNotifier.value) {
          _miniPlayerCrawledNotifier.value = true;
        }
      } else if (delta < 0) {
        _accumulatedScrollDelta =
            (_accumulatedScrollDelta < 0 ? _accumulatedScrollDelta : 0) + delta;
        if (_accumulatedScrollDelta < -25 && _miniPlayerCrawledNotifier.value) {
          _miniPlayerCrawledNotifier.value = false;
        }
      }
    }

    return false;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _miniPlayerCrawledNotifier.dispose();
    super.dispose();
  }

  void _openPlayerScreen() {
    if (!mounted) return;
    openPlayerScreen(context);
  }

  void _navigateToSearchWithQuery(String query) {
    ref.read(currentTabProvider.notifier).state = 3;
    _miniPlayerCrawledNotifier.value = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchKey.currentState?.search(query);
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasCurrentSong = ref.watch(playerProvider.select((s) => s.currentSong != null));
    final currentTabIndex = ref.watch(currentTabProvider);
    final topPadding = MediaQuery.of(context).padding.top;

    // Lazily mark the active tab as loaded
    _loadedTabs.add(currentTabIndex);

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
        if (_miniPlayerCrawledNotifier.value) {
          _miniPlayerCrawledNotifier.value = false;
        }
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Active Tab Page View with Scroll-driven Crawl Observer (No top SafeArea so HomeFeedScreen extends edge-to-edge behind the battery/status bar)
          NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: IndexedStack(
              index: currentTabIndex,
              children: [
                RepaintBoundary(
                  child: HomeFeedScreen(
                    onNavigateToTab: (index) {
                      ref.read(currentTabProvider.notifier).state = index;
                      _miniPlayerCrawledNotifier.value = false;
                    },
                    onSearch: _navigateToSearchWithQuery,
                  ),
                ),
                _loadedTabs.contains(1)
                    ? RepaintBoundary(
                        child: ExploreScreen(
                          onSearch: _navigateToSearchWithQuery,
                        ),
                      )
                    : const SizedBox.shrink(),
                _loadedTabs.contains(2)
                    ? const RepaintBoundary(
                        child: LibraryScreen(),
                      )
                    : const SizedBox.shrink(),
                _loadedTabs.contains(3)
                    ? RepaintBoundary(
                        child: SearchScreen(
                          key: _searchKey,
                          searchController: _searchController,
                          showAvatar: false,
                        ),
                      )
                    : const SizedBox.shrink(),
              ],
            ),
          ),

          // Fixed Top Status Bar Gradient Dissolve across Home, Explore, and Library tabs
          // Creates a natural liquid fading of scrolling headers under the top bezel
          if (currentTabIndex != 3)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topPadding + 44,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black,
                        Colors.black.withValues(alpha: 0.85),
                        Colors.black.withValues(alpha: 0.40),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.45, 0.75, 1.0],
                    ),
                  ),
                ),
              ),
            ),

          // Global Fixed Top-Right Profile Avatar Button
          // Rock-solid fixed in place across all tabs (Home, Explore, Library, Search)
          Positioned(
            top: topPadding + 12,
            right: 16,
            child: const TopProfileAvatarButton(size: 40),
          ),

          // Floating Player + Floating Liquid Glass Navigation Dock
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: RepaintBoundary(
              child: SafeArea(
                top: false,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _miniPlayerCrawledNotifier,
                  builder: (context, isCrawled, _) {
                    return LiquidGlassBottomBar(
                      currentIndex: currentTabIndex,
                      isCrawled: isCrawled,
                      onTabSelected: (index) {
                        ref.read(currentTabProvider.notifier).state = index;
                        _miniPlayerCrawledNotifier.value = false;
                      },
                      onExpand: () {
                        _miniPlayerCrawledNotifier.value = false;
                      },
                      bottomAccessory: hasCurrentSong
                          ? PlayerControls(onTap: _openPlayerScreen)
                          : null,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

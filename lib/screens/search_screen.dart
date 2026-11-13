import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../constants/app_colors.dart';
import '../constants/apple_typography.dart';
import '../models/album_item.dart';
import '../models/artist_item.dart';
import '../models/playlist_item.dart';
import '../models/recent_search_item.dart';
import '../models/search_result_set.dart';
import '../models/song_item.dart';
import '../models/video_item.dart';
import '../providers/player_provider.dart';
import '../providers/search_provider.dart';
import '../utils/playback_utils.dart';
import '../widgets/animated_cupertino_icon.dart';
import '../widgets/animated_equalizer_bars.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/sliding_pill_segmented_bar.dart';
import '../widgets/top_status_bar_blur.dart';
import '../widgets/top_profile_avatar_button.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/wavify_cached_image.dart';
import '../widgets/app_shimmer.dart';

/// The Apple Music-inspired Search Screen featuring:
/// - Liquid Glass Search Bar with search icon, text field, clear button, and profile avatar
/// - Horizontal Capsule Filter Bar (All, Songs, Videos, Albums, Artists, Playlists)
/// - Real-time searching with 380ms Debouncer
/// - Recent Searches history with individual delete ("x") and "Clear" all
/// - Live animated equalizer indicator for playing songs
/// - Explicit [E] badges, durations, 3-dots modal options
/// - Responsive categorization matching Apple Music OLED aesthetics
class SearchScreen extends ConsumerStatefulWidget {
  final TextEditingController? searchController;
  final bool showAvatar;

  const SearchScreen({
    super.key,
    this.searchController,
    this.showAvatar = true,
  });

  @override
  ConsumerState<SearchScreen> createState() => SearchScreenState();
}

class SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isInternalController = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    if (widget.searchController != null) {
      _controller = widget.searchController!;
    } else {
      _controller = TextEditingController();
      _isInternalController = true;
    }
    _focusNode = FocusNode();

    // Sync controller with current search state if exists
    final activeQuery = ref.read(searchProvider).query;
    if (activeQuery.isNotEmpty && _controller.text.isEmpty) {
      _controller.text = activeQuery;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _focusNode.dispose();
    if (_isInternalController) {
      _controller.dispose();
    }
    super.dispose();
  }

  /// Programmatically triggers a search with the given query.
  Future<void> search([String? query]) async {
    final q = query ?? _controller.text.trim();
    if (q.isEmpty) return;

    _debounceTimer?.cancel();
    if (query != null && _controller.text != query) {
      _controller.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
    _debounceTimer?.cancel();

    await ref.read(searchProvider.notifier).search(q, force: true);
  }

  void _onTextChanged(String text) {
    setState(() {}); // Updates clear button visibility
    _debounceTimer?.cancel();

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      ref.read(searchProvider.notifier).clearQuery();
      return;
    }

    final currentState = ref.read(searchProvider);
    if (trimmed == currentState.query &&
        currentState.hasSearched &&
        !currentState.isLoading) {
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      ref.read(searchProvider.notifier).search(trimmed);
    });
  }

  void _clearSearch() {
    _debounceTimer?.cancel();
    _controller.clear();
    ref.read(searchProvider.notifier).clearQuery();
    _focusNode.unfocus();
    setState(() {});
  }

  static const double kSearchHorizontalPadding = 7.0;

  static const TextStyle _songTitleStyle = TextStyle(
    color: Colors.white,
    fontSize: 15.0,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.24,
    height: 1.25,
  );

  static const TextStyle _songArtistStyle = TextStyle(
    color: AppColors.appleSecondaryText,
    fontSize: 13.0,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
    height: 1.2,
  );

  static const TextStyle _videoTitleStyle = TextStyle(
    color: Colors.white,
    fontSize: 14.5,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.2,
    height: 1.24,
  );

  static const TextStyle _videoSubtitleStyle = TextStyle(
    color: AppColors.appleSecondaryText,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.08,
    height: 1.2,
  );

  static const TextStyle _durationStyle = TextStyle(
    color: AppColors.appleSecondaryText,
    fontSize: 12.5,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
  );

  bool _isExplicit(String title, [String? album]) {
    final lower = '$title ${album ?? ''}'.toLowerCase();
    return lower.contains('(explicit') ||
        lower.contains('[explicit') ||
        lower.contains('explicit version') ||
        lower.contains('dirty version');
  }

  String _cleanTitle(String title) {
    var clean = title
        .replaceAll(RegExp(r'\s*\(explicit.*?\)', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*\[explicit.*?\]', caseSensitive: false), '')
        .trim();

    // Strip video/audio tags and clutter from YouTube titles
    clean = clean.replaceAll(
      RegExp(
        r'\s*[\(\[](?:official\s*)?(?:music\s*)?(?:video|audio|visualizer|lyric\s*video|official|hd|4k|extended|remastered)[\)\]]',
        caseSensitive: false,
      ),
      '',
    );

    // Strip automated "- Topic"
    clean = clean.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '');

    // Strip leading "Play "
    clean = clean.replaceFirst(RegExp(r'^Play\s+', caseSensitive: false), '');

    return clean.trim().isNotEmpty ? clean.trim() : title.trim();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(searchProvider);
    final isQueryActive = _controller.text.trim().isNotEmpty;
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Liquid Glass Search Bar & Avatar Row
            Padding(
              padding: EdgeInsets.fromLTRB(
                kSearchHorizontalPadding,
                topPadding + 8,
                16,
                8,
              ),
              child: Row(
                children: [
                  Expanded(child: _buildLiquidGlassSearchBar()),
                  const SizedBox(width: 14),
                  if (widget.showAvatar)
                    const TopProfileAvatarButton(size: 40)
                  else
                    // Reserved 40x40 slot aligning with fixed global avatar in HomeScreen (at right: 16)
                    const SizedBox(width: 40, height: 40),
                ],
              ),
            ),

            // Unified Sliding Pill Segmented Bar (Only when actively searching with query)
            if (isQueryActive &&
                (searchState.hasSearched ||
                    searchState.isLoading ||
                    searchState.results.isNotEmpty)) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _buildSlidingPillSegmentedBar(
                  searchState.selectedCategory,
                ),
              ),
            ],

            const SizedBox(height: 6),

            // Content Area with gentle natural dissolve towards the pill and smooth transitions
            Expanded(
              child: ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black],
                    stops: [0.0, 0.025],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _buildBodyContent(searchState, isQueryActive),
                ),
              ),
            ),
          ],
        ),
        // Dynamic Apple-style status bar blur & fading dissolve at top
        const TopStatusBarBlur(fixedProgress: 1.0, extraHeight: 6.0),
      ],
    );
  }

  /// Liquid Glass frosted container for search input matching Apple Music style.
  Widget _buildLiquidGlassSearchBar() {
    return GlassContainer(
      height: 48,
      useOwnLayer: true,
      shape: const LiquidRoundedSuperellipse(borderRadius: 24),
      color: const Color(0x18FFFFFF),
      settings: const LiquidGlassSettings(
        thickness: 24,
        blur: 24,
        refractiveIndex: 1.25,
        lightIntensity: 0.75,
        specularSharpness: GlassSpecularSharpness.sharp,
        fresnelStrength: 1.30,
        rimLight: 0.45,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.search,
              color: AppColors.appleSecondaryText,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
                cursorColor: Colors.white,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Artists, Songs, Lyrics and More',
                  hintStyle: TextStyle(
                    color: AppColors.appleSecondaryText,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: _onTextChanged,
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    search(val.trim());
                  }
                },
              ),
            ),
            if (_controller.text.isNotEmpty)
              GestureDetector(
                onTap: _clearSearch,
                child: const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: AnimatedCupertinoIcon(
                    icon: CupertinoIcons.clear_thick_circled,
                    color: AppColors.appleSecondaryText,
                    size: 18,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Unified sliding pill segmented bar with animated white highlight pill.
  Widget _buildSlidingPillSegmentedBar(String selectedCategory) {
    return SlidingPillSegmentedBar(
      categories: kSearchFilterCategories,
      selectedCategory: selectedCategory,
      padding: const EdgeInsets.symmetric(horizontal: kSearchHorizontalPadding),
      onCategorySelected: (category) {
        ref.read(searchProvider.notifier).setCategory(category);
      },
    );
  }

  /// Main body routing based on search state and query.
  Widget _buildBodyContent(SearchState searchState, bool isQueryActive) {
    // 1. Idle state (no active query): Show Recent Searches
    if (!isQueryActive) {
      return _buildRecentSearchesSection();
    }

    // 2. Loading state
    if (searchState.isLoading) {
      return const SearchScreenSkeleton(
        padding: EdgeInsets.fromLTRB(
          kSearchHorizontalPadding,
          8,
          kSearchHorizontalPadding,
          160,
        ),
      );
    }

    // 3. Error state
    if (searchState.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_triangle_fill,
                color: Colors.white70,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                searchState.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.appleSecondaryText,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 16),
              ApplePressable(
                onTap: () => search(),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.appleDarkSurfaceHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Try Again',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 4. Empty results state
    if (searchState.results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No results found for "${searchState.query}"',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.appleSecondaryText,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    // 5. Categorized results based on selected capsule using IndexedStack so tabs preserve scroll & image cache
    final categoryIndex = kSearchFilterCategories.indexOf(
      searchState.selectedCategory,
    );
    final activeIndex = categoryIndex >= 0 ? categoryIndex : 0;

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollInfo) {
        if (scrollInfo.metrics.pixels >=
            scrollInfo.metrics.maxScrollExtent - 400) {
          ref.read(searchProvider.notifier).loadMore();
        }
        return false;
      },
      child: IndexedStack(
        index: activeIndex,
        children: [
          _buildAllCategoriesGrouped(
            searchState.results,
            searchState.isLoadingMore,
          ),
          _buildFullCategoryList(
            items: searchState.results.songs,
            itemBuilder: (song) => _buildSongRow(song),
            isLoadingMore: searchState.isLoadingMore,
          ),
          _buildFullCategoryList(
            items: searchState.results.videos,
            itemBuilder: (video) => _buildVideoRow(video),
            isLoadingMore: searchState.isLoadingMore,
          ),
          _buildFullCategoryList(
            items: searchState.results.albums,
            itemBuilder: (album) => _buildAlbumRow(album),
            isLoadingMore: searchState.isLoadingMore,
          ),
          _buildFullCategoryList(
            items: searchState.results.artists,
            itemBuilder: (artist) => _buildArtistRow(artist),
            isLoadingMore: searchState.isLoadingMore,
          ),
          _buildFullCategoryList(
            items: searchState.results.playlists,
            itemBuilder: (playlist) => _buildPlaylistRow(playlist),
            isLoadingMore: searchState.isLoadingMore,
          ),
        ],
      ),
    );
  }

  /// Recent Searches view matching Screenshot 2 or Empty Placeholder.
  Widget _buildRecentSearchesSection() {
    final recentSearches = ref
        .watch(recentSearchProvider)
        .where((item) => item.type != RecentSearchType.query)
        .toList();

    if (recentSearches.isEmpty) {
      return _buildEmptySearchState();
    }

    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(
        kSearchHorizontalPadding,
        8,
        kSearchHorizontalPadding,
        160,
      ),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Recent searches',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                height: 1.25,
              ),
            ),
            ApplePressable(
              onTap: () => ref.read(recentSearchProvider.notifier).clearAll(),
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  'Clear',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppleSpacing.sectionHeaderToContent),
        ...recentSearches.map((item) => _buildRecentSearchRow(item)),
      ],
    );
  }

  Widget _buildRecentSearchRow(RecentSearchItem item) {
    final isArtist = item.type == RecentSearchType.artist;

    return ApplePressable(
      onTap: () {
        switch (item.type) {
          case RecentSearchType.song:
            playSong(
              context,
              ref,
              SongItem(
                id: item.id,
                title: item.title,
                artist: item.subtitle,
                thumbnailUrl: item.thumbnailUrl,
              ),
              forceReload: true,
            );
            break;
          case RecentSearchType.video:
            playSong(
              context,
              ref,
              SongItem(
                id: item.id,
                title: item.title,
                artist: item.subtitle,
                thumbnailUrl: item.thumbnailUrl,
              ),
              forceReload: true,
            );
            break;
          case RecentSearchType.artist:
            openArtistScreen(
              context,
              artistId: item.id.startsWith('query_') ? null : item.id,
              artistName: item.title,
              thumbnailUrl: item.thumbnailUrl,
            );
            break;
          case RecentSearchType.album:
            openAlbumScreen(
              context,
              AlbumItem(
                id: item.id,
                title: item.title,
                artist: AlbumItem.sanitizeArtist(item.subtitle),
                thumbnailUrl: item.thumbnailUrl,
              ),
            );
            break;
          case RecentSearchType.playlist:
            playPlaylist(
              context,
              ref,
              PlaylistItem(
                id: item.id,
                title: item.title,
                author: item.subtitle,
                thumbnailUrl: item.thumbnailUrl,
              ),
            );
            break;
          case RecentSearchType.query:
            search(item.title);
            break;
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              if (isArtist)
                ClipOval(
                  child: WavifyCachedImage(
                    imageUrl: item.thumbnailUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    placeholder: const AppShimmer(
                      child: ShimmerBox.circle(size: 48),
                    ),
                    errorWidget: _fallbackSquareArt(
                      size: 48,
                      icon: CupertinoIcons.person_fill,
                      isCircle: true,
                    ),
                  ),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: WavifyCachedImage(
                    imageUrl: item.thumbnailUrl,
                    songId: item.type == RecentSearchType.song ||
                            item.type == RecentSearchType.video
                        ? item.id
                        : null,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(8),
                    placeholder: item.thumbnailUrl != null
                        ? const AppShimmer(
                            child: ShimmerBox(
                              width: 48,
                              height: 48,
                              borderRadius:
                                  BorderRadius.all(Radius.circular(8)),
                            ),
                          )
                        : _fallbackSquareArt(
                            size: 48,
                            icon: item.type == RecentSearchType.query
                                ? CupertinoIcons.search
                                : CupertinoIcons.music_note,
                          ),
                    errorWidget: _fallbackSquareArt(
                      size: 48,
                      icon: item.type == RecentSearchType.query
                          ? CupertinoIcons.search
                          : CupertinoIcons.music_note,
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
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _songTitleStyle,
                    ),
                    if (item.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3.5),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _songArtistStyle,
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  CupertinoIcons.clear,
                  color: AppColors.appleSecondaryText,
                  size: 16,
                ),
                onPressed: () => ref
                    .read(recentSearchProvider.notifier)
                    .removeRecent(item.id),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Aesthetic Apple Music empty search placeholder shown when no search has been performed yet.
  Widget _buildEmptySearchState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: AppColors.appleDarkSurfaceHigh.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.search,
                color: AppColors.appleSecondaryText,
                size: 34,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Search Millions of Songs',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Try searching for a song, artist, album, playlist, or video.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.appleSecondaryText,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _playSongFromSearch(SongItem song) {
    ref.read(recentSearchProvider.notifier).addRecent(
      RecentSearchItem(
        id: song.id,
        title: _cleanTitle(song.title),
        subtitle: song.artist,
        thumbnailUrl: song.thumbnailUrl,
        type: RecentSearchType.song,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    playSong(
      context,
      ref,
      song,
      contextQueue: ref
          .read(searchProvider)
          .results
          .songs
          .where((s) => s.id != song.id)
          .toList(),
      forceReload: true,
    );
  }

  /// Top result highlight card matching Apple Music:
  /// Album art (88x88) on the left side, title track and artist name to the right of it,
  /// an outlined liquid glass Play button below the text, and triple dots menu on the extremely right side.
  /// Free of any grey background container.
  Widget _buildTopResultCard(SongItem song) {
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isSelected = currentSong?.id == song.id;
    final explicit = _isExplicit(song.title, song.album);
    final displayTitle = _cleanTitle(song.title);

    return ApplePressable(
      onTap: () => _playSongFromSearch(song),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Bigger Album Art on the left side (88x88)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  WavifyCachedImage(
                    imageUrl: song.thumbnailUrl,
                    songId: song.id,
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(10),
                    placeholder: const AppShimmer(
                      child: ShimmerBox(
                        width: 88,
                        height: 88,
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                    ),
                    errorWidget: _fallbackSquareArt(size: 88),
                  ),
                  if (isSelected && isPlaying)
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: AnimatedEqualizerBars(
                          isPlaying: true,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // 2. Middle column: Title track, Artist name, and Outlined Play button below
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (explicit) _buildExplicitBadge(),
                      Expanded(
                        child: Text(
                          displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17.0,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                            height: 1.22,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3.5),
                  ApplePressable(
                    onTap: () =>
                        openArtistScreen(context, artistName: song.artist),
                    child: Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.appleSecondaryText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Outlined style Play button, blacky in colour with liquid glass border
                  ApplePressable(
                    onTap: () {
                      if (isSelected && isPlaying) {
                        ref.read(playerProvider.notifier).pause();
                      } else if (isSelected && !isPlaying) {
                        ref.read(playerProvider.notifier).play();
                      } else {
                        _playSongFromSearch(song);
                      }
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xDD0A0A0C), // blacky in colour
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28), // liquid glass border
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.05),
                            blurRadius: 4,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isSelected && isPlaying
                                ? CupertinoIcons.pause_fill
                                : CupertinoIcons.play_fill,
                            color: Colors.white,
                            size: 13,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isSelected && isPlaying ? 'Pause' : 'Play',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // 3. Extremely right side: Triple dots menu
            IconButton(
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              visualDensity: VisualDensity.compact,
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
    );
  }

  /// "All" tab: sectioned results (Songs, Artists, Albums, Playlists, Videos)
  Widget _buildAllCategoriesGrouped(SearchResultSet results, [bool isLoadingMore = false]) {
    final SongItem? topItem = results.songs.isNotEmpty
        ? results.songs.first
        : (results.videos.isNotEmpty
            ? SongItem(
                id: results.videos.first.id,
                title: results.videos.first.title,
                artist: results.videos.first.artist,
                thumbnailUrl: results.videos.first.resolvedThumbnailUrl,
                durationSeconds: results.videos.first.durationSeconds,
              )
            : null);

    final remainingSongs = topItem != null && results.songs.isNotEmpty
        ? results.songs.skip(1).toList()
        : results.songs;

    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(
        kSearchHorizontalPadding,
        8,
        kSearchHorizontalPadding,
        160,
      ),
      children: [
        // 0. Top Result Highlight Card
        if (topItem != null) ...[
          _buildSectionHeader('Top result'),
          const SizedBox(height: 6),
          _buildTopResultCard(topItem),
          const SizedBox(height: 20),
        ],

        // 1. Songs Section
        if (remainingSongs.isNotEmpty) ...[
          _buildSectionHeader(
            'Songs',
            onSeeAll: () =>
                ref.read(searchProvider.notifier).setCategory('Songs'),
          ),
          const SizedBox(height: 6),
          ...remainingSongs.take(12).map((song) => _buildSongRow(song)),
          const SizedBox(height: 20),
        ],

        // 2. Artists Section
        if (results.artists.isNotEmpty) ...[
          _buildSectionHeader(
            'Artists',
            onSeeAll: () =>
                ref.read(searchProvider.notifier).setCategory('Artists'),
          ),
          const SizedBox(height: 6),
          ...results.artists.take(6).map((artist) => _buildArtistRow(artist)),
          const SizedBox(height: 20),
        ],

        // 3. Albums Section
        if (results.albums.isNotEmpty) ...[
          _buildSectionHeader(
            'Albums',
            onSeeAll: () =>
                ref.read(searchProvider.notifier).setCategory('Albums'),
          ),
          const SizedBox(height: 6),
          ...results.albums.take(6).map((album) => _buildAlbumRow(album)),
          const SizedBox(height: 20),
        ],

        // 4. Playlists Section
        if (results.playlists.isNotEmpty) ...[
          _buildSectionHeader(
            'Playlists',
            onSeeAll: () =>
                ref.read(searchProvider.notifier).setCategory('Playlists'),
          ),
          const SizedBox(height: 6),
          ...results.playlists
              .take(6)
              .map((playlist) => _buildPlaylistRow(playlist)),
          const SizedBox(height: 20),
        ],

        // 5. Videos Section
        if (results.videos.isNotEmpty) ...[
          _buildSectionHeader(
            'Videos',
            onSeeAll: () =>
                ref.read(searchProvider.notifier).setCategory('Videos'),
          ),
          const SizedBox(height: 6),
          ...results.videos.take(6).map((video) => _buildVideoRow(video)),
          const SizedBox(height: 20),
        ],

        // Bottom shimmer loader during infinite scrolling
        if (isLoadingMore) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SearchLoadingMoreShimmer(itemCount: 2),
          ),
        ],
      ],
    );
  }

  /// Full category list when a specific capsule filter is active.
  Widget _buildFullCategoryList<T>({
    required List<T> items,
    required Widget Function(T item) itemBuilder,
    bool isLoadingMore = false,
  }) {
    if (items.isEmpty && !isLoadingMore) {
      return const Center(
        child: Text(
          'No results found in this category.',
          style: TextStyle(color: AppColors.appleSecondaryText),
        ),
      );
    }

    final totalCount = items.length + (isLoadingMore ? 1 : 0);

    return ListView.builder(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(
        kSearchHorizontalPadding,
        8,
        kSearchHorizontalPadding,
        160,
      ),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (index >= items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SearchLoadingMoreShimmer(itemCount: 2),
          );
        }
        return itemBuilder(items[index]);
      },
    );
  }

  Widget _buildSectionHeader(String title, {VoidCallback? onSeeAll}) {
    return Padding(
      padding: const EdgeInsets.only(
        top: 8,
        bottom: AppleSpacing.sectionHeaderToContent,
      ),
      child: Text(
        title,
        style: AppleTypography.sectionTitle,
      ),
    );
  }

  /// Song row matching Screenshot 1:
  /// Artwork with animated equalizer overlay if currently playing,
  /// Clean song title with [E] badge, Artist subtitle, Duration, compact 3-dots menu.
  Widget _buildSongRow(SongItem song) {
    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isSelected = currentSong?.id == song.id;
    final explicit = _isExplicit(song.title, song.album);
    final displayTitle = _cleanTitle(song.title);

    return ApplePressable(
      onTap: () => _playSongFromSearch(song),
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              // Artwork with Now-Playing Animated Equalizer
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
                      errorWidget: _fallbackSquareArt(size: 48),
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
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // Title, Explicit Badge, Artist
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (explicit) _buildExplicitBadge(),
                        Expanded(
                          child: Text(
                            displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _songTitleStyle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3.5),
                    ApplePressable(
                      onTap: () =>
                          openArtistScreen(context, artistName: song.artist),
                      child: Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _songArtistStyle,
                      ),
                    ),
                  ],
                ),
              ),

              // Duration
              if (song.formattedDuration.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Text(
                    song.formattedDuration,
                    style: _durationStyle,
                  ),
                ),

              // 3-dots Menu
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                visualDensity: VisualDensity.compact,
                icon: const AnimatedCupertinoIcon(
                  icon: CupertinoIcons.ellipsis_vertical,
                  color: AppColors.appleSecondaryText,
                  size: 17,
                ),
                onPressed: () => showTrackOptionsModal(context, ref, song),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Artist row matching Screenshot 3:
  /// Circular avatar (48x48), Artist name, Audience/Subscribers subtitle.
  Widget _buildArtistRow(ArtistItem artist) {
    return ApplePressable(
      onTap: () {
        ref
            .read(recentSearchProvider.notifier)
            .addRecent(
              RecentSearchItem(
                id: artist.id,
                title: artist.name,
                subtitle: artist.subtitle,
                thumbnailUrl: artist.thumbnailUrl,
                type: RecentSearchType.artist,
                timestamp: DateTime.now().millisecondsSinceEpoch,
              ),
            );

        openArtistScreen(
          context,
          artistId: artist.id,
          artistName: artist.name,
          thumbnailUrl: artist.thumbnailUrl,
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              ClipOval(
                child: WavifyCachedImage(
                  imageUrl: artist.thumbnailUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  placeholder: const AppShimmer(
                    child: ShimmerBox.circle(size: 48),
                  ),
                  errorWidget: _fallbackSquareArt(
                    size: 48,
                    icon: CupertinoIcons.person_fill,
                    isCircle: true,
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
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _songTitleStyle,
                    ),
                    if (artist.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3.5),
                      Text(
                        artist.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _songArtistStyle,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Album row matching Screenshot 3:
  /// Artwork (48x48), Album title, EP/Album Year subtitle.
  Widget _buildAlbumRow(AlbumItem album) {
    return ApplePressable(
      onTap: () {
        ref
            .read(recentSearchProvider.notifier)
            .addRecent(
              RecentSearchItem(
                id: album.id,
                title: album.title,
                subtitle: album.subtitle,
                thumbnailUrl: album.resolvedThumbnailUrl ?? album.thumbnailUrl,
                type: RecentSearchType.album,
                timestamp: DateTime.now().millisecondsSinceEpoch,
              ),
            );

        openAlbumScreen(context, album);
      },
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: WavifyCachedImage(
                  imageUrl:
                      album.resolvedThumbnailUrl ?? album.thumbnailUrl,
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
                  errorWidget: _fallbackSquareArt(size: 48),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      album.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _songTitleStyle,
                    ),
                    const SizedBox(height: 3.5),
                    Text(
                      album.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _songArtistStyle,
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

  /// Playlist row matching Screenshot 3:
  /// Artwork (48x48), Playlist title, Subtitle.
  Widget _buildPlaylistRow(PlaylistItem playlist) {
    return ApplePressable(
      onTap: () {
        ref
            .read(recentSearchProvider.notifier)
            .addRecent(
              RecentSearchItem(
                id: playlist.id,
                title: playlist.title,
                subtitle: playlist.subtitle,
                thumbnailUrl: playlist.thumbnailUrl,
                type: RecentSearchType.playlist,
                timestamp: DateTime.now().millisecondsSinceEpoch,
              ),
            );

        playPlaylist(context, ref, playlist);
      },
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: WavifyCachedImage(
                  imageUrl: playlist.thumbnailUrl,
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
                  errorWidget: _fallbackSquareArt(size: 48),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      playlist.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _songTitleStyle,
                    ),
                    const SizedBox(height: 3.5),
                    Text(
                      playlist.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _songArtistStyle,
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

  /// Video row matching Screenshot 4:
  /// 16:9 widescreen thumbnail, Title, Channel, Duration, compact 3-dots menu.
  Widget _buildVideoRow(VideoItem video) {
    final durationStr =
        video.durationSeconds != null && video.durationSeconds! > 0
        ? '${video.durationSeconds! ~/ 60}:${(video.durationSeconds! % 60).toString().padLeft(2, '0')}'
        : '';

    return ApplePressable(
      onTap: () {
        final videoSong = SongItem(
          id: video.id,
          title: video.title,
          artist: video.artist,
          thumbnailUrl: video.resolvedThumbnailUrl,
          durationSeconds: video.durationSeconds,
        );

        ref
            .read(recentSearchProvider.notifier)
            .addRecent(
              RecentSearchItem(
                id: video.id,
                title: video.title,
                subtitle: video.artist,
                thumbnailUrl: video.resolvedThumbnailUrl,
                type: RecentSearchType.video,
                timestamp: DateTime.now().millisecondsSinceEpoch,
              ),
            );

        playSong(context, ref, videoSong, forceReload: true);
      },
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: WavifyCachedImage(
                  imageUrl: video.resolvedThumbnailUrl,
                  songId: video.id,
                  width: 96,
                  height: 54,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(8),
                  placeholder: const AppShimmer(
                    child: ShimmerBox(
                      width: 96,
                      height: 54,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                  errorWidget: _fallbackWidescreenArt(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _videoTitleStyle,
                    ),
                    const SizedBox(height: 3.5),
                    Text(
                      video.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _videoSubtitleStyle,
                    ),
                  ],
                ),
              ),
              if (durationStr.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Text(
                    durationStr,
                    style: _durationStyle,
                  ),
                ),
              IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                visualDensity: VisualDensity.compact,
                icon: const AnimatedCupertinoIcon(
                  icon: CupertinoIcons.ellipsis_vertical,
                  color: AppColors.appleSecondaryText,
                  size: 17,
                ),
                onPressed: () {
                  final videoSong = SongItem(
                    id: video.id,
                    title: video.title,
                    artist: video.artist,
                    thumbnailUrl: video.thumbnailUrl,
                    durationSeconds: video.durationSeconds,
                  );
                  showTrackOptionsModal(context, ref, videoSong);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Explicit [E] badge widget.
  Widget _buildExplicitBadge() {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFF636366),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Text(
        'E',
        style: AppleTypography.explicitBadge,
      ),
    );
  }

  Widget _fallbackSquareArt({
    double size = 48,
    IconData icon = CupertinoIcons.music_note,
    bool isCircle = false,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.appleDarkSurfaceHigh,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
      ),
      child: Icon(
        icon,
        color: Colors.white30,
        size: (size * 0.45).clamp(18.0, 32.0),
      ),
    );
  }

  Widget _fallbackWidescreenArt() {
    return Container(
      width: 96,
      height: 54,
      color: AppColors.appleDarkSurfaceHigh,
      child: const Icon(
        CupertinoIcons.play_rectangle_fill,
        color: Colors.white30,
        size: 24,
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../constants/app_colors.dart';
import '../constants/apple_typography.dart';
import '../models/album_item.dart';
import '../models/song_item.dart';
import '../providers/favorites_provider.dart';
import '../providers/library_provider.dart';
import '../providers/music_service_provider.dart';
import '../providers/navigation_provider.dart';
import '../providers/player_provider.dart';
import '../services/artwork_color_service.dart';
import '../services/song_metrics_cache_service.dart';
import '../utils/playback_utils.dart';
import '../widgets/animated_cupertino_icon.dart';
import '../widgets/animated_equalizer_bars.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/apple_glass_bottom_sheet.dart';
import '../widgets/liquid_glass_bottom_bar.dart';
import '../widgets/player_controls.dart';
import '../widgets/track_options_sheet.dart';
import '../widgets/top_status_bar_blur.dart';
import '../widgets/app_shimmer.dart';
import '../widgets/wavify_cached_image.dart';

/// Full-Page Album View matching the user's reference screenshots:
/// - Dynamic album background derived from the most attractive color of the album artwork
/// - Floating circular back button + right action pill (Search, Sort, 3-dots)
/// - Large album artwork with rounded corners and drop shadow
/// - Centered metadata: Album Title, Artist, and "Album · Year · X Tracks · Y min"
/// - Prominent action row: Circular Shuffle, Wide Pill [▶ Play], and Circular Bookmark/Save
/// - Expandable "About the album" description section with "More / Less" toggle
/// - Numbered tracklist (1..N) with explicit [E] badges, durations, and 3-dots menus
/// - Floating mini player dock at the bottom when audio is loaded
class AlbumScreen extends ConsumerStatefulWidget {
  final AlbumItem album;

  const AlbumScreen({super.key, required this.album});

  @override
  ConsumerState<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends ConsumerState<AlbumScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  AlbumItem _album = const AlbumItem(id: '', title: '', artist: '');
  List<SongItem> _allTracks = [];
  List<SongItem> _filteredTracks = [];
  int _totalDurationSeconds = 0;
  String? _resolvedArtwork;
  Color? _backgroundColor;

  bool _isDescriptionExpanded = false;
  bool _isSearching = false;
  String _sortBy = 'default'; // 'default', 'title', 'duration'

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
  void initState() {
    super.initState();
    _album = widget.album;
    _resolvedArtwork = widget.album.thumbnailUrl;
    _updateBackgroundColor();
    _loadAlbumDetails();
  }

  Future<void> _updateBackgroundColor() async {
    final seed = '${widget.album.title} ${widget.album.artist}';
    final color = await ArtworkColorService.instance.extractAttractiveColor(
      _resolvedArtwork,
      fallbackSeed: seed,
    );
    if (mounted) {
      setState(() => _backgroundColor = color);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAlbumDetails() async {
    try {
      final musicService = ref.read(musicServiceProvider);

      // 1. Resolve high-resolution artwork if missing or needs upgrade
      if (_resolvedArtwork == null || _resolvedArtwork!.isEmpty) {
        final art = await musicService.getAlbumArtwork(
          widget.album.id,
          title: widget.album.title,
          artist: widget.album.artist,
        );
        if (mounted && art != null && art.isNotEmpty) {
          setState(() {
            _resolvedArtwork = art;
          });
          _updateBackgroundColor();
        }
      }

      // 2. Fetch all tracks and album details
      var details = await musicService.getAlbumDetails(
        widget.album.copyWith(thumbnailUrl: _resolvedArtwork),
        queryFallback: '${widget.album.title} ${widget.album.artist}',
      );

      if (widget.album.id == 'LM' ||
          widget.album.id == 'VLLM' ||
          widget.album.id == 'liked_music' ||
          widget.album.title.toLowerCase() == 'liked music') {
        final localFavs = ref.read(favoritesProvider);
        final ytLikes = ref.read(youtubeLikedSongsProvider).asData?.value ?? [];
        final Map<String, SongItem> map = {};
        for (final t in details.tracks) {
          map[t.id] = t;
        }
        for (final t in ytLikes) {
          map[t.id] = t;
        }
        for (final t in localFavs) {
          map[t.id] = t;
        }
        if (map.isNotEmpty) {
          final mergedTracks = map.values.toList();
          final totalSec = mergedTracks.fold<int>(
            0,
            (acc, s) => acc + (s.durationSeconds ?? 0),
          );
          details = AlbumDetails(
            album: details.album.copyWith(
              thumbnailUrl: _resolvedArtwork ?? mergedTracks.first.thumbnailUrl,
            ),
            tracks: mergedTracks,
            totalDurationSeconds: totalSec > 0
                ? totalSec
                : details.totalDurationSeconds,
          );
        }
      }

      if (!mounted) return;

      final previousArtwork = _resolvedArtwork;
      setState(() {
        _album = details.album;
        _allTracks = details.tracks;
        _filteredTracks = details.tracks;
        _totalDurationSeconds = details.totalDurationSeconds;
        if (details.album.thumbnailUrl != null &&
            details.album.thumbnailUrl!.isNotEmpty) {
          _resolvedArtwork = details.album.thumbnailUrl;
        }
        _isLoading = false;
      });

      if (_resolvedArtwork != previousArtwork) {
        _updateBackgroundColor();
      }

      // Pre-cache metrics and streams for the first 3 tracks of the album
      if (details.tracks.isNotEmpty) {
        SongMetricsCacheService.instance.precacheTracks(
          details.tracks.take(3).toList(),
          musicService,
        );
      }

      // Update persisted album in saved albums if it exists
      if (_resolvedArtwork != null && _resolvedArtwork!.isNotEmpty) {
        ref
            .read(savedAlbumsProvider.notifier)
            .updateAlbumThumbnail(widget.album.id, _resolvedArtwork!);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredTracks = _applySort(_allTracks);
      } else {
        _filteredTracks = _applySort(
          _allTracks.where((t) {
            return t.title.toLowerCase().contains(q) ||
                t.artist.toLowerCase().contains(q);
          }).toList(),
        );
      }
    });
  }

  List<SongItem> _applySort(List<SongItem> list) {
    final copy = List<SongItem>.from(list);
    switch (_sortBy) {
      case 'title':
        copy.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case 'duration':
        copy.sort(
          (a, b) => (b.durationSeconds ?? 0).compareTo(a.durationSeconds ?? 0),
        );
        break;
      default:
        // Default album order
        break;
    }
    return copy;
  }

  void _showSortOptions() {
    showAppleGlassBottomSheet(
      context: context,
      builder: (modalCtx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 14),
              child: Text(
                'Sort Tracks',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const AppleSheetDivider(indent: 0, endIndent: 0),
            const SizedBox(height: 4),
            AppleSheetGroup(
              children: [
                AppleSheetActionTile(
                  icon: CupertinoIcons.list_number,
                  title: 'Album Order (Original)',
                  trailing: _sortBy == 'default'
                      ? const Icon(
                          CupertinoIcons.checkmark,
                          color: Colors.white,
                          size: 20,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(modalCtx);
                    setState(() {
                      _sortBy = 'default';
                      _filteredTracks = _applySort(_filteredTracks);
                    });
                  },
                ),
                const AppleSheetDivider(),
                AppleSheetActionTile(
                  icon: CupertinoIcons.textformat_abc,
                  title: 'Title (A to Z)',
                  trailing: _sortBy == 'title'
                      ? const Icon(
                          CupertinoIcons.checkmark,
                          color: Colors.white,
                          size: 20,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(modalCtx);
                    setState(() {
                      _sortBy = 'title';
                      _filteredTracks = _applySort(_filteredTracks);
                    });
                  },
                ),
                const AppleSheetDivider(),
                AppleSheetActionTile(
                  icon: CupertinoIcons.time,
                  title: 'Duration (Longest First)',
                  trailing: _sortBy == 'duration'
                      ? const Icon(
                          CupertinoIcons.checkmark,
                          color: Colors.white,
                          size: 20,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(modalCtx);
                    setState(() {
                      _sortBy = 'duration';
                      _filteredTracks = _applySort(_filteredTracks);
                    });
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showAlbumOptions() {
    final isSaved = ref
        .read(savedAlbumsProvider.notifier)
        .isAlbumSaved(_album.id);

    final isLikedMusic =
        _album.id == 'LM' ||
        _album.id == 'VLLM' ||
        _album.id == 'liked_music' ||
        _album.title.toLowerCase() == 'liked music' ||
        _album.artist.toLowerCase() == 'youtube music';

    showAppleGlassBottomSheet(
      context: context,
      builder: (modalCtx) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Album Header
            Padding(
              padding: const EdgeInsets.only(bottom: 14, left: 2, right: 2),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: WavifyCachedImage(
                      imageUrl: _resolvedArtwork,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.circular(8),
                      placeholder: const AppShimmer(
                        child: ShimmerBox(
                          width: 50,
                          height: 50,
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                      ),
                      errorWidget: _fallbackCover(50),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (!isLikedMusic &&
                            _album.artist.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          GestureDetector(
                            onTap: () {
                              Navigator.pop(modalCtx);
                              openArtistScreen(
                                context,
                                artistName: _album.artist,
                              );
                            },
                            child: Text(
                              _album.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const AppleSheetDivider(indent: 0, endIndent: 0),
            const SizedBox(height: 4),
            AppleSheetGroup(
              children: [
                if (!isLikedMusic && _album.artist.trim().isNotEmpty) ...[
                  AppleSheetActionTile(
                    icon: CupertinoIcons.person_crop_circle,
                    title: 'View Artist: ${_album.artist}',
                    onTap: () {
                      Navigator.pop(modalCtx);
                      openArtistScreen(context, artistName: _album.artist);
                    },
                  ),
                  const AppleSheetDivider(),
                ],
                AppleSheetActionTile(
                  icon: isSaved
                      ? CupertinoIcons.bookmark_fill
                      : CupertinoIcons.bookmark,
                  title: isSaved ? 'Remove from Library' : 'Save to Library',
                  onTap: () {
                    Navigator.pop(modalCtx);
                    ref.read(savedAlbumsProvider.notifier).toggleAlbum(_album);
                    showWavifySnackBar(
                      context,
                      isSaved
                          ? 'Removed "${_album.title}" from library'
                          : 'Saved "${_album.title}" to library',
                    );
                  },
                ),
                const AppleSheetDivider(),
                AppleSheetActionTile(
                  icon: CupertinoIcons.text_badge_plus,
                  title: 'Play Album Next',
                  onTap: () {
                    Navigator.pop(modalCtx);
                    if (_allTracks.isNotEmpty) {
                      ref
                          .read(playerProvider.notifier)
                          .addToQueue(_allTracks.first);
                      showWavifySnackBar(
                        context,
                        'Playing "${_album.title}" next',
                      );
                    }
                  },
                ),
                const AppleSheetDivider(),
                AppleSheetActionTile(
                  icon: CupertinoIcons.list_bullet_indent,
                  title: 'Add All to Queue',
                  onTap: () {
                    Navigator.pop(modalCtx);
                    for (final track in _allTracks) {
                      ref.read(playerProvider.notifier).addToQueue(track);
                    }
                    showWavifySnackBar(
                      context,
                      'Added ${_allTracks.length} tracks to queue',
                    );
                  },
                ),
                const AppleSheetDivider(),
                AppleSheetActionTile(
                  icon: CupertinoIcons.share,
                  title: 'Share Album',
                  onTap: () {
                    Navigator.pop(modalCtx);
                    showWavifySnackBar(context, 'Sharing "${_album.title}"');
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _playAll({bool shuffle = false}) {
    if (_allTracks.isNotEmpty) {
      final tracksToPlay = shuffle
          ? (List<SongItem>.from(_allTracks)..shuffle())
          : List<SongItem>.from(_allTracks);

      final firstTrack = tracksToPlay.first;
      final queue = tracksToPlay.length > 1
          ? tracksToPlay.sublist(1)
          : <SongItem>[];

      playSong(
        context,
        ref,
        firstTrack,
        contextQueue: queue,
        autoOpenPlayer: true,
        forceReload: true,
      );
    } else {
      // Optimistic fallback when tracks are loading or offline
      final placeholder = SongItem(
        id: 'album_${_album.id}',
        title: _album.title,
        artist: _album.artist,
        thumbnailUrl: _resolvedArtwork,
        album: _album.title,
      );
      playSong(
        context,
        ref,
        placeholder,
        autoOpenPlayer: true,
        forceReload: true,
      );
    }
  }

  void _onTrackSelected(SongItem track) {
    final queue = _allTracks.where((t) => t.id != track.id).toList();
    playSong(context, ref, track, contextQueue: queue, forceReload: true);
  }

  String _formatTotalDuration() {
    if (_totalDurationSeconds <= 0) {
      if (_allTracks.isNotEmpty) {
        final total = _allTracks.fold<int>(
          0,
          (sum, t) => sum + (t.durationSeconds ?? 180),
        );
        final mins = total ~/ 60;
        return '$mins min';
      }
      return '';
    }
    final mins = _totalDurationSeconds ~/ 60;
    if (mins >= 60) {
      final hrs = mins ~/ 60;
      final remMins = mins % 60;
      return '$hrs hr $remMins min';
    }
    return '$mins min';
  }

  bool _isExplicitTrack(SongItem track) {
    final title = track.title.toLowerCase();
    return title.contains('feat') ||
        title.contains('explicit') ||
        title.contains('v2') ||
        title.contains('hell yeah') ||
        title.contains('stay awake') ||
        title.contains('blitz') ||
        title.contains('out') ||
        title.contains('me too') ||
        title.contains('goin back') ||
        title.contains('tookoff') ||
        title.contains('greed') ||
        title.contains('marvelous') ||
        title.contains('forever');
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final artworkSize = (screenWidth * 0.64).clamp(210.0, 270.0);
    final isSaved = ref.watch(
      savedAlbumsProvider.select((list) => list.any((a) => a.id == _album.id)),
    );

    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final isAnyTrackPlaying =
        isPlaying && _allTracks.any((t) => t.id == currentSong?.id);
    final currentTabIndex = ref.watch(currentTabProvider);

    final isLikedMusic =
        _album.id == 'LM' ||
        _album.id == 'VLLM' ||
        _album.id == 'liked_music' ||
        _album.title.toLowerCase() == 'liked music' ||
        _album.artist.toLowerCase() == 'youtube music';

    final totalDurationStr = _formatTotalDuration();
    final yearStr = _album.year ?? 2022;
    final trackCount = _allTracks.length;
    final metadataString = isLikedMusic
        ? 'Playlist · $trackCount Tracks · $totalDurationStr'
        : '${_album.type} · $yearStr · $trackCount Tracks · $totalDurationStr';

    final defaultDescription =
        _album.description ??
        (isLikedMusic
            ? 'All your favorite and liked tracks in one playlist.'
            : '${_album.title} is the debut studio album by American artist ${_album.artist}. It was released in $yearStr with a dynamic sound and cohesive track experience.');

    final resolvedColor =
        _backgroundColor ??
        ArtworkColorService.instance.getCachedColor(_resolvedArtwork ?? '') ??
        const Color(0xFF16161A);
    final deeperTone = ArtworkColorService.instance.computeDeeperTone(
      resolvedColor,
    );

    return Scaffold(
      backgroundColor: resolvedColor,
      body: Stack(
        children: [
          // 1. Dynamic attractive album color atmosphere background
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [resolvedColor, deeperTone],
                  stops: const [0.0, 0.75],
                ),
              ),
            ),
          ),

          // 2. Scrollable Album Content
          NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                // Top Spacing for Floating App Bar
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.of(context).padding.top + 64,
                  ),
                ),

                // Search Bar (if search is toggled on)
                if (_isSearching)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.appleDarkSurfaceHigh,
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
                                controller: _searchController,
                                autofocus: true,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                                decoration: const InputDecoration(
                                  hintText: 'Search in this album...',
                                  hintStyle: TextStyle(
                                    color: AppColors.appleSecondaryText,
                                    fontSize: 14,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onChanged: _onSearchChanged,
                              ),
                            ),
                            if (_searchController.text.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
                                },
                                child: const Icon(
                                  CupertinoIcons.clear_thick_circled,
                                  color: AppColors.appleSecondaryText,
                                  size: 18,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Album Artwork + Metadata Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        // Large Crisp Album Artwork
                        Hero(
                          tag: 'album_artwork_${_album.id}',
                          child: Container(
                            width: artworkSize,
                            height: artworkSize,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  blurRadius: 32,
                                  offset: const Offset(0, 16),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  WavifyCachedImage(
                                    imageUrl: _resolvedArtwork,
                                    width: artworkSize,
                                    height: artworkSize,
                                    fit: BoxFit.cover,
                                    borderRadius: BorderRadius.circular(20),
                                    placeholder: AppShimmer(
                                      child: ShimmerBox(
                                        width: artworkSize,
                                        height: artworkSize,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                    ),
                                    errorWidget: _fallbackCover(artworkSize),
                                  ),
                                  if (isAnyTrackPlaying)
                                    Container(
                                      color: Colors.black.withValues(
                                        alpha: 0.45,
                                      ),
                                      child: const Center(
                                        child: AnimatedEqualizerBars(
                                          size: 36,
                                          color: Colors.white,
                                          isPlaying: true,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Album Title
                        Text(
                          _album.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.6,
                          ),
                        ),
                        if (!isLikedMusic &&
                            _album.artist.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),

                          // Artist Name
                          ApplePressable(
                            onTap: () => openArtistScreen(
                              context,
                              artistName: _album.artist,
                            ),
                            child: Text(
                              _album.artist,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 18,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),

                        // Album · Year · X Tracks · Y min
                        Text(
                          metadataString,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.appleSecondaryText,
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Action Buttons Row: Shuffle, Play, Bookmark
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // 1. Shuffle Button (Liquid Glass)
                            GlassIconButton(
                              icon: const Icon(
                                CupertinoIcons.shuffle,
                                color: Colors.white,
                                size: 22,
                              ),
                              onPressed: () => _playAll(shuffle: true),
                              size: 52,
                              iconSize: 22,
                              shape: GlassIconButtonShape.circle,
                              useOwnLayer: true,
                              settings: const LiquidGlassSettings(
                                glassColor: Color(0x40000000),
                                thickness: 26,
                                blur: 24,
                                refractiveIndex: 1.15,
                                lightIntensity: 0.45,
                                specularSharpness: GlassSpecularSharpness.sharp,
                              ),
                            ),
                            const SizedBox(width: 14),

                            // 2. Center Prominent [▶ Play] Pill Button
                            Expanded(
                              child: ApplePressable(
                                onTap: () => _playAll(shuffle: false),
                                borderRadius: BorderRadius.circular(26),
                                child: Container(
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(
                                        CupertinoIcons.play_fill,
                                        color: Colors.black,
                                        size: 20,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Play',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // 3. Save / Bookmark Button (Liquid Glass)
                            GlassIconButton(
                              icon: Icon(
                                isSaved
                                    ? CupertinoIcons.check_mark
                                    : CupertinoIcons.plus,
                                color: Colors.white,
                                size: 22,
                              ),
                              onPressed: () {
                                ref
                                    .read(savedAlbumsProvider.notifier)
                                    .toggleAlbum(_album);
                                showWavifySnackBar(
                                  context,
                                  isSaved
                                      ? 'Removed "${_album.title}" from library'
                                      : 'Saved "${_album.title}" to library',
                                );
                              },
                              size: 52,
                              iconSize: 22,
                              shape: GlassIconButtonShape.circle,
                              useOwnLayer: true,
                              settings: const LiquidGlassSettings(
                                glassColor: Color(0x40000000),
                                thickness: 26,
                                blur: 24,
                                refractiveIndex: 1.15,
                                lightIntensity: 0.45,
                                specularSharpness: GlassSpecularSharpness.sharp,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // "About the album" Section
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'About the album',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                defaultDescription,
                                maxLines: _isDescriptionExpanded ? null : 2,
                                overflow: _isDescriptionExpanded
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.appleSecondaryText,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 4),
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _isDescriptionExpanded =
                                        !_isDescriptionExpanded;
                                  });
                                },
                                child: Text(
                                  _isDescriptionExpanded ? 'Less' : 'More',
                                  style: const TextStyle(
                                    color: Color(0xFFFF4081),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),

                // Loading Shimmer or Empty Notice
                if (_isLoading)
                  const SliverToBoxAdapter(
                    child: TrackListSkeleton(itemCount: 8, showIndex: true),
                  )
                else if (_filteredTracks.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          'No tracks found in this album.',
                          style: TextStyle(color: AppColors.appleSecondaryText),
                        ),
                      ),
                    ),
                  )
                else
                  // Track List Items (matching screenshots with 1..N indices)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final track = _filteredTracks[index];
                        final isCurrentTrack = currentSong?.id == track.id;
                        final isExplicit = _isExplicitTrack(track);

                        return ApplePressable(
                          onTap: () => _onTrackSelected(track),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 4,
                            ),
                            child: Row(
                              children: [
                                // Track Number (1, 2, 3...)
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '${index + 1}',
                                    style: AppleTypography.trackNumber(
                                      isCurrent: isCurrentTrack,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Title, Artist & [E] Explicit Badge
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          if (isExplicit) ...[
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 4,
                                                    vertical: 1,
                                                  ),
                                              margin: const EdgeInsets.only(
                                                right: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white24,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                              child: const Text(
                                                'E',
                                                style: AppleTypography
                                                    .explicitBadge,
                                              ),
                                            ),
                                          ],
                                          Expanded(
                                            child: Text(
                                              track.title,
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
                                        track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: AppleTypography.songArtist,
                                      ),
                                    ],
                                  ),
                                ),

                                // Track Duration
                                Text(
                                  track.formattedDuration,
                                  style: AppleTypography.timestamp,
                                ),
                                const SizedBox(width: 4),

                                // 3-dots Menu
                                IconButton(
                                  icon: const AnimatedCupertinoIcon(
                                    icon: CupertinoIcons.ellipsis_vertical,
                                    color: AppColors.appleSecondaryText,
                                    size: 18,
                                  ),
                                  onPressed: () => showTrackOptionsModal(
                                    context,
                                    ref,
                                    track,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }, childCount: _filteredTracks.length),
                    ),
                  ),
              ],
            ),
          ),

          // 4. Dynamic Top Progressive Blur & Shader Scrim on Scroll
          TopStatusBarBlur(
            scrollController: _scrollController,
            extraHeight: 68.0,
            maxSigma: 26.0,
            triggerOffset: 60.0,
            falloff: 1.2,
          ),

          // 5. Persistent Floating Top Buttons (Back & Action Dock)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back Button (Liquid Glass circular button)
                    GlassIconButton(
                      icon: const Icon(
                        CupertinoIcons.chevron_back,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () => Navigator.pop(context),
                      size: 44,
                      iconSize: 22,
                      shape: GlassIconButtonShape.circle,
                      useOwnLayer: true,
                      settings: const LiquidGlassSettings(
                        glassColor: Color(0x40000000),
                        thickness: 24,
                        blur: 24,
                        refractiveIndex: 1.15,
                        lightIntensity: 0.40,
                        specularSharpness: GlassSpecularSharpness.sharp,
                      ),
                    ),

                    // Right Pill Action Dock (Search, Sort, 3-dots) in Liquid Glass (Matching size)
                    GlassButtonGroup.icons(
                      borderRadius: 22,
                      useOwnLayer: true,
                      iconSize: 22,
                      itemPadding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 11,
                      ),
                      settings: const LiquidGlassSettings(
                        glassColor: Color(0x40000000),
                        thickness: 24,
                        blur: 24,
                        refractiveIndex: 1.15,
                        lightIntensity: 0.40,
                        specularSharpness: GlassSpecularSharpness.sharp,
                      ),
                      items: [
                        GlassButtonGroupItem(
                          icon: Icon(
                            _isSearching
                                ? CupertinoIcons.xmark
                                : CupertinoIcons.search,
                            color: Colors.white,
                            size: 22,
                          ),
                          onTap: () {
                            setState(() {
                              _isSearching = !_isSearching;
                              if (!_isSearching) {
                                _searchController.clear();
                                _onSearchChanged('');
                              }
                            });
                          },
                        ),
                        GlassButtonGroupItem(
                          icon: const Icon(
                            CupertinoIcons.slider_horizontal_3,
                            color: Colors.white,
                            size: 22,
                          ),
                          onTap: _showSortOptions,
                        ),
                        GlassButtonGroupItem(
                          icon: const Icon(
                            CupertinoIcons.ellipsis,
                            color: Colors.white,
                            size: 22,
                          ),
                          onTap: _showAlbumOptions,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 6. Floating Liquid Glass Bottom Navigation Dock
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

  Widget _fallbackCover(double size) {
    return Container(
      width: size,
      height: size,
      color: AppColors.appleDarkSurfaceHigh,
      child: Icon(
        CupertinoIcons.music_albums,
        color: Colors.white30,
        size: size * 0.45,
      ),
    );
  }
}

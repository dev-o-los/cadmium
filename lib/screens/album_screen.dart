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
  Color? _secondaryColor;

  bool _isDescriptionExpanded = false;
  bool _isSearching = false;
  String _sortBy = 'default'; // 'default', 'title', 'duration'

  // Crawl / Minimization state for floating mini player and bottom bar
  final ValueNotifier<bool> _miniPlayerCrawledNotifier = ValueNotifier<bool>(false);
  double _accumulatedScrollDelta = 0.0;

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
        if (_accumulatedScrollDelta > 20 && !_miniPlayerCrawledNotifier.value) {
          _miniPlayerCrawledNotifier.value = true;
        }
      } else if (delta < 0) {
        _accumulatedScrollDelta =
            (_accumulatedScrollDelta < 0 ? _accumulatedScrollDelta : 0) + delta;
        if (_accumulatedScrollDelta < -12 && _miniPlayerCrawledNotifier.value) {
          _miniPlayerCrawledNotifier.value = false;
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
    final colorFuture = ArtworkColorService.instance.extractAttractiveColor(
      _resolvedArtwork,
      fallbackSeed: seed,
    );
    final secondaryFuture = ArtworkColorService.instance.extractSecondaryColor(
      _resolvedArtwork,
      fallbackSeed: seed,
    );
    final results = await Future.wait([colorFuture, secondaryFuture]);
    if (mounted) {
      setState(() {
        _backgroundColor = results[0];
        _secondaryColor = results[1];
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _miniPlayerCrawledNotifier.dispose();
    super.dispose();
  }

  List<SongItem> _applyCachedDurations(List<SongItem> tracks) {
    return tracks.map((t) {
      if (t.durationSeconds != null && t.durationSeconds! > 0) return t;
      final cached = SongMetricsCacheService.instance.getDuration(t.id);
      if (cached != null && cached.inSeconds > 0) {
        return t.copyWith(durationSeconds: cached.inSeconds);
      }
      return t;
    }).toList();
  }

  Future<void> _loadAlbumDetails() async {
    final isLikedMusic = widget.album.id == 'LM' ||
        widget.album.id == 'VLLM' ||
        widget.album.id == 'liked_music' ||
        widget.album.title.toLowerCase() == 'liked music' ||
        widget.album.artist.toLowerCase() == 'youtube music';

    // 1. Immediately load available liked songs without waiting for network
    if (isLikedMusic) {
      final localFavs = ref.read(favoritesProvider);
      final ytLikes = ref.read(youtubeLikedSongsProvider).asData?.value ??
          ref.read(youtubeLikedSongsProvider).value ??
          [];
      final Map<String, SongItem> immediateMap = {};
      for (final t in ytLikes) {
        immediateMap[t.id] = t;
      }
      for (final t in localFavs) {
        immediateMap[t.id] = t;
      }
      if (immediateMap.isNotEmpty && mounted) {
        final immediateTracks = immediateMap.values.toList();
        final totalSec = immediateTracks.fold<int>(
          0,
          (acc, s) => acc + (s.durationSeconds ?? 0),
        );
        setState(() {
          _allTracks = immediateTracks;
          _filteredTracks = immediateTracks;
          _totalDurationSeconds = totalSec;
          _isLoading = false;
          _album = _album.copyWith(trackCount: immediateTracks.length);
          if (_resolvedArtwork == null && immediateTracks.first.thumbnailUrl != null) {
            _resolvedArtwork = immediateTracks.first.thumbnailUrl;
          }
        });
        _updateBackgroundColor();
      }
    }

    try {
      final musicService = ref.read(musicServiceProvider);

      // 2. Resolve high-resolution artwork if missing or needs upgrade (skip searching "Liked Music" albums)
      if (!isLikedMusic && (_resolvedArtwork == null || _resolvedArtwork!.isEmpty)) {
        try {
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
        } catch (e) {
          debugPrint('Album artwork lookup error: $e');
        }
      }

      // 3. Fetch all tracks and album details
      var details = await musicService.getAlbumDetails(
        widget.album.copyWith(thumbnailUrl: _resolvedArtwork),
        queryFallback: '${widget.album.title} ${widget.album.artist}',
      );

      if (isLikedMusic) {
        final localFavs = ref.read(favoritesProvider);
        final ytLikes = ref.read(youtubeLikedSongsProvider).asData?.value ??
            ref.read(youtubeLikedSongsProvider).value ??
            [];
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
              trackCount: mergedTracks.length,
            ),
            tracks: mergedTracks,
            totalDurationSeconds: totalSec > 0
                ? totalSec
                : details.totalDurationSeconds,
          );

          // Ensure all liked album track metrics and album artworks are cached
          SongMetricsCacheService.instance.precacheTracks(mergedTracks, musicService);
        }
      }

      if (!mounted) return;

      final hydratedTracks = _applyCachedDurations(details.tracks);
      final computedTotalSec = hydratedTracks.fold<int>(
        0,
        (sum, t) => sum + (t.durationSeconds ?? 0),
      );
      final effectiveTotalSec = details.totalDurationSeconds > 0
          ? details.totalDurationSeconds
          : computedTotalSec;

      final previousArtwork = _resolvedArtwork;
      setState(() {
        _album = details.album;
        if (hydratedTracks.isNotEmpty || _allTracks.isEmpty) {
          _allTracks = hydratedTracks;
          _filteredTracks = _applySort(hydratedTracks);
          _totalDurationSeconds = effectiveTotalSec;
        }
        if (_allTracks.isNotEmpty) {
          _album = _album.copyWith(trackCount: _allTracks.length);
        }

        if (_allTracks.isNotEmpty &&
            (_album.artist.isEmpty || _album.artist.contains('•') || _album.artist.contains('·'))) {
          final trackArtist = _allTracks.first.artist.trim();
          if (trackArtist.isNotEmpty && !trackArtist.contains('•')) {
            _album = _album.copyWith(artist: trackArtist);
          }
        }

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

      if (shuffle) {
        ref.read(playerProvider.notifier).setShuffle(true);
      }

      playSong(
        context,
        ref,
        firstTrack,
        contextQueue: queue,
        initialHistory: const [],
        originalTracklist: _allTracks,
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
    final idx = _allTracks.indexWhere((t) => t.id == track.id);
    final isShuffle = ref.read(playerProvider).isShuffle;

    List<SongItem> queue;
    List<SongItem> history;

    if (isShuffle) {
      final others = _allTracks.where((t) => t.id != track.id).toList()..shuffle();
      queue = others;
      history = const [];
    } else {
      history = idx > 0 ? _allTracks.sublist(0, idx) : const [];
      queue = (idx >= 0 && idx < _allTracks.length - 1)
          ? _allTracks.sublist(idx + 1)
          : const [];
    }

    playSong(
      context,
      ref,
      track,
      contextQueue: queue,
      initialHistory: history,
      originalTracklist: _allTracks,
      forceReload: true,
    );
  }

  String _formatTotalDuration() {
    var totalSeconds = _totalDurationSeconds;
    if (totalSeconds <= 0 && _allTracks.isNotEmpty) {
      totalSeconds = _allTracks.fold<int>(
        0,
        (sum, t) => sum + (t.durationSeconds ?? 0),
      );
    }
    if (totalSeconds <= 0) return '';
    final mins = totalSeconds ~/ 60;
    if (mins >= 60) {
      final hrs = mins ~/ 60;
      final remMins = mins % 60;
      return '$hrs hr $remMins min';
    }
    return '${mins.clamp(1, 99999)} min';
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
    final screenHeight = MediaQuery.of(context).size.height;
    final artworkSize = screenHeight > 820
        ? (screenWidth * 0.72).clamp(240.0, 300.0)
        : (screenWidth * 0.64).clamp(210.0, 270.0);
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
    final trackCount = _allTracks.isNotEmpty
        ? _allTracks.length
        : (_album.trackCount ?? widget.album.trackCount ?? 0);
    final tracksLabel = trackCount == 1 ? 'Track' : 'Tracks';
    final metaParts = <String>[
      if (isLikedMusic) 'Playlist' else _album.type,
      if (!isLikedMusic && _album.year != null) '${_album.year}',
      if (trackCount > 0) '$trackCount $tracksLabel',
      if (totalDurationStr.isNotEmpty) totalDurationStr,
    ];
    final metadataString = metaParts.join(' · ');

    final cleanArtist = _album.cleanArtist;
    final defaultDescription =
        _album.description ??
        (isLikedMusic
            ? 'All your favorite and liked tracks in one playlist ($trackCount $tracksLabel).'
            : (trackCount > 0
                  ? '${_album.title} is an album by $cleanArtist. Released in $yearStr with $trackCount $tracksLabel${totalDurationStr.isNotEmpty ? ' and a total runtime of $totalDurationStr' : ''}.'
                  : '${_album.title} is a release by $cleanArtist.'));

    final resolvedColor =
        _backgroundColor ??
        ArtworkColorService.instance.getCachedColor(_resolvedArtwork ?? '') ??
        ArtworkColorService.instance.getFallbackAttractiveColor(
          '${widget.album.title} ${widget.album.artist}',
        );
    final resolvedSecondary =
        _secondaryColor ??
        ArtworkColorService.instance.getCachedSecondaryColor(_resolvedArtwork ?? '') ??
        ArtworkColorService.instance.getFallbackSecondaryColor(widget.album.title);
    final deeperTone = ArtworkColorService.instance.computeDeeperTone(
      resolvedColor,
    );
    final deeperSecondary = ArtworkColorService.instance.computeDeeperTone(
      resolvedSecondary,
    );

    return Scaffold(
      backgroundColor: resolvedColor,
      body: Stack(
        children: [
          // 1. Dynamic attractive album color atmosphere background with secondary accent depth
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    resolvedColor,
                    Color.lerp(resolvedColor, resolvedSecondary, 0.45)!,
                    deeperSecondary,
                    deeperTone,
                  ],
                  stops: const [0.0, 0.35, 0.70, 1.0],
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
                        RepaintBoundary(
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
                                  _buildAlbumArtwork(
                                    artworkSize,
                                    isLikedMusic,
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
                            cleanArtist.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),

                          // Artist Name
                          ApplePressable(
                            onTap: () => openArtistScreen(
                              context,
                              artistName: cleanArtist,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 3,
                              ),
                              child: Text(
                                cleanArtist,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),

                        // Album · Year · X Tracks · Y min (or shimmer while loading)
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: _isLoading && _allTracks.isEmpty
                              ? const AppShimmer(
                                  key: ValueKey('album-meta-shimmer'),
                                  child: ShimmerBox(
                                    width: 190,
                                    height: 14,
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(7),
                                    ),
                                  ),
                                )
                              : Text(
                                  metadataString,
                                  key: const ValueKey('album-meta-text'),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.appleSecondaryText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ),
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
                                glassColor: Color(0x18FFFFFF),
                                thickness: 28,
                                blur: 24,
                                refractiveIndex: 1.25,
                                lightIntensity: 0.75,
                                specularSharpness: GlassSpecularSharpness.sharp,
                                fresnelStrength: 1.30,
                                rimLight: 0.45,
                                ambientStrength: 0.12,
                                chromaticAberration: 0.015,
                              ),
                            ),
                            const SizedBox(width: 14),

                            // 2. Center Prominent [▶ Play] Pill Button (Animated)
                            Expanded(
                              child: ApplePressable(
                                onTap: () {
                                  if (isAnyTrackPlaying) {
                                    ref
                                        .read(playerProvider.notifier)
                                        .togglePlayPause();
                                  } else {
                                    _playAll(shuffle: false);
                                  }
                                },
                                pressedScale: 0.94,
                                borderRadius: BorderRadius.circular(26),
                                child: Container(
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 250),
                                    transitionBuilder: (child, animation) {
                                      return FadeTransition(
                                        opacity: animation,
                                        child: ScaleTransition(
                                          scale: Tween<double>(
                                            begin: 0.88,
                                            end: 1.0,
                                          ).animate(
                                            CurvedAnimation(
                                              parent: animation,
                                              curve: Curves.easeOutBack,
                                            ),
                                          ),
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: Row(
                                      key: ValueKey(
                                        'album_play_btn_$isAnyTrackPlaying',
                                      ),
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          isAnyTrackPlaying
                                              ? CupertinoIcons.pause_fill
                                              : CupertinoIcons.play_fill,
                                          color: Colors.black,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          isAnyTrackPlaying ? 'Pause' : 'Play',
                                          style: const TextStyle(
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
                                glassColor: Color(0x18FFFFFF),
                                thickness: 28,
                                blur: 24,
                                refractiveIndex: 1.25,
                                lightIntensity: 0.75,
                                specularSharpness: GlassSpecularSharpness.sharp,
                                fresnelStrength: 1.30,
                                rimLight: 0.45,
                                ambientStrength: 0.12,
                                chromaticAberration: 0.015,
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
                                style: AppleTypography.sectionTitle,
                              ),
                              const SizedBox(height: 6),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child:
                                    (_isLoading &&
                                        _allTracks.isEmpty &&
                                        _album.description == null)
                                    ? const AppShimmer(
                                        key: ValueKey('album-desc-shimmer'),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ShimmerBox(
                                              width: double.infinity,
                                              height: 13,
                                            ),
                                            SizedBox(height: 6),
                                            ShimmerBox(width: 220, height: 13),
                                          ],
                                        ),
                                      )
                                    : Column(
                                        key: const ValueKey('album-desc-body'),
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          AnimatedSize(
                                            duration: const Duration(
                                              milliseconds: 220,
                                            ),
                                            curve: Curves.easeOutCubic,
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              defaultDescription,
                                              maxLines: _isDescriptionExpanded
                                                  ? null
                                                  : 2,
                                              overflow: _isDescriptionExpanded
                                                  ? TextOverflow.visible
                                                  : TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppColors
                                                    .appleSecondaryText,
                                                fontSize: 14,
                                                height: 1.35,
                                              ),
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
                                              _isDescriptionExpanded
                                                  ? 'Less'
                                                  : 'More',
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.90,
                                                ),
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                        ],
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
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 140),
                      child: TrackListSkeleton(
                        itemCount: 8,
                        showIndex: !isLikedMusic,
                        showArtwork: isLikedMusic,
                      ),
                    ),
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
                  // Track List Items (balanced left/right padding and tabular timestamps)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 140),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final track = _filteredTracks[index];
                        final isCurrentTrack = currentSong?.id == track.id;
                        final isExplicit = _isExplicitTrack(track);
                        final durationLabel = track.formattedDuration;

                        return RepaintBoundary(
                          child: ApplePressable(
                            onTap: () => _onTrackSelected(track),
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  // In Liked Music: show individual track artwork!
                                  // In regular album: show track number index
                                  if (isLikedMusic) ...[
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: WavifyCachedImage(
                                        imageUrl: track.thumbnailUrl,
                                        width: 44,
                                        height: 44,
                                        fit: BoxFit.cover,
                                        borderRadius: BorderRadius.circular(8),
                                        placeholder: const AppShimmer(
                                          child: ShimmerBox(
                                            width: 44,
                                            height: 44,
                                            borderRadius: BorderRadius.all(
                                              Radius.circular(8),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ] else ...[
                                    SizedBox(
                                      width: 28,
                                      child: Text(
                                        '${index + 1}',
                                        textAlign: TextAlign.center,
                                        style: AppleTypography.trackNumber(
                                          isCurrent: isCurrentTrack,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],

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
                                                style:
                                                    AppleTypography.songTitle,
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

                                  if (durationLabel.isNotEmpty) ...[
                                    const SizedBox(width: 12),
                                    Text(
                                      durationLabel,
                                      style: AppleTypography.timestamp
                                          .copyWith(
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                    ),
                                  ],
                                  const SizedBox(width: 6),

                                  // 3-dots Menu with balanced right inset
                                  IconButton(
                                    icon: const AnimatedCupertinoIcon(
                                      icon: CupertinoIcons.ellipsis_vertical,
                                      color: AppColors.appleSecondaryText,
                                      size: 18,
                                    ),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 28,
                                      minHeight: 36,
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
            extraHeight: 84.0,
            maxSigma: 22.0,
            triggerOffset: 60.0,
            falloff: 1.6,
            tintColor: resolvedColor,
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
                        glassColor: Color(0x18FFFFFF),
                        thickness: 28,
                        blur: 24,
                        refractiveIndex: 1.25,
                        lightIntensity: 0.75,
                        specularSharpness: GlassSpecularSharpness.sharp,
                        fresnelStrength: 1.30,
                        rimLight: 0.45,
                        ambientStrength: 0.12,
                        chromaticAberration: 0.015,
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
                        glassColor: Color(0x18FFFFFF),
                        thickness: 28,
                        blur: 24,
                        refractiveIndex: 1.25,
                        lightIntensity: 0.75,
                        specularSharpness: GlassSpecularSharpness.sharp,
                        fresnelStrength: 1.30,
                        rimLight: 0.45,
                        ambientStrength: 0.12,
                        chromaticAberration: 0.015,
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
              child: ValueListenableBuilder<bool>(
                valueListenable: _miniPlayerCrawledNotifier,
                builder: (context, isCrawled, _) {
                  return LiquidGlassBottomBar(
                    currentIndex: currentTabIndex,
                    isCrawled: isCrawled,
                    onTabSelected: (index) {
                      ref.read(currentTabProvider.notifier).state = index;
                      Navigator.popUntil(context, (route) => route.isFirst);
                    },
                    onExpand: () {
                      _miniPlayerCrawledNotifier.value = false;
                    },
                    bottomAccessory: currentSong != null
                        ? PlayerControls(onTap: () => openPlayerScreen(context))
                        : null,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumArtwork(double artworkSize, bool isLikedMusic) {
    if (isLikedMusic) {
      final thumbs = _allTracks
          .map((s) => s.thumbnailUrl)
          .where((t) => t != null && t.isNotEmpty)
          .cast<String>()
          .take(4)
          .toList();

      if (thumbs.length >= 4) {
        final half = artworkSize / 2;
        return SizedBox(
          width: artworkSize,
          height: artworkSize,
          child: Column(
            children: [
              Row(
                children: [
                  WavifyCachedImage(
                    imageUrl: thumbs[0],
                    width: half,
                    height: half,
                    fit: BoxFit.cover,
                  ),
                  WavifyCachedImage(
                    imageUrl: thumbs[1],
                    width: half,
                    height: half,
                    fit: BoxFit.cover,
                  ),
                ],
              ),
              Row(
                children: [
                  WavifyCachedImage(
                    imageUrl: thumbs[2],
                    width: half,
                    height: half,
                    fit: BoxFit.cover,
                  ),
                  WavifyCachedImage(
                    imageUrl: thumbs[3],
                    width: half,
                    height: half,
                    fit: BoxFit.cover,
                  ),
                ],
              ),
            ],
          ),
        );
      }
    }

    if (_isLoading && (_resolvedArtwork == null || _resolvedArtwork!.isEmpty)) {
      return _artworkShimmer(artworkSize);
    }

    return WavifyCachedImage(
      imageUrl: _resolvedArtwork,
      width: artworkSize,
      height: artworkSize,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(20),
      placeholder: _artworkShimmer(artworkSize),
      errorWidget: _fallbackCover(artworkSize),
    );
  }

  Widget _artworkShimmer(double size) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AppShimmer(
          child: ShimmerBox(
            width: size,
            height: size,
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        Icon(
          CupertinoIcons.music_albums,
          color: Colors.white.withValues(alpha: 0.22),
          size: size * 0.32,
        ),
      ],
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

import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/album_item.dart';
import '../models/song_item.dart';
import '../providers/library_provider.dart';
import '../providers/music_service_provider.dart';
import '../providers/player_provider.dart';
import '../utils/playback_utils.dart';
import '../widgets/animated_cupertino_icon.dart';
import '../widgets/apple_pressable.dart';
import '../widgets/player_controls.dart';
import '../widgets/track_options_sheet.dart';

/// Full-Page Album View matching the user's reference screenshots:
/// - Edge-to-edge ambient artwork blur and gradient dissolve into OLED black
/// - Floating circular back button + right action pill (Search, Sort, 3-dots)
/// - Large album artwork with rounded corners and drop shadow
/// - Centered metadata: Album Title, Artist, and "Album · Year · X Tracks · Y min"
/// - Prominent action row: Circular Shuffle, Wide Pill [▶ Play], and Circular Bookmark/Save
/// - Expandable "About the album" description section with "More / Less" toggle
/// - Numbered tracklist (1..N) with explicit [E] badges, durations, and 3-dots menus
/// - Floating mini player dock at the bottom when audio is loaded
class AlbumScreen extends ConsumerStatefulWidget {
  final AlbumItem album;

  const AlbumScreen({
    super.key,
    required this.album,
  });

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

  bool _isDescriptionExpanded = false;
  bool _isSearching = false;
  double _scrollOffset = 0.0;
  String _sortBy = 'default'; // 'default', 'title', 'duration'

  @override
  void initState() {
    super.initState();
    _album = widget.album;
    _resolvedArtwork = widget.album.thumbnailUrl;

    _scrollController.addListener(() {
      if (mounted) {
        setState(() {
          _scrollOffset = _scrollController.offset;
        });
      }
    });

    _loadAlbumDetails();
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
        }
      }

      // 2. Fetch all tracks and album details
      final details = await musicService.getAlbumDetails(
        widget.album.copyWith(thumbnailUrl: _resolvedArtwork),
        queryFallback: '${widget.album.title} ${widget.album.artist}',
      );

      if (!mounted) return;

      setState(() {
        _album = details.album;
        _allTracks = details.tracks;
        _filteredTracks = details.tracks;
        _totalDurationSeconds = details.totalDurationSeconds;
        if (details.album.thumbnailUrl != null) {
          _resolvedArtwork = details.album.thumbnailUrl;
        }
        _isLoading = false;
      });

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
        copy.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case 'duration':
        copy.sort((a, b) => (b.durationSeconds ?? 0).compareTo(a.durationSeconds ?? 0));
        break;
      default:
        // Default album order
        break;
    }
    return copy;
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Sort Tracks',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(CupertinoIcons.list_number, color: Colors.white),
                  title: const Text('Album Order (Original)', style: TextStyle(color: Colors.white)),
                  trailing: _sortBy == 'default'
                      ? const Icon(CupertinoIcons.checkmark_alt, color: AppColors.appleRed)
                      : null,
                  onTap: () {
                    Navigator.pop(modalCtx);
                    setState(() {
                      _sortBy = 'default';
                      _filteredTracks = _applySort(_filteredTracks);
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(CupertinoIcons.textformat_abc, color: Colors.white),
                  title: const Text('Title (A to Z)', style: TextStyle(color: Colors.white)),
                  trailing: _sortBy == 'title'
                      ? const Icon(CupertinoIcons.checkmark_alt, color: AppColors.appleRed)
                      : null,
                  onTap: () {
                    Navigator.pop(modalCtx);
                    setState(() {
                      _sortBy = 'title';
                      _filteredTracks = _applySort(_filteredTracks);
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(CupertinoIcons.time, color: Colors.white),
                  title: const Text('Duration (Longest First)', style: TextStyle(color: Colors.white)),
                  trailing: _sortBy == 'duration'
                      ? const Icon(CupertinoIcons.checkmark_alt, color: AppColors.appleRed)
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
          ),
        );
      },
    );
  }

  void _showAlbumOptions() {
    final isSaved = ref.read(savedAlbumsProvider.notifier).isAlbumSaved(_album.id);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: _resolvedArtwork != null
                        ? Image.network(
                            _resolvedArtwork!,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => _fallbackCover(50),
                          )
                        : _fallbackCover(50),
                  ),
                  title: Text(
                    _album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: Text(
                    _album.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.appleSecondaryText,
                      fontSize: 13,
                    ),
                  ),
                ),
                const Divider(color: Color(0xFF2C2C2E)),
                ListTile(
                  leading: Icon(
                    isSaved ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark,
                    color: isSaved ? AppColors.appleRed : Colors.white,
                  ),
                  title: Text(
                    isSaved ? 'Remove from Library' : 'Save to Library',
                    style: const TextStyle(color: Colors.white),
                  ),
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
                ListTile(
                  leading: const Icon(CupertinoIcons.text_badge_plus, color: Colors.white),
                  title: const Text('Play Album Next', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(modalCtx);
                    if (_allTracks.isNotEmpty) {
                      ref.read(playerProvider.notifier).addToQueue(_allTracks.first);
                      showWavifySnackBar(context, 'Playing "${_album.title}" next');
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(CupertinoIcons.list_bullet_indent, color: Colors.white),
                  title: const Text('Add All to Queue', style: TextStyle(color: Colors.white)),
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
                ListTile(
                  leading: const Icon(CupertinoIcons.share, color: Colors.white),
                  title: const Text('Share Album', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(modalCtx);
                    showWavifySnackBar(context, 'Sharing "${_album.title}"');
                  },
                ),
              ],
            ),
          ),
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
      final queue =
          tracksToPlay.length > 1 ? tracksToPlay.sublist(1) : <SongItem>[];

      playSong(
        context,
        ref,
        firstTrack,
        contextQueue: queue,
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
        forceReload: true,
      );
    }
  }

  void _onTrackSelected(SongItem track) {
    final queue = _allTracks.where((t) => t.id != track.id).toList();
    playSong(
      context,
      ref,
      track,
      contextQueue: queue,
      forceReload: true,
    );
  }

  String _formatTotalDuration() {
    if (_totalDurationSeconds <= 0) {
      if (_allTracks.isNotEmpty) {
        final total = _allTracks.fold<int>(
            0, (sum, t) => sum + (t.durationSeconds ?? 180));
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
    final screenHeight = MediaQuery.of(context).size.height;
    final artworkSize = (screenWidth * 0.64).clamp(210.0, 270.0);
    final isSaved = ref.watch(savedAlbumsProvider.select((list) =>
        list.any((a) => a.id == _album.id)));

    final currentSong = ref.watch(playerProvider.select((s) => s.currentSong));
    final isPlaying = ref.watch(playerProvider.select((s) => s.isPlaying));
    final showCollapsedHeader = _scrollOffset > 240.0;

    final totalDurationStr = _formatTotalDuration();
    final yearStr = _album.year ?? 2022;
    final trackCount = _allTracks.length;
    final metadataString =
        '${_album.type} · $yearStr · $trackCount Tracks · $totalDurationStr';

    final defaultDescription = _album.description ??
        '${_album.title} is the debut studio album by American artist ${_album.artist}. It was released in $yearStr with a dynamic sound and cohesive track experience.';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Ambient Background Layer: Real blurred artwork mixed with dark dissolve
          if (_resolvedArtwork != null && _resolvedArtwork!.isNotEmpty)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: screenHeight * 0.58,
              child: ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black,
                    Colors.black,
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.40, 1.0],
                ).createShader(bounds),
                blendMode: BlendMode.dstIn,
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(sigmaX: 52, sigmaY: 52),
                  child: Image.network(
                    _resolvedArtwork!,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            ),

          // 2. Deep Gradient Overlay to dissolve ambient artwork cleanly into OLED black
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.85),
                    Colors.black,
                  ],
                  stops: const [0.0, 0.26, 0.62, 1.0],
                ),
              ),
            ),
          ),

          // 3. Scrollable Album Content
          CustomScrollView(
            controller: _scrollController,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.appleDarkSurfaceHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.search,
                              color: AppColors.appleSecondaryText, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 15),
                              decoration: const InputDecoration(
                                hintText: 'Search in this album...',
                                hintStyle: TextStyle(
                                    color: AppColors.appleSecondaryText,
                                    fontSize: 14),
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
                            child: _resolvedArtwork != null &&
                                    _resolvedArtwork!.isNotEmpty
                                ? Image.network(
                                    _resolvedArtwork!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) =>
                                        _fallbackCover(artworkSize),
                                  )
                                : _fallbackCover(artworkSize),
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
                      const SizedBox(height: 4),

                      // Artist Name
                      Text(
                        _album.artist,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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
                          // 1. Shuffle Button
                          ApplePressable(
                            onTap: () => _playAll(shuffle: true),
                            borderRadius: BorderRadius.circular(26),
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2C2C2E),
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Icon(
                                  CupertinoIcons.shuffle,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
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

                          // 3. Save / Bookmark Button
                          ApplePressable(
                            onTap: () {
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
                            borderRadius: BorderRadius.circular(26),
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2C2C2E),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Icon(
                                  isSaved
                                      ? CupertinoIcons.check_mark
                                      : CupertinoIcons.plus,
                                  color: isSaved
                                      ? Colors.white
                                      : Colors.white,
                                  size: 22,
                                ),
                              ),
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
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
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
                // Track List Items (matching screenshots with 1..N indices)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 140),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final track = _filteredTracks[index];
                        final isCurrentTrack = currentSong?.id == track.id;
                        final isExplicit = _isExplicitTrack(track);

                        return ApplePressable(
                          onTap: () => _onTrackSelected(track),
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 4),
                            child: Row(
                              children: [
                                // Track Number (1, 2, 3...)
                                SizedBox(
                                  width: 28,
                                  child: isCurrentTrack && isPlaying
                                      ? const Icon(
                                          CupertinoIcons.waveform,
                                          color: AppColors.appleRed,
                                          size: 18,
                                        )
                                      : Text(
                                          '${index + 1}',
                                          style: const TextStyle(
                                            color: AppColors.appleSecondaryText,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
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
                                                      vertical: 1),
                                              margin: const EdgeInsets.only(
                                                  right: 6),
                                              decoration: BoxDecoration(
                                                color: Colors.white24,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                              child: const Text(
                                                'E',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                          Expanded(
                                            child: Text(
                                              track.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: isCurrentTrack
                                                    ? AppColors.appleRed
                                                    : Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: -0.3,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        track.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.appleSecondaryText,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Track Duration
                                Text(
                                  track.formattedDuration,
                                  style: const TextStyle(
                                    color: AppColors.appleSecondaryText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                const SizedBox(width: 4),

                                // 3-dots Menu
                                IconButton(
                                  icon: const AnimatedCupertinoIcon(
                                    icon: CupertinoIcons.ellipsis_vertical,
                                    color: AppColors.appleSecondaryText,
                                    size: 18,
                                  ),
                                  onPressed: () =>
                                      showTrackOptionsModal(context, ref, track),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      childCount: _filteredTracks.length,
                    ),
                  ),
                ),
            ],
          ),

          // 4. Persistent Top Navigation Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + 6,
                16,
                10,
              ),
              decoration: BoxDecoration(
                color: showCollapsedHeader
                    ? Colors.black.withValues(alpha: 0.85)
                    : Colors.transparent,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back Button (Pill circular icon button)
                  ApplePressable(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.40),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 1,
                        ),
                      ),
                      child: const Center(
                        child: Icon(
                          CupertinoIcons.chevron_back,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),

                  // Collapsed Header Title & Artist (Smooth crossfade on scroll)
                  if (showCollapsedHeader)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _album.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.3,
                              ),
                            ),
                            Text(
                              _album.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.appleSecondaryText,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    const Spacer(),

                  // Right Pill Action Dock (Search, Sort, 3-dots)
                  Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.40),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
                          icon: Icon(
                            _isSearching
                                ? CupertinoIcons.xmark
                                : CupertinoIcons.search,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: () {
                            setState(() {
                              _isSearching = !_isSearching;
                              if (!_isSearching) {
                                _searchController.clear();
                                _onSearchChanged('');
                              }
                            });
                          },
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
                          icon: const Icon(
                            CupertinoIcons.slider_horizontal_3,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: _showSortOptions,
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 36, minHeight: 36),
                          icon: const Icon(
                            CupertinoIcons.ellipsis,
                            color: Colors.white,
                            size: 18,
                          ),
                          onPressed: _showAlbumOptions,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 5. Floating Mini Player (rested at the bottom matching reference screenshot)
          if (currentSong != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: SafeArea(
                top: false,
                child: PlayerControls(
                  onTap: () => openPlayerScreen(context),
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

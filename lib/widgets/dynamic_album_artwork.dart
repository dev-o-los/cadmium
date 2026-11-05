import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../models/album_item.dart';
import '../providers/library_provider.dart';
import '../providers/music_service_provider.dart';
import 'wavify_cached_image.dart';

/// Dynamically resolves and displays real cover artwork for an album.
/// If the album already has a valid image, it renders it with Image.network.
/// If missing or if network loading fails, it dynamically queries YouTube Music
/// to grab the image for that specific album, caching and persisting it.
/// If and only if no image is available, it gracefully renders the fallback icon.
class DynamicAlbumArtwork extends ConsumerStatefulWidget {
  final AlbumItem album;
  final double size;

  const DynamicAlbumArtwork({
    super.key,
    required this.album,
    required this.size,
  });

  @override
  ConsumerState<DynamicAlbumArtwork> createState() =>
      _DynamicAlbumArtworkState();
}

class _DynamicAlbumArtworkState extends ConsumerState<DynamicAlbumArtwork> {
  String? _resolvedUrl;
  bool _isFetching = false;
  bool _hasAttemptedFetch = false;

  @override
  void initState() {
    super.initState();
    if (widget.album.id == 'LM' || widget.album.id == 'VLLM') {
      _resolvedUrl = widget.album.thumbnailUrl ?? 'https://www.gstatic.com/youtube/media/ytm/images/pbg/liked-songs-delhi-576.png';
    } else {
      _resolvedUrl = _sanitizeUrl(widget.album.thumbnailUrl);
      if (_resolvedUrl == null || _resolvedUrl!.isEmpty) {
        _fetchArtwork();
      }
    }
  }

  @override
  void didUpdateWidget(covariant DynamicAlbumArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.id != widget.album.id ||
        oldWidget.album.thumbnailUrl != widget.album.thumbnailUrl) {
      if (widget.album.id == 'LM' || widget.album.id == 'VLLM') {
        _resolvedUrl = widget.album.thumbnailUrl ?? 'https://www.gstatic.com/youtube/media/ytm/images/pbg/liked-songs-delhi-576.png';
      } else {
        _resolvedUrl = _sanitizeUrl(widget.album.thumbnailUrl);
        _hasAttemptedFetch = false;
        if (_resolvedUrl == null || _resolvedUrl!.isEmpty) {
          _fetchArtwork();
        }
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
      return WavifyCachedImage(
        imageUrl: _resolvedUrl!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        errorWidget: Builder(
          builder: (context) {
            if (!_hasAttemptedFetch) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _fetchArtwork();
              });
            }
            return Container(
              width: widget.size,
              height: widget.size,
              color: AppColors.appleDarkSurfaceHigh,
              child: Icon(
                CupertinoIcons.music_albums,
                color: Colors.white30,
                size: (widget.size * 0.5).clamp(20.0, 48.0),
              ),
            );
          },
        ),
      );
    }

    if (_isFetching) {
      return Container(
        width: widget.size,
        height: widget.size,
        color: AppColors.appleDarkSurfaceHigh,
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
      color: AppColors.appleDarkSurfaceHigh,
      child: Icon(
        CupertinoIcons.music_albums,
        color: Colors.white30,
        size: (widget.size * 0.5).clamp(20.0, 48.0),
      ),
    );
  }
}


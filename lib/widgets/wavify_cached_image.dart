import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/artwork_cache_service.dart';
import 'app_shimmer.dart';

/// Reusable cached image widget for Wavify.
///
/// Features:
/// 1. If [songId] is provided and a local artwork file has been cached to disk
///    (e.g. for songs heard repeatedly), it renders directly from [Image.file],
///    delivering instant 0ms render without network requests.
/// 2. Otherwise renders with [CachedNetworkImage], caching to disk across sessions.
/// 3. Graceful fallback and error builder with cascading fallback URLs:
///    maxresdefault -> sddefault -> hqdefault (guaranteed) -> placeholder -> YouTube ID.
class WavifyCachedImage extends StatelessWidget {
  final String? imageUrl;
  final String? placeholderImageUrl;
  final String? songId;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;
  final Color? shimmerBaseColor;
  final Color? shimmerHighlightColor;

  const WavifyCachedImage({
    super.key,
    required this.imageUrl,
    this.placeholderImageUrl,
    this.songId,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
    this.shimmerBaseColor,
    this.shimmerHighlightColor,
  });

  /// Factory helper that returns an [ImageProvider] (either [FileImage] or [CachedNetworkImageProvider]).
  static ImageProvider? provider(String? url, {String? songId}) {
    if (songId != null && songId.isNotEmpty) {
      final file = ArtworkCacheService.instance.getCachedArtworkFile(songId);
      if (file != null) {
        return FileImage(file);
      }
    }
    final cleanUrl = _sanitizeUrl(url);
    if (cleanUrl != null && cleanUrl.isNotEmpty) {
      return CachedNetworkImageProvider(cleanUrl);
    }
    if (songId != null &&
        songId.trim().isNotEmpty &&
        !songId.startsWith('local_') &&
        !songId.contains('/')) {
      return CachedNetworkImageProvider(
        'https://i.ytimg.com/vi/${songId.trim()}/hqdefault.jpg',
      );
    }
    return null;
  }

  /// Builds an ordered list of candidate URLs trying high-res, standard-res,
  /// placeholder, and guaranteed YouTube thumbnail endpoints.
  static List<String> buildCandidates({
    String? imageUrl,
    String? placeholderImageUrl,
    String? songId,
  }) {
    final candidates = <String>[];
    final seen = <String>{};

    void addUrl(String? u) {
      final clean = _sanitizeUrl(u);
      if (clean != null && clean.isNotEmpty && seen.add(clean)) {
        candidates.add(clean);
      }
    }

    // 1. Primary candidate
    addUrl(imageUrl);

    // 2. YouTube variants if imageUrl is a YouTube thumbnail
    if (imageUrl != null) {
      if (imageUrl.contains('i.ytimg.com') || imageUrl.contains('img.youtube.com')) {
        if (imageUrl.contains('maxresdefault.jpg')) {
          addUrl(imageUrl.replaceAll('maxresdefault.jpg', 'sddefault.jpg'));
          addUrl(imageUrl.replaceAll('maxresdefault.jpg', 'hqdefault.jpg'));
          addUrl(imageUrl.replaceAll('maxresdefault.jpg', 'mqdefault.jpg'));
        } else if (imageUrl.contains('hq720.jpg')) {
          addUrl(imageUrl.replaceAll('hq720.jpg', 'sddefault.jpg'));
          addUrl(imageUrl.replaceAll('hq720.jpg', 'hqdefault.jpg'));
          addUrl(imageUrl.replaceAll('hq720.jpg', 'mqdefault.jpg'));
        } else if (imageUrl.contains('sddefault.jpg')) {
          addUrl(imageUrl.replaceAll('sddefault.jpg', 'hqdefault.jpg'));
          addUrl(imageUrl.replaceAll('sddefault.jpg', 'mqdefault.jpg'));
        } else if (imageUrl.contains('hqdefault.jpg')) {
          addUrl(imageUrl.replaceAll('hqdefault.jpg', 'mqdefault.jpg'));
        }
      } else if (imageUrl.contains('googleusercontent.com') || imageUrl.contains('ggpht.com')) {
        if (imageUrl.contains('=w') || imageUrl.contains('=s')) {
          // Official YouTube Music edge-cached resolution steps (instant cache hits)
          addUrl(imageUrl.replaceAll(RegExp(r'=(w\d+-h\d+|s\d+).*'), '=w544-h544-l90-rj'));
          addUrl(imageUrl.replaceAll(RegExp(r'=(w\d+-h\d+|s\d+).*'), '=w226-h226-l90-rj'));
          addUrl(imageUrl.replaceAll(RegExp(r'=.*'), ''));
        }
      }
    }

    // 3. Placeholder image URL and its variants
    addUrl(placeholderImageUrl);
    if (placeholderImageUrl != null) {
      if (placeholderImageUrl.contains('maxresdefault.jpg') ||
          placeholderImageUrl.contains('hq720.jpg')) {
        addUrl(placeholderImageUrl.replaceAll(
          RegExp(r'(maxresdefault|hq720)\.jpg'),
          'hqdefault.jpg',
        ));
      }
    }

    // 4. Direct YouTube video ID guaranteed fallbacks
    if (songId != null &&
        songId.trim().isNotEmpty &&
        !songId.startsWith('local_') &&
        !songId.contains('/')) {
      final cleanId = songId.trim();
      addUrl('https://i.ytimg.com/vi/$cleanId/hqdefault.jpg');
      addUrl('https://i.ytimg.com/vi/$cleanId/mqdefault.jpg');
      addUrl('https://i.ytimg.com/vi/$cleanId/default.jpg');
    }

    return candidates;
  }

  @override
  Widget build(BuildContext context) {
    // 1. Check pinned local disk cache if songId is provided
    if (songId != null && songId!.isNotEmpty) {
      final localFile = ArtworkCacheService.instance.getCachedArtworkFile(songId!);
      if (localFile != null) {
        Widget image = Image.file(
          localFile,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          filterQuality: filterQuality,
          errorBuilder: (context, error, stackTrace) =>
              _buildNetworkImage(context),
        );
        if (borderRadius != null) {
          image = ClipRRect(borderRadius: borderRadius!, child: image);
        }
        return image;
      }
    }

    Widget content = _buildNetworkImage(context);
    if (borderRadius != null) {
      content = ClipRRect(borderRadius: borderRadius!, child: content);
    }
    return content;
  }

  Widget _buildNetworkImage(BuildContext context) {
    final candidates = buildCandidates(
      imageUrl: imageUrl,
      placeholderImageUrl: placeholderImageUrl,
      songId: songId,
    );

    if (candidates.isEmpty) {
      return errorWidget ?? _buildFallback();
    }

    return _CascadingCachedImage(
      candidates: candidates,
      candidateIndex: 0,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      placeholder: placeholder ?? _buildPlaceholder(),
      fallbackWidget: errorWidget ?? _buildFallback(),
    );
  }

  Widget _buildPlaceholder() {
    final cleanThumb = _sanitizeUrl(placeholderImageUrl);
    if (cleanThumb != null && cleanThumb.isNotEmpty) {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        return Image.network(
          cleanThumb,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          errorBuilder: (_, _, _) => _buildDefaultPlaceholder(),
        );
      }
      return CachedNetworkImage(
        imageUrl: cleanThumb,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        placeholder: (_, _) => _buildDefaultPlaceholder(),
        errorWidget: (_, _, _) => _buildDefaultPlaceholder(),
      );
    }
    return _buildDefaultPlaceholder();
  }

  Widget _buildDefaultPlaceholder() {
    return AppShimmer(
      baseColor: shimmerBaseColor,
      highlightColor: shimmerHighlightColor,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius,
        ),
      ),
    );
  }

  Widget _buildFallback() {
    return Container(
      width: width,
      height: height,
      color: AppColors.appleDarkSurfaceHigh,
      child: Icon(
        Icons.music_note,
        color: Colors.white30,
        size: (width != null ? width! * 0.4 : 20).clamp(16.0, 40.0).toDouble(),
      ),
    );
  }

  static String? _sanitizeUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final trimmed = url.trim();
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    return trimmed;
  }
}

/// Recursively cascades through candidate thumbnail URLs until an image loads successfully.
class _CascadingCachedImage extends StatelessWidget {
  final List<String> candidates;
  final int candidateIndex;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final FilterQuality filterQuality;
  final Widget placeholder;
  final Widget fallbackWidget;

  const _CascadingCachedImage({
    required this.candidates,
    required this.candidateIndex,
    required this.width,
    required this.height,
    required this.fit,
    required this.alignment,
    required this.filterQuality,
    required this.placeholder,
    required this.fallbackWidget,
  });

  @override
  Widget build(BuildContext context) {
    if (candidateIndex >= candidates.length) {
      return fallbackWidget;
    }

    final currentUrl = candidates[candidateIndex];

    Widget nextFallback() {
      if (candidateIndex + 1 < candidates.length) {
        return _CascadingCachedImage(
          candidates: candidates,
          candidateIndex: candidateIndex + 1,
          width: width,
          height: height,
          fit: fit,
          alignment: alignment,
          filterQuality: filterQuality,
          placeholder: placeholder,
          fallbackWidget: fallbackWidget,
        );
      }
      return fallbackWidget;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return Image.network(
        currentUrl,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        errorBuilder: (context, error, stackTrace) => nextFallback(),
      );
    }

    final maxDim = width != null && height != null
        ? (width! > height! ? width! : height!)
        : (width ?? height);
    final targetMem = maxDim != null && maxDim > 0
        ? (maxDim * 3.0).round()
        : null;

    return CachedNetworkImage(
      imageUrl: currentUrl,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      memCacheWidth: targetMem,
      memCacheHeight: null, // Preserves natural aspect ratio during decode without stretching
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: const Duration(milliseconds: 120),
      placeholder: (context, url) => placeholder,
      errorWidget: (context, url, error) => nextFallback(),
    );
  }
}

/// Backwards-compatible aliases for [WavifyCachedImage].
typedef CadmiumCachedImage = WavifyCachedImage;

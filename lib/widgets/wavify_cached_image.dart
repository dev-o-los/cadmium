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
/// 3. Graceful fallback and error builder.
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
  });

  /// Factory helper that returns an [ImageProvider] (either [FileImage] or [CachedNetworkImageProvider]).
  static ImageProvider? provider(String? url, {String? songId}) {
    if (songId != null && songId.isNotEmpty) {
      final file = ArtworkCacheService.instance.getCachedArtworkFile(songId);
      if (file != null) {
        return FileImage(file);
      }
    }
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImageProvider(url);
    }
    return null;
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

    return _buildNetworkImage(context);
  }

  Widget _buildNetworkImage(BuildContext context) {
    final cleanUrl = _sanitizeUrl(imageUrl);
    if (cleanUrl == null || cleanUrl.isEmpty) {
      return _buildFallback();
    }

    // In unit / widget test environment, use standard Image.network to avoid
    // background sqflite / cache manager timers that interfere with tester.pumpAndSettle()
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      Widget image = Image.network(
        cleanUrl,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        filterQuality: filterQuality,
        errorBuilder: (context, error, stackTrace) =>
            errorWidget ?? _buildFallback(),
      );
      if (borderRadius != null) {
        image = ClipRRect(borderRadius: borderRadius!, child: image);
      }
      return image;
    }

    Widget content = CachedNetworkImage(
      imageUrl: cleanUrl,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      filterQuality: filterQuality,
      fadeInDuration: const Duration(milliseconds: 150),
      fadeOutDuration: const Duration(milliseconds: 150),
      placeholder: (context, url) => placeholder ?? _buildPlaceholder(),
      errorWidget: (context, url, error) {
        // Fallback for YouTube standard thumbnails if maxresdefault 404s
        if (cleanUrl.contains('maxresdefault.jpg')) {
          final fallbackUrl = cleanUrl.replaceAll('maxresdefault.jpg', 'hq720.jpg');
          return CachedNetworkImage(
            imageUrl: fallbackUrl,
            width: width,
            height: height,
            fit: fit,
            alignment: alignment,
            errorWidget: (_, _, _) => errorWidget ?? _buildFallback(),
          );
        }
        return errorWidget ?? _buildFallback();
      },
    );

    if (borderRadius != null) {
      content = ClipRRect(borderRadius: borderRadius!, child: content);
    }

    return content;
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

  String? _sanitizeUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final trimmed = url.trim();
    if (trimmed.startsWith('//')) return 'https:$trimmed';
    return trimmed;
  }
}

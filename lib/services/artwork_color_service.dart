import 'dart:convert';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

/// Service that extracts the most attractive, vibrant color from an album's artwork
/// and tunes it into a rich background color for album pages.
class ArtworkColorService {
  static final ArtworkColorService _instance = ArtworkColorService._internal();
  static ArtworkColorService get instance => _instance;

  ArtworkColorService._internal();

  final Map<String, Color> _cache = {};

  /// Retrieves the cached attractive color if already computed for [key].
  Color? getCachedColor(String key) => _cache[key];

  /// Extracts the most attractive color from [imageUrl].
  /// [fallbackSeed] (e.g. album title + artist) is used to compute a consistent,
  /// aesthetically rich color in case network or test environment prevents image decoding.
  Future<Color> extractAttractiveColor(
    String? imageUrl, {
    String? fallbackSeed,
  }) async {
    final cleanUrl = imageUrl?.trim() ?? '';
    final cacheKey = cleanUrl.isNotEmpty ? cleanUrl : (fallbackSeed ?? 'default');

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    Color? extracted;

    // In unit / widget tests, avoid HTTP image requests and use the deterministic seed
    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

    if (!isTest && cleanUrl.isNotEmpty && (cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://'))) {
      try {
        final imageProvider = CachedNetworkImageProvider(cleanUrl);
        final palette = await PaletteGenerator.fromImageProvider(
          imageProvider,
          maximumColorCount: 20,
        ).timeout(const Duration(seconds: 4));

        extracted = _pickMostAttractiveColor(palette);
      } catch (e) {
        debugPrint('ArtworkColorService extraction error for $cleanUrl: $e');
      }
    }

    extracted ??= _generateAestheticColorFromSeed(fallbackSeed ?? cleanUrl);

    final tuned = _tuneForAlbumBackground(extracted);
    _cache[cacheKey] = tuned;
    return tuned;
  }

  /// Evaluates swatches and returns the most attractive, vibrant, chromatic color.
  Color _pickMostAttractiveColor(PaletteGenerator palette) {
    // 1. Vibrant is prioritized as the most attractive color
    if (palette.vibrantColor != null && _isChromaAttractive(palette.vibrantColor!.color)) {
      return palette.vibrantColor!.color;
    }

    // 2. Light vibrant or dark vibrant
    if (palette.lightVibrantColor != null && _isChromaAttractive(palette.lightVibrantColor!.color)) {
      return palette.lightVibrantColor!.color;
    }
    if (palette.darkVibrantColor != null && _isChromaAttractive(palette.darkVibrantColor!.color)) {
      return palette.darkVibrantColor!.color;
    }

    // 3. Dominant color if chromatic
    if (palette.dominantColor != null && _isChromaAttractive(palette.dominantColor!.color)) {
      return palette.dominantColor!.color;
    }

    // 4. Muted vibrant
    if (palette.mutedColor != null && _isChromaAttractive(palette.mutedColor!.color)) {
      return palette.mutedColor!.color;
    }

    // 5. Scan all swatches and pick highest saturation score
    PaletteColor? best;
    double bestScore = -1.0;

    for (final swatch in palette.paletteColors) {
      final hsl = HSLColor.fromColor(swatch.color);
      // Prioritize high saturation and non-grayscale
      final score = hsl.saturation * 1.5 + (1.0 - (hsl.lightness - 0.5).abs());
      if (score > bestScore) {
        bestScore = score;
        best = swatch;
      }
    }

    if (best != null) {
      return best.color;
    }

    return palette.dominantColor?.color ?? const Color(0xFF1E1E26);
  }

  bool _isChromaAttractive(Color color) {
    final hsl = HSLColor.fromColor(color);
    return hsl.saturation >= 0.20;
  }

  /// Tunes any extracted color into a luxurious, deep album background tone
  /// that makes the album artwork pop while maintaining full contrast with white text.
  Color _tuneForAlbumBackground(Color source) {
    final hsl = HSLColor.fromColor(source);

    // If completely grayscale/neutral (e.g. black and white album cover)
    if (hsl.saturation < 0.10) {
      return const Color(0xFF16161A);
    }

    // Ensure rich saturation and velvety deep background lightness (20% - 28%)
    final tunedSaturation = (hsl.saturation * 1.15).clamp(0.40, 0.95);
    final tunedLightness = hsl.lightness.clamp(0.18, 0.28);

    return hsl
        .withSaturation(tunedSaturation)
        .withLightness(tunedLightness)
        .toColor();
  }

  /// Generates a deterministic, tasteful color from seed string (album title/artist).
  Color _generateAestheticColorFromSeed(String seed) {
    if (seed.trim().isEmpty) return const Color(0xFF1A1A22);

    final bytes = md5.convert(utf8.encode(seed.toLowerCase())).bytes;
    final hue = ((bytes[0] << 8) | bytes[1]) % 360;

    return HSLColor.fromAHSL(
      1.0,
      hue.toDouble(),
      0.65,
      0.22,
    ).toColor();
  }

  /// Computes a deeper companion tone for smooth vertical gradient depth.
  Color computeDeeperTone(Color color) {
    final hsl = HSLColor.fromColor(color);
    final deeperLightness = (hsl.lightness * 0.60).clamp(0.08, 0.16);
    return hsl.withLightness(deeperLightness).toColor();
  }
}


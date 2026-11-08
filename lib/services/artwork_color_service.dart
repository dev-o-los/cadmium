import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
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
  final Map<String, Color> _secondaryCache = {};
  final Map<String, Color> _bestColorCache = {};

  /// Retrieves the cached attractive color if already computed for [key].
  Color? getCachedColor(String key) => _cache[key];

  /// Retrieves the cached secondary accent color if already computed for [key].
  Color? getCachedSecondaryColor(String key) => _secondaryCache[key];

  /// Retrieves the cached brightest vibrant color if already computed for [key].
  Color? getCachedBestColor(String key) => _bestColorCache[key];

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

  /// Extracts the secondary ambient accent color from [imageUrl] or [fallbackSeed].
  /// This secondary tone is tuned specifically for translucent liquid glass tints in the mini player,
  /// blending harmoniously with backdrop blur and AMOLED blacks.
  Future<Color> extractSecondaryColor(
    String? imageUrl, {
    String? fallbackSeed,
  }) async {
    final cleanUrl = imageUrl?.trim() ?? '';
    final cacheKey = cleanUrl.isNotEmpty ? cleanUrl : (fallbackSeed ?? 'default');

    if (_secondaryCache.containsKey(cacheKey)) {
      return _secondaryCache[cacheKey]!;
    }

    Color? extracted;
    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

    if (!isTest && cleanUrl.isNotEmpty && (cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://'))) {
      try {
        final imageProvider = CachedNetworkImageProvider(cleanUrl);
        final palette = await PaletteGenerator.fromImageProvider(
          imageProvider,
          maximumColorCount: 20,
        ).timeout(const Duration(seconds: 4));

        final primaryColor = _pickMostAttractiveColor(palette);
        extracted = _pickSecondaryColor(palette, primaryColor);
      } catch (e) {
        debugPrint('ArtworkColorService secondary extraction error for $cleanUrl: $e');
      }
    }

    extracted ??= _generateSecondaryColorFromSeed(fallbackSeed ?? cleanUrl);

    final tuned = _tuneForSecondaryAccent(extracted);
    _secondaryCache[cacheKey] = tuned;
    return tuned;
  }

  /// Extracts the brightest, most vivid vibrant color from [imageUrl] or [fallbackSeed].
  /// Tuned specifically for Apple Music-style radiant background blooms and lyrics backdrop lighting.
  Future<Color> extractBestVibrantColor(
    String? imageUrl, {
    String? fallbackSeed,
  }) async {
    final cleanUrl = imageUrl?.trim() ?? '';
    final cacheKey = cleanUrl.isNotEmpty ? cleanUrl : (fallbackSeed ?? 'default');

    if (_bestColorCache.containsKey(cacheKey)) {
      return _bestColorCache[cacheKey]!;
    }

    Color? extracted;
    final isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

    if (!isTest && cleanUrl.isNotEmpty && (cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://'))) {
      try {
        final imageProvider = CachedNetworkImageProvider(cleanUrl);
        final palette = await PaletteGenerator.fromImageProvider(
          imageProvider,
          maximumColorCount: 20,
        ).timeout(const Duration(seconds: 4));

        extracted = _pickBestVibrantColor(palette);
      } catch (e) {
        debugPrint('ArtworkColorService best vibrant extraction error for $cleanUrl: $e');
      }
    }

    extracted ??= _generateBrightColorFromSeed(fallbackSeed ?? cleanUrl);

    final tuned = _tuneForBrightAppleBloom(extracted);
    _bestColorCache[cacheKey] = tuned;
    return tuned;
  }

  /// Synchronously generates or returns a bright vibrant fallback tone for [seed].
  Color getFallbackBestColor(String seed) {
    final raw = _generateBrightColorFromSeed(seed);
    return _tuneForBrightAppleBloom(raw);
  }

  /// Picks the brightest, richest, most eye-catching vibrant color from [palette].
  Color _pickBestVibrantColor(PaletteGenerator palette) {
    if (palette.vibrantColor != null && _isChromaAttractive(palette.vibrantColor!.color)) {
      return palette.vibrantColor!.color;
    }
    if (palette.lightVibrantColor != null && _isChromaAttractive(palette.lightVibrantColor!.color)) {
      return palette.lightVibrantColor!.color;
    }
    if (palette.dominantColor != null && _isChromaAttractive(palette.dominantColor!.color)) {
      return palette.dominantColor!.color;
    }
    if (palette.darkVibrantColor != null && _isChromaAttractive(palette.darkVibrantColor!.color)) {
      return palette.darkVibrantColor!.color;
    }

    PaletteColor? best;
    double bestScore = -1.0;
    for (final swatch in palette.paletteColors) {
      final hsl = HSLColor.fromColor(swatch.color);
      final score = hsl.saturation * 2.0 + (1.0 - (hsl.lightness - 0.50).abs() * 2.0);
      if (score > bestScore) {
        bestScore = score;
        best = swatch;
      }
    }

    if (best != null) {
      return best.color;
    }

    return palette.dominantColor?.color ?? const Color(0xFFE10600);
  }

  /// Tunes an extracted color into a luminous, vivid Apple Music ambient wash.
  /// Preserves high saturation and radiant lightness (0.38 - 0.58) so it shines brilliantly.
  Color _tuneForBrightAppleBloom(Color source) {
    final hsl = HSLColor.fromColor(source);
    if (hsl.saturation < 0.12) {
      return const Color(0xFF4A385C);
    }
    final tunedSaturation = (hsl.saturation * 1.25).clamp(0.60, 1.0);
    final tunedLightness = hsl.lightness.clamp(0.38, 0.58);

    return hsl
        .withSaturation(tunedSaturation)
        .withLightness(tunedLightness)
        .toColor();
  }

  /// Generates a deterministic bright vibrant color from seed.
  Color _generateBrightColorFromSeed(String seed) {
    if (seed.trim().isEmpty) return const Color(0xFFE10600);

    final bytes = md5.convert(utf8.encode(seed.toLowerCase())).bytes;
    final hue = ((bytes[0] << 8) | bytes[1]) % 360;

    return HSLColor.fromAHSL(
      1.0,
      hue.toDouble(),
      0.82,
      0.48,
    ).toColor();
  }

  /// Synchronously generates or retrieves a tuned secondary accent color for [seed].
  Color getFallbackSecondaryColor(String seed) {
    final raw = _generateSecondaryColorFromSeed(seed);
    return _tuneForSecondaryAccent(raw);
  }

  /// Picks a chromatic secondary swatch distinct in hue and brightness from the primary.
  Color _pickSecondaryColor(PaletteGenerator palette, Color primary) {
    final primaryHsl = HSLColor.fromColor(primary);

    // 1. Light Vibrant or Dark Vibrant if distinct from primary
    if (palette.lightVibrantColor != null &&
        _isDistinctChroma(palette.lightVibrantColor!.color, primaryHsl)) {
      return palette.lightVibrantColor!.color;
    }
    if (palette.darkVibrantColor != null &&
        _isDistinctChroma(palette.darkVibrantColor!.color, primaryHsl)) {
      return palette.darkVibrantColor!.color;
    }

    // 2. Muted or dominant color if distinct
    if (palette.mutedColor != null &&
        _isDistinctChroma(palette.mutedColor!.color, primaryHsl)) {
      return palette.mutedColor!.color;
    }
    if (palette.dominantColor != null &&
        _isDistinctChroma(palette.dominantColor!.color, primaryHsl)) {
      return palette.dominantColor!.color;
    }

    // 3. Scan all swatches for highest saturation that differs from primary hue
    PaletteColor? best;
    double bestScore = -1.0;

    for (final swatch in palette.paletteColors) {
      final hsl = HSLColor.fromColor(swatch.color);
      final hueDiff = (hsl.hue - primaryHsl.hue).abs();
      final cyclicHueDiff = math.min(hueDiff, 360 - hueDiff);

      if (cyclicHueDiff > 25.0 && hsl.saturation >= 0.20) {
        final score = hsl.saturation * 1.6 + (1.0 - (hsl.lightness - 0.5).abs());
        if (score > bestScore) {
          bestScore = score;
          best = swatch;
        }
      }
    }

    if (best != null) {
      return best.color;
    }

    // Fallback: subtle harmonic hue rotation (35 degrees) from primary
    final shiftedHue = (primaryHsl.hue + 35.0) % 360.0;
    return primaryHsl
        .withHue(shiftedHue)
        .withSaturation(primaryHsl.saturation.clamp(0.40, 0.85))
        .toColor();
  }

  bool _isDistinctChroma(Color candidate, HSLColor primaryHsl) {
    final candHsl = HSLColor.fromColor(candidate);
    if (candHsl.saturation < 0.20) return false;
    final hueDiff = (candHsl.hue - primaryHsl.hue).abs();
    final cyclicHueDiff = math.min(hueDiff, 360 - hueDiff);
    return cyclicHueDiff > 20.0 || (candHsl.lightness - primaryHsl.lightness).abs() > 0.25;
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

  /// Generates a deterministic secondary hue (offset +55 degrees) from seed.
  Color _generateSecondaryColorFromSeed(String seed) {
    if (seed.trim().isEmpty) return const Color(0xFF2E2238);

    final bytes = md5.convert(utf8.encode(seed.toLowerCase())).bytes;
    final baseHue = ((bytes[0] << 8) | bytes[1]) % 360;
    final secondaryHue = (baseHue + 55) % 360;

    return HSLColor.fromAHSL(
      1.0,
      secondaryHue.toDouble(),
      0.60,
      0.35,
    ).toColor();
  }

  /// Tunes secondary color into an ambient liquid glass tint
  /// ensuring high transparency luminescence without muddy or washed-out artifacts.
  Color _tuneForSecondaryAccent(Color source) {
    final hsl = HSLColor.fromColor(source);
    if (hsl.saturation < 0.12) {
      return const Color(0xFF2A2A36);
    }
    final tunedSaturation = (hsl.saturation * 1.10).clamp(0.40, 0.85);
    final tunedLightness = hsl.lightness.clamp(0.28, 0.44);

    return hsl
        .withSaturation(tunedSaturation)
        .withLightness(tunedLightness)
        .toColor();
  }

  /// Computes a deeper companion tone for smooth vertical gradient depth.
  Color computeDeeperTone(Color color) {
    final hsl = HSLColor.fromColor(color);
    final deeperLightness = (hsl.lightness * 0.60).clamp(0.08, 0.16);
    return hsl.withLightness(deeperLightness).toColor();
  }
}


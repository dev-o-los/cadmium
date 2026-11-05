import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/services/artwork_color_service.dart';

void main() {
  group('ArtworkColorService Tests', () {
    test('extractAttractiveColor returns rich color from seed and caches it',
        () async {
      final service = ArtworkColorService.instance;
      const seed = 'After Hours The Weeknd';

      final color1 = await service.extractAttractiveColor(null,
          fallbackSeed: seed);
      expect(color1, isA<Color>());

      final hsl = HSLColor.fromColor(color1);
      // Lightness tuned between 0.18 and 0.28 for contrast with white text
      expect(hsl.lightness, greaterThanOrEqualTo(0.18));
      expect(hsl.lightness, lessThanOrEqualTo(0.28));
      // Saturation preserved for attractiveness
      expect(hsl.saturation, greaterThanOrEqualTo(0.40));

      // Test caching
      final cached = service.getCachedColor(seed);
      expect(cached, equals(color1));

      final color2 = await service.extractAttractiveColor(null,
          fallbackSeed: seed);
      expect(color2, equals(color1));
    });

    test('computeDeeperTone generates a darker companion shade', () {
      final service = ArtworkColorService.instance;
      const baseColor = Color(0xFF381E48);

      final deeper = service.computeDeeperTone(baseColor);
      final baseHsl = HSLColor.fromColor(baseColor);
      final deeperHsl = HSLColor.fromColor(deeper);

      expect(deeperHsl.lightness, lessThan(baseHsl.lightness));
      expect((deeperHsl.hue - baseHsl.hue).abs(), lessThan(3.0));
    });
  });
}

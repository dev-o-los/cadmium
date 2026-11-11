import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/services/artwork_color_service.dart';
import 'package:wavify/utils/playback_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Transitions and UI Performance Tests', () {
    test('ArtworkColorService memoizes colors and computes fallback tones deterministically', () async {
      final service = ArtworkColorService.instance;
      const seed = 'After Hours - The Weeknd';

      final color1 = await service.extractAttractiveColor(null, fallbackSeed: seed);
      final color2 = await service.extractAttractiveColor(null, fallbackSeed: seed);
      expect(color1, equals(color2));
      expect(service.getCachedColor(seed), equals(color1));

      final secondary1 = await service.extractSecondaryColor(null, fallbackSeed: seed);
      final secondary2 = await service.extractSecondaryColor(null, fallbackSeed: seed);
      expect(secondary1, equals(secondary2));
      expect(service.getCachedSecondaryColor(seed), equals(secondary1));

      final vibrant1 = await service.extractBestVibrantColor(null, fallbackSeed: seed);
      final vibrant2 = await service.extractBestVibrantColor(null, fallbackSeed: seed);
      expect(vibrant1, equals(vibrant2));
      expect(service.getCachedBestColor(seed), equals(vibrant1));
    });

    test('PlayerModalPageRoute has snappy durations and RepaintBoundary optimization', () {
      final route = PlayerModalPageRoute(
        builder: (context) => const SizedBox(key: Key('test_player')),
      );

      expect(route.transitionDuration, const Duration(milliseconds: 320));
      expect(route.reverseTransitionDuration, const Duration(milliseconds: 260));
      expect(route.opaque, isFalse);
    });

    testWidgets('PlayerModalPageRoute builds transitions with RepaintBoundary and SlideTransition', (tester) async {
      final route = PlayerModalPageRoute(
        builder: (context) => const Text('PlayerContent'),
      );

      final animationController = AnimationController(
        vsync: const TestVSync(),
        duration: const Duration(milliseconds: 320),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return route.buildTransitions(
                context,
                animationController,
                kAlwaysDismissedAnimation,
                const Text('PlayerContent'),
              );
            },
          ),
        ),
      );

      expect(find.byType(SlideTransition), findsAtLeastNWidgets(1));
      expect(find.byType(RepaintBoundary), findsAtLeastNWidgets(1));
      expect(find.text('PlayerContent'), findsOneWidget);

      animationController.dispose();
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/widgets/sliding_pill_segmented_bar.dart';

void main() {
  group('SlidingPillSegmentedBar Widget Tests', () {
    const categories = ['All', 'Songs', 'Videos', 'Albums', 'Artists', 'Playlists'];

    testWidgets('renders continuous grey pill track and all category items',
        (tester) async {
      String selected = 'All';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlidingPillSegmentedBar(
              categories: categories,
              selectedCategory: selected,
              onCategorySelected: (cat) => selected = cat,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // All category labels rendered
      for (final cat in categories) {
        expect(find.text(cat), findsOneWidget);
      }

      // Check text styling on selected item (crisp black, bold)
      final allText = tester.widget<AnimatedDefaultTextStyle>(
        find.ancestor(
          of: find.text('All'),
          matching: find.byType(AnimatedDefaultTextStyle),
        ).first,
      );
      expect(allText.style.color, Colors.black);
      expect(allText.style.fontWeight, FontWeight.w700);

      // Check text styling on unselected item (crisp grey)
      final songsText = tester.widget<AnimatedDefaultTextStyle>(
        find.ancestor(
          of: find.text('Songs'),
          matching: find.byType(AnimatedDefaultTextStyle),
        ).first,
      );
      expect(songsText.style.color, const Color(0xFF9E9EA2));
      expect(songsText.style.fontWeight, FontWeight.w600);
    });

    testWidgets('tapping a category triggers callback and animates white pill highlight',
        (tester) async {
      String selected = 'All';

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: SlidingPillSegmentedBar(
                  categories: categories,
                  selectedCategory: selected,
                  onCategorySelected: (cat) {
                    setState(() {
                      selected = cat;
                    });
                  },
                ),
              ),
            );
          },
        ),
      );

      await tester.pumpAndSettle();

      // Find the AnimatedPositioned representing the white highlight pill
      final initialPositioned = tester.widget<AnimatedPositioned>(
        find.byType(AnimatedPositioned),
      );
      expect(initialPositioned.left, 0.0);

      // Tap 'Videos'
      await tester.tap(find.text('Videos'));
      await tester.pump(); // Start animation
      await tester.pump(const Duration(milliseconds: 150)); // Halfway

      // Position should be animating to the right
      final midPositioned = tester.widget<AnimatedPositioned>(
        find.byType(AnimatedPositioned),
      );
      expect(midPositioned.left, greaterThan(0.0));

      await tester.pumpAndSettle(); // Complete animation

      expect(selected, 'Videos');

      // 'Videos' text should now be crisp black
      final videosText = tester.widget<AnimatedDefaultTextStyle>(
        find.ancestor(
          of: find.text('Videos'),
          matching: find.byType(AnimatedDefaultTextStyle),
        ).first,
      );
      expect(videosText.style.color, Colors.black);
      expect(videosText.style.fontWeight, FontWeight.w700);

      // 'All' text should now be crisp grey
      final allText = tester.widget<AnimatedDefaultTextStyle>(
        find.ancestor(
          of: find.text('All'),
          matching: find.byType(AnimatedDefaultTextStyle),
        ).first,
      );
      expect(allText.style.color, const Color(0xFF9E9EA2));
    });
  });
}

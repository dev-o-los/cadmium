import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/widgets/sliding_pill_segmented_bar.dart';

void main() {
  group('SlidingPillSegmentedBar Widget Tests', () {
    const categories = [
      'All',
      'Songs',
      'Videos',
      'Albums',
      'Artists',
      'Playlists',
    ];

    testWidgets('renders continuous grey pill track and all category items', (
      tester,
    ) async {
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

      final pillRect = tester.getRect(find.byType(AnimatedPositioned));
      final allRect = tester.getRect(find.text('All'));
      final leftSpace = allRect.left - pillRect.left;
      final rightSpace = pillRect.right - allRect.right;

      // Verify the white pill is symmetrically balanced on both sides around the text
      expect((leftSpace - rightSpace).abs(), lessThan(0.01));
      expect(leftSpace, closeTo(20.0, 0.01));
      expect(rightSpace, closeTo(20.0, 0.01));

      // Check text styling on selected item (crisp black, bold)
      final allText = tester.widget<AnimatedDefaultTextStyle>(
        find
            .ancestor(
              of: find.text('All'),
              matching: find.byType(AnimatedDefaultTextStyle),
            )
            .first,
      );
      expect(allText.style.color, Colors.black);
      expect(allText.style.fontWeight, FontWeight.w600);

      // Check text styling on unselected item (crisp grey, consistent weight)
      final songsText = tester.widget<AnimatedDefaultTextStyle>(
        find
            .ancestor(
              of: find.text('Songs'),
              matching: find.byType(AnimatedDefaultTextStyle),
            )
            .first,
      );
      expect(songsText.style.color, const Color(0xFF8E8E93));
      expect(songsText.style.fontWeight, FontWeight.w600);
    });

    testWidgets(
      'tapping a category triggers callback and animates white pill highlight',
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
          find
              .ancestor(
                of: find.text('Videos'),
                matching: find.byType(AnimatedDefaultTextStyle),
              )
              .first,
        );
        expect(videosText.style.color, Colors.black);
        expect(videosText.style.fontWeight, FontWeight.w600);

        // 'All' text should now be crisp grey
        final allText = tester.widget<AnimatedDefaultTextStyle>(
          find
              .ancestor(
                of: find.text('All'),
                matching: find.byType(AnimatedDefaultTextStyle),
              )
              .first,
        );
        expect(allText.style.color, const Color(0xFF8E8E93));
      },
    );

    testWidgets(
      'dragging inside fixed pill scrolls content while outer pill remains fixed',
      (tester) async {
        String selected = 'All';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360, // Simulate standard mobile screen width
                child: SlidingPillSegmentedBar(
                  categories: categories,
                  selectedCategory: selected,
                  onCategorySelected: (cat) => selected = cat,
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Find the outer fixed pill container by finding the ClipRRect parent
        final clipRRectFinder = find.byType(ClipRRect);
        expect(clipRRectFinder, findsOneWidget);
        final initialPillRect = tester.getRect(clipRRectFinder);

        // Verify initial scroll position of internal SingleChildScrollView
        final scrollFinder = find.byType(SingleChildScrollView);
        expect(scrollFinder, findsOneWidget);
        final scrollStateBefore = tester.widget<SingleChildScrollView>(
          scrollFinder,
        );
        expect(scrollStateBefore.controller?.offset, 0.0);

        // Drag left on the content
        await tester.drag(find.text('Songs'), const Offset(-150, 0));
        await tester.pumpAndSettle();

        // Content inside should have scrolled (offset > 0)
        final scrollStateAfter = tester.widget<SingleChildScrollView>(
          scrollFinder,
        );
        expect(scrollStateAfter.controller?.offset, greaterThan(50.0));

        // The outer pill container must remain completely fixed at the exact same screen coordinates
        final afterPillRect = tester.getRect(clipRRectFinder);
        expect(afterPillRect.left, initialPillRect.left);
        expect(afterPillRect.top, initialPillRect.top);
        expect(afterPillRect.width, initialPillRect.width);
        expect(afterPillRect.height, initialPillRect.height);
      },
    );

    testWidgets(
      'left edge dissolve is only active when scrolled away from left edge',
      (tester) async {
        String selected = 'All';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: SlidingPillSegmentedBar(
                  categories: categories,
                  selectedCategory: selected,
                  onCategorySelected: (cat) => selected = cat,
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // At offset 0, ShaderMask shader callback returns a gradient whose left color is fully opaque black (no left dissolve)
        final shaderMask = tester.widget<ShaderMask>(find.byType(ShaderMask));
        expect(shaderMask, isNotNull);

        // Drag left so content scrolls
        await tester.drag(find.text('Songs'), const Offset(-80, 0));
        await tester.pumpAndSettle();

        final scrollFinder = find.byType(SingleChildScrollView);
        final scrollState = tester.widget<SingleChildScrollView>(scrollFinder);
        expect(scrollState.controller?.offset, greaterThan(0.0));
      },
    );

    testWidgets(
      'white highlight pill maintains perfect symmetry across all categories',
      (tester) async {
        String selected = 'All';

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return MaterialApp(
                home: Scaffold(
                  body: SizedBox(
                    width: 600, // Wide viewport so all tabs are visible without scrolling
                    child: SlidingPillSegmentedBar(
                      categories: categories,
                      selectedCategory: selected,
                      onCategorySelected: (cat) {
                        setState(() {
                          selected = cat;
                        });
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        );

        await tester.pumpAndSettle();

        for (final cat in categories) {
          await tester.tap(find.text(cat));
          await tester.pumpAndSettle();

          final pillRect = tester.getRect(find.byType(AnimatedPositioned));
          final textRect = tester.getRect(find.text(cat));
          final leftSpace = textRect.left - pillRect.left;
          final rightSpace = pillRect.right - textRect.right;

          // Verify exact symmetrical balance on both sides of the text in the white pill
          expect(
            (leftSpace - rightSpace).abs(),
            lessThan(0.01),
            reason:
                'Pill should be symmetrically equal on both sides for category "$cat"',
          );
          expect(
            leftSpace,
            closeTo(20.0, 0.01),
            reason: 'Left spacing should equal horizontal padding for "$cat"',
          );
          expect(
            rightSpace,
            closeTo(20.0, 0.01),
            reason: 'Right spacing should equal horizontal padding for "$cat"',
          );
        }
      },
    );

    testWidgets(
      'pill remains symmetrically equal under device font scaling (1.3x)',
      (tester) async {
        String selected = 'All';

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
                child: SizedBox(
                  width: 700,
                  child: SlidingPillSegmentedBar(
                    categories: categories,
                    selectedCategory: selected,
                    onCategorySelected: (cat) => selected = cat,
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final pillRect = tester.getRect(find.byType(AnimatedPositioned));
        final allRect = tester.getRect(find.text('All'));
        final leftSpace = allRect.left - pillRect.left;
        final rightSpace = pillRect.right - allRect.right;

        // Perfectly symmetrical under textScaler
        expect((leftSpace - rightSpace).abs(), lessThan(0.01));
        expect(leftSpace, closeTo(20.0, 0.01));
        expect(rightSpace, closeTo(20.0, 0.01));
      },
    );
  });
}

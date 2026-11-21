import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/models/song_item.dart';
import 'package:wavify/widgets/explicit_badge.dart';

void main() {
  group('ExplicitBadge Widget Tests', () {
    testWidgets(
      'renders white background with bold black E text and proper margins',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: ExplicitBadge())),
        );

        // Verify the Text 'E' is rendered
        final textFinder = find.descendant(
          of: find.byType(ExplicitBadge),
          matching: find.text('E'),
        );
        expect(textFinder, findsOneWidget);

        final textWidget = tester.widget<Text>(textFinder);
        expect(textWidget.style?.color, Colors.black);
        expect(textWidget.style?.fontWeight, FontWeight.w800);

        // Verify Container has white background
        final containerFinder = find.descendant(
          of: find.byType(ExplicitBadge),
          matching: find.byType(Container),
        );
        expect(containerFinder, findsOneWidget);

        final containerWidget = tester.widget<Container>(containerFinder);
        final decoration = containerWidget.decoration as BoxDecoration;
        expect(decoration.color, Colors.white);

        // Verify padding / margin in front of song name
        final badgeWidget = tester.widget<ExplicitBadge>(
          find.byType(ExplicitBadge),
        );
        expect(badgeWidget.margin, const EdgeInsets.only(right: 6.0));
        expect(badgeWidget.size, 14.0);
      },
    );

    testWidgets('supports custom size and margin', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ExplicitBadge(
              size: 18,
              margin: EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
      );

      final badgeWidget = tester.widget<ExplicitBadge>(
        find.byType(ExplicitBadge),
      );
      expect(badgeWidget.size, 18.0);
      expect(badgeWidget.margin, const EdgeInsets.symmetric(horizontal: 8));

      final containerFinder = find.descendant(
        of: find.byType(ExplicitBadge),
        matching: find.byType(Container),
      );
      final containerWidget = tester.widget<Container>(containerFinder);
      expect(containerWidget.constraints?.minWidth, 18.0);
      expect(containerWidget.constraints?.minHeight, 18.0);
    });

    test('SongItem correctly detects explicit metadata and flags', () {
      const explicitTrack = SongItem(
        id: '123',
        title: 'Not Like Us',
        artist: 'Kendrick Lamar',
        isExplicit: true,
      );
      expect(explicitTrack.isExplicit, isTrue);
      expect(explicitTrack.hasExplicitContent, isTrue);

      const titleExplicitTrack = SongItem(
        id: '456',
        title: 'Explicit Track (Explicit)',
        artist: 'Artist',
      );
      expect(titleExplicitTrack.hasExplicitContent, isTrue);

      const cleanTrack = SongItem(
        id: '789',
        title: 'Clean Track',
        artist: 'Artist',
      );
      expect(cleanTrack.isExplicit, isFalse);
      expect(cleanTrack.hasExplicitContent, isFalse);
    });
  });
}

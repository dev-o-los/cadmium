import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:wavify/widgets/apple_glass_bottom_sheet.dart';

void main() {
  group('Liquid Glossy Bottom Sheet Tests', () {
    testWidgets(
        'AppleGlassBottomSheetContainer renders liquid glossy panel with white grabber and white typography',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showAppleGlassBottomSheet(
                      context: context,
                      builder: (modalCtx) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Modal Title',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 14),
                            AppleSheetGroup(
                              children: [
                                AppleSheetActionTile(
                                  icon: CupertinoIcons.play,
                                  title: 'Play Next',
                                  subtitle: 'Add to top of queue',
                                  onTap: () {},
                                ),
                                const AppleSheetDivider(),
                                AppleSheetActionTile(
                                  icon: CupertinoIcons.trash,
                                  title: 'Delete / Remove',
                                  isDestructive: true,
                                  onTap: () {},
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: const Text('Open Sheet'),
                );
              },
            ),
          ),
        ),
      );

      // Open bottom sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      // Verify bottom sheet container exists
      expect(find.byType(AppleGlassBottomSheetContainer), findsOneWidget);

      // Verify uniform white text for all options (including destructive ones)
      final playText = tester.widget<Text>(find.text('Play Next'));
      expect(playText.style?.color, equals(Colors.white));

      final deleteText = tester.widget<Text>(find.text('Delete / Remove'));
      expect(deleteText.style?.color, equals(Colors.white));

      // Verify all icons are white
      final playIcon = tester.widget<Icon>(find.byIcon(CupertinoIcons.play));
      expect(playIcon.color, equals(Colors.white));

      final trashIcon = tester.widget<Icon>(find.byIcon(CupertinoIcons.trash));
      expect(trashIcon.color, equals(Colors.white));

      // Verify divider exists
      expect(find.byType(AppleSheetDivider), findsOneWidget);

      // Verify no GlassContainer is used on the bottom sheet (not liquid glassy, black effect instead)
      expect(find.byType(GlassContainer), findsNothing);
    });
  });
}


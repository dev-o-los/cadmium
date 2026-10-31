import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/main.dart';
import 'package:wavify/widgets/liquid_glass_bottom_bar.dart';

void main() {
  testWidgets('WavifyApp Liquid Glass Navigation Bar UI smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: WavifyApp(),
      ),
    );

    // Verify Liquid Glass navigation bar dock with Home, Explore, Library, and Search
    expect(find.byType(LiquidGlassBottomBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.search), findsWidgets);
    expect(find.text('Radio'), findsNothing);
  });
}

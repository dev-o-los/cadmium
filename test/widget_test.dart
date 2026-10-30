import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/main.dart';

void main() {
  testWidgets('WavifyApp Apple Music UI smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const WavifyApp());

    // Verify Apple Music navigation bar and primary Listen Now tab
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('Listen Now'), findsWidgets);
    expect(find.text('Browse'), findsOneWidget);
    expect(find.text('Radio'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
  });
}

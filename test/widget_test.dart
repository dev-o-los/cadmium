import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/main.dart';

void main() {
  testWidgets('WavifyApp 4-Tab Apple Music UI smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const WavifyApp());

    // Verify 4-tab Apple Music navigation bar: Home, Explore, Library, Search
    expect(find.byType(BottomNavigationBar), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Radio'), findsNothing);
  });
}

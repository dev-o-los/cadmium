import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/main.dart';

void main() {
  testWidgets('WavifyApp initial UI smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const WavifyApp());

    // Verify app title and search bar
    expect(find.text('Wavify'), findsOneWidget);
    expect(find.byType(SearchBar), findsOneWidget);
  });
}

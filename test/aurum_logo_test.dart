import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wavify/widgets/wavify_logo.dart';

void main() {
  testWidgets('CadmiumLogo renders without errors', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CadmiumLogo(size: 56),
        ),
      ),
    );
    expect(find.byType(CadmiumLogo), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}

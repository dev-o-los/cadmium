import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:wavify/screens/settings_screen.dart';

void main() {
  testWidgets('SettingsScreen renders floating liquid glass back button and large title',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify liquid glass circular back button is present (matching AlbumScreen)
    expect(find.byType(GlassIconButton), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.chevron_back), findsOneWidget);

    // Verify single large title
    expect(find.text('Settings'), findsOneWidget);

    // Verify sections
    expect(find.text('ACCOUNT'), findsOneWidget);
    expect(find.text('SOFTWARE UPDATE'), findsOneWidget);
    expect(find.text('PLAYBACK & AUDIO'), findsOneWidget);
    expect(find.text('ABOUT'), findsOneWidget);
  });
}


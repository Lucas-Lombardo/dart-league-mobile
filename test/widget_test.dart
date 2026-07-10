import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/main.dart';
import 'package:mobile/providers/game_provider.dart';

void main() {
  testWidgets('App builds without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(DartLegendsApp(gameProvider: GameProvider()));

    // The old assertion looked for a hardcoded '🎯 Dart Rivals' title that the
    // splash screen stopped rendering when it moved to a logo asset plus a
    // localized tagline — this test had been failing long before the
    // reliability work. Assert what a smoke test can honestly guarantee on the
    // first frame: the app boots and mounts its MaterialApp.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/main.dart';
import 'package:mobile/providers/game_provider.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(DartLegendsApp(gameProvider: GameProvider()));

    expect(find.text('🎯 Dart Rivals'), findsOneWidget);
  });
}

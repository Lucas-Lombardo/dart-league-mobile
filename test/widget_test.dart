import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/main.dart';

void main() {
  testWidgets('Home screen displays Dart Legends', (WidgetTester tester) async {
    await tester.pumpWidget(const DartLegendsApp());

    expect(find.text('🎯 Dart Legends'), findsOneWidget);
  });
}

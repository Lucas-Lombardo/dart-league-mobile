import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/utils/game_system_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.dartrivals/system_bars');
  final hiddenCalls = <bool>[];

  setUp(() {
    hiddenCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          hiddenCalls.add((call.arguments as Map)['hidden'] as bool);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  group('GameSystemUi', () {
    test('a game → game handoff keeps the bars hidden until the last game '
        'leaves', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      GameSystemUi.enter(); // game A
      GameSystemUi.enter(); // game B, pushed before A's deferred dispose
      GameSystemUi.exit(); // A disposes
      await pumpEventQueue();
      expect(hiddenCalls, [true]);

      GameSystemUi.exit(); // B leaves for the home screen
      await pumpEventQueue();
      expect(hiddenCalls, [true, false]);
    });

    test('iOS is left alone', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      GameSystemUi.enter();
      GameSystemUi.exit();
      await pumpEventQueue();
      expect(hiddenCalls, isEmpty);
    });
  });

  group('gameSideGutters', () {
    Future<({double left, double right})> guttersFor(
      WidgetTester tester,
      EdgeInsets padding,
    ) async {
      late ({double left, double right}) gutters;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(padding: padding),
          child: Builder(
            builder: (context) {
              gutters = gameSideGutters(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return gutters;
    }

    testWidgets('12 on a bare edge', (tester) async {
      expect(await guttersFor(tester, EdgeInsets.zero), (left: 12.0, right: 12.0));
      // Rounded-corner waterfall insets are thinner than the margin.
      expect(
        await guttersFor(tester, const EdgeInsets.only(left: 4, right: 4)),
        (left: 12.0, right: 12.0),
      );
    });

    testWidgets('the inset when larger: punch hole, navigation bar', (
      tester,
    ) async {
      expect(
        await guttersFor(tester, const EdgeInsets.only(left: 26, right: 48)),
        (left: 26.0, right: 48.0),
      );
    });
  });
}

// Renders the two camera-free quizzes ("Compte rapide", "Vision checkout")
// and the per-double progression screen (system D) to PNG so they can be
// reviewed without a device. Not a test of behaviour — skipped unless run
// explicitly:
//
//   flutter test test/preview/training_quiz_preview_test.dart \
//     --dart-define=PREVIEW=true \
//     --dart-define=PREVIEW_OUT=/abs/dir
//
// Manrope is loaded from assets/fonts (the bundled family), Material Icons
// from the Flutter SDK cache. The progression screen calls the API on init,
// so it is pumped inside a mocked http client.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/screens/training/checkout_vision_screen.dart';
import 'package:mobile/screens/training/important_doubles_progress_screen.dart';
import 'package:mobile/screens/training/quick_count_screen.dart';
import 'package:mobile/utils/app_theme.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outDir = String.fromEnvironment('PREVIEW_OUT');

Future<void> _loadFonts() async {
  final fonts = Directory('${Directory.current.path}/assets/fonts');
  if (fonts.existsSync()) {
    final loader = FontLoader(AppTheme.fontFamily);
    final files = fonts
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ttf'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final bytes = await f.readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.path;
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons');
    final bytes = await icons.readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
}

/// Pumps [screen], lets [after] drive it to the state we want to look at,
/// then writes the PNG.
Future<void> _shot(
  WidgetTester tester,
  Widget screen,
  String name, {
  Future<void> Function(WidgetTester tester)? after,
}) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(const Size(393, 852));
  tester.view.devicePixelRatio = 3;
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,
      locale: const Locale('fr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepaintBoundary(key: key, child: screen),
    ),
  );
  // Localizations resolve asynchronously.
  await tester.runAsync(() async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
  await tester.pump();
  if (after != null) await after(tester);

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('wrote ${file.path}');
  });
  // audioplayers has no implementation in a widget test — the quiz plays a
  // sound on every dart, and that MissingPluginException is not a layout
  // problem.
  final error = tester.takeException();
  expect(error == null || error is MissingPluginException, isTrue,
      reason: '$name: $error');
}

/// Three Important Doubles sessions, two doubles each, so the list shows the
/// best / worst tinting, a delta and a sparkline.
String _sessionsJson() {
  final now = DateTime.now();
  Map<String, dynamic> session(int i, int d16, int d20) => {
    'id': 's$i',
    'type': 'important_doubles',
    'score': d16 + d20,
    'dartsThrown': 120,
    'completed': true,
    'details': {
      'doubles': [
        {'target': 16, 'hits': d16, 'darts': 60},
        {'target': 20, 'hits': d20, 'darts': 60},
      ],
    },
    'completedAt': now.subtract(Duration(days: i)).toIso8601String(),
    'createdAt': now.subtract(Duration(days: i)).toIso8601String(),
  };
  return jsonEncode({
    'sessions': [session(1, 22, 9), session(6, 18, 11), session(14, 14, 13)],
  });
}

void main() {
  testWidgets('training quiz previews', (tester) async {
    await tester.runAsync(_loadFonts);
    // The API layer reads the auth token from secure storage.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => null,
    );

    // 1. Compte rapide, the visit landing on the board.
    await _shot(
      tester,
      const QuickCountScreen(),
      'quick_count_landing',
      after: (t) async {
        for (var i = 0; i < 3; i++) {
          await t.pump(const Duration(seconds: 2));
        }
      },
    );

    // 2. Compte rapide, the clock running and an answer half typed.
    await _shot(
      tester,
      const QuickCountScreen(),
      'quick_count_answer',
      after: (t) async {
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(seconds: 2));
        }
        // A few seconds off the clock so the timer bar is not full.
        await t.pump(const Duration(seconds: 6));
      },
    );

    // 3. Vision checkout, composing a finish.
    await _shot(tester, const CheckoutVisionScreen(), 'checkout_vision');

    // 3b. Vision checkout, the verdict (three misses always resolve).
    await _shot(
      tester,
      const CheckoutVisionScreen(),
      'checkout_vision_result',
      after: (t) async {
        for (var i = 0; i < 3; i++) {
          final miss = find.text('Manqué');
          if (miss.evaluate().isEmpty) break;
          await t.tap(miss);
          await t.pump();
        }
        await t.pump(const Duration(milliseconds: 300));
      },
    );

    // 4. Progression par double, with three sessions on two doubles.
    await http.runWithClient(
      () async {
        await _shot(
          tester,
          const ImportantDoublesProgressScreen(),
          'doubles_progress',
          after: (t) async {
            await t.runAsync(() async {
              await Future<void>.delayed(const Duration(milliseconds: 50));
            });
            await t.pump();
          },
        );
      },
      () => MockClient(
        (request) async =>
            http.Response(_sessionsJson(), 200, headers: const {
              'content-type': 'application/json; charset=utf-8',
            }),
      ),
    );
  }, skip: !_enabled);
}

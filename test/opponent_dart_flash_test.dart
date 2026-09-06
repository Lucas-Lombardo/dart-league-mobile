import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/opponent_dart_zoom.dart';
import 'package:mobile/widgets/board_safe_video.dart';
import 'package:mobile/widgets/game_turn_ui.dart';

/// The opponent-turn dart flash drives the video zoom: 2.2× on the point the
/// thrower sent, one second, back to 1 — and never a jump when darts chain.
void main() {
  late VideoZoomController controller;

  setUp(() => controller = VideoZoomController());
  tearDown(() => controller.dispose());

  // pumpWidget alone leaves an EMPTY tree under MaterialApp (the l10n
  // delegates load asynchronously); the extra pump builds the flash, so the
  // next pumpWidget reaches it through didUpdateWidget, like a real rebuild.
  Future<void> pump(
    WidgetTester tester, {
    required List<String> throws,
    OpponentDartZoom? zoom,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 366,
            height: 423,
            child: Stack(
              fit: StackFit.expand,
              children: [
                OpponentDartFlash(
                  throws: throws,
                  zoom: zoom,
                  controller: controller,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  OpponentDartZoom dart(int seq, {double x = 0.3, double y = 0.7, bool manual = false}) =>
      OpponentDartZoom(
        x: x,
        y: y,
        manual: manual,
        notation: 'T19',
        dartIndex: seq,
        seq: seq,
      );

  testWidgets('zooms 2.2× on the sent point, holds, and comes back', (tester) async {
    await pump(tester, throws: const []);
    expect(controller.value.isIdle, isTrue);

    await pump(tester, throws: const ['T19'], zoom: dart(1));
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.value.scale, closeTo(2.2, 0.01));
    expect(controller.value.focusX, closeTo(0.3, 1e-6));
    expect(controller.value.focusY, closeTo(0.7, 1e-6));
    expect(find.text('T19'), findsOneWidget);
    expect(find.text('+57 pts'), findsOneWidget);
    expect(find.text('FLÉCHETTE 1 / 3'), findsOneWidget);
    expect(find.text('MANUEL'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1300));
    expect(controller.value.scale, closeTo(2.2, 0.01));

    await tester.pump(const Duration(milliseconds: 700));
    expect(controller.value.isIdle, isTrue);
  });

  testWidgets('a typed score shows the MANUEL tag', (tester) async {
    await pump(tester, throws: const []);
    await pump(tester, throws: const ['T19'], zoom: dart(1, manual: true));
    await tester.pump(const Duration(milliseconds: 350));
    expect(controller.value.manual, isTrue);
    expect(find.text('MANUEL'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2000));
  });

  testWidgets('a second dart mid-zoom restarts from the current scale, no jump', (tester) async {
    await pump(tester, throws: const []);
    await pump(tester, throws: const ['T19'], zoom: dart(1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.value.scale, closeTo(2.2, 0.01));

    final seen = <double>[];
    controller.addListener(() => seen.add(controller.value.scale));
    await pump(tester, throws: const ['T19', 'T19'], zoom: dart(2, x: 0.8, y: 0.2));
    await tester.pump(const Duration(milliseconds: 100));
    // Every scale the video was asked to paint stayed at 2.2, never 1, and
    // the focus glides towards the new dart instead of jumping.
    expect(seen.every((s) => s > 2.1), isTrue, reason: 'scales seen: $seen');
    expect(controller.value.focusX, greaterThan(0.3));
    expect(controller.value.focusX, lessThan(0.8));
    await tester.pump(const Duration(milliseconds: 250));
    expect(controller.value.scale, closeTo(2.2, 0.01));
    expect(controller.value.focusX, closeTo(0.8, 1e-6));
    expect(controller.value.focusY, closeTo(0.2, 1e-6));
    await tester.pump(const Duration(milliseconds: 2300));
    expect(controller.value.isIdle, isTrue);
  });

  testWidgets('a dart without a point mid-zoom eases the video back to 1', (tester) async {
    await pump(tester, throws: const []);
    await pump(tester, throws: const ['T19'], zoom: dart(1));
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.value.scale, closeTo(2.2, 0.01));

    // Older sender for this dart: the list grows, no zoom point comes.
    await pump(tester, throws: const ['T19', 'S5'], zoom: dart(1));
    await tester.pump(const Duration(milliseconds: 175));
    expect(controller.value.scale, lessThan(2.2));
    expect(controller.value.scale, greaterThan(1.0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.value.scale, closeTo(1.0, 0.01));
    expect(find.text('S5'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2000));
  });

  testWidgets('without any point the label shows and the video is untouched', (tester) async {
    await pump(tester, throws: const []);
    await pump(tester, throws: const ['D16']);
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.value.isIdle, isTrue);
    expect(find.text('D16'), findsOneWidget);
    expect(find.text('+32 pts'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2000));
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/widgets/board_safe_video.dart';

/// The rule that bit on the first device build: a square feed must be laid
/// out at EXACTLY its fitted size inside the panel — never stretched to the
/// panel's tight constraints and then cropped by the child's `cover` fit.
void main() {
  Future<Size> pumpAndMeasure(
    WidgetTester tester, {
    required Size panel,
    required double sourceWidth,
    required double sourceHeight,
    double topInset = 0,
    VideoZoomController? zoom,
  }) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: panel.width,
            height: panel.height,
            child: BoardSafeVideo(
              sourceWidth: sourceWidth,
              sourceHeight: sourceHeight,
              topInset: topInset,
              zoom: zoom,
              child: Container(key: key, color: const Color(0xFF00FF00)),
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byKey(key));
  }

  testWidgets('a square feed in a portrait panel is a square, not a stretch', (tester) async {
    final size = await pumpAndMeasure(
      tester,
      panel: const Size(366, 423),
      sourceWidth: 640,
      sourceHeight: 640,
    );
    expect(size, const Size(366, 366));
  });

  testWidgets('a square feed in a landscape panel is the same square', (tester) async {
    final size = await pumpAndMeasure(
      tester,
      panel: const Size(406, 361),
      sourceWidth: 640,
      sourceHeight: 640,
    );
    expect(size, const Size(361, 361));
  });

  testWidgets('the badge inset pushes the square down, whole', (tester) async {
    final controller = VideoZoomController();
    addTearDown(controller.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 366,
            height: 423,
            child: BoardSafeVideo(
              sourceWidth: 640,
              sourceHeight: 640,
              topInset: 52,
              zoom: controller,
              child: Container(key: key),
            ),
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byKey(key));
    final panel = tester.getRect(find.byType(BoardSafeVideo));
    expect(box.width, 366);
    expect(box.height, 366);
    expect(box.top - panel.top, closeTo(52 + 2.5, 1e-6));
  });

  testWidgets('a full portrait feed keeps the old centred-square rule', (tester) async {
    final size = await pumpAndMeasure(
      tester,
      panel: const Size(366, 423),
      sourceWidth: 720,
      sourceHeight: 1280,
    );
    expect(size.width, 366);
    expect(size.height, closeTo(650.67, 0.01));
  });
}

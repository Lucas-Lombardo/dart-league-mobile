import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/widgets/board_safe_video.dart';

/// Panel-space edges of the video box once [videoZoomTranslation] is applied.
({double left, double right, double top, double bottom}) edges({
  required double scale,
  required double focusX,
  required double focusY,
  required double sourceWidth,
  required double sourceHeight,
  required double panelWidth,
  required double panelHeight,
  double topInset = 0,
}) {
  final box = boardSafeVideoBox(
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    panelWidth: panelWidth,
    panelHeight: panelHeight,
    topInset: topInset,
  );
  final t = videoZoomTranslation(
    scale: scale,
    focusX: focusX,
    focusY: focusY,
    boxWidth: box.width,
    boxHeight: box.height,
    panelWidth: panelWidth,
    panelHeight: panelHeight,
    boxLeft: box.left,
    boxTop: box.top,
  );
  return (
    left: box.left + t.dx,
    right: box.left + t.dx + box.width * scale,
    top: box.top + t.dy,
    bottom: box.top + t.dy + box.height * scale,
  );
}

void main() {
  group('boardSafeVideoBox', () {
    test('shows a square feed whole, at the short side, centred', () {
      final b = boardSafeVideoBox(
        sourceWidth: 640,
        sourceHeight: 640,
        panelWidth: 366,
        panelHeight: 423,
      );
      expect(b.width, 366);
      expect(b.height, 366);
      expect(b.left, 0);
      expect(b.top, closeTo(28.5, 1e-9));
    });

    test('keeps the same square in a landscape panel', () {
      final b = boardSafeVideoBox(
        sourceWidth: 640,
        sourceHeight: 640,
        panelWidth: 406,
        panelHeight: 361,
      );
      expect(b.width, 361);
      expect(b.height, 361);
      expect(b.left, closeTo(22.5, 1e-9));
      expect(b.top, 0);
    });

    test('fits below the badge row when asked', () {
      final portrait = boardSafeVideoBox(
        sourceWidth: 640,
        sourceHeight: 640,
        panelWidth: 366,
        panelHeight: 423,
        topInset: 52,
      );
      expect(portrait.width, 366);
      expect(portrait.top, closeTo(52 + (371 - 366) / 2, 1e-9));
      final landscape = boardSafeVideoBox(
        sourceWidth: 640,
        sourceHeight: 640,
        panelWidth: 406,
        panelHeight: 361,
        topInset: 52,
      );
      expect(landscape.height, 309);
      expect(landscape.top, 52);
      expect(landscape.left, closeTo((406 - 309) / 2, 1e-9));
    });

    test('is the old centred-square rule for a full portrait feed', () {
      final b = boardSafeVideoBox(
        sourceWidth: 720,
        sourceHeight: 1280,
        panelWidth: 366,
        panelHeight: 423,
      );
      expect(b.width, 366);
      expect(b.height, closeTo(650.67, 0.01));
      expect(b.top, closeTo((423 - 650.67) / 2, 0.01));
    });
  });

  group('videoZoomTranslation', () {
    test('is the identity at scale 1, inset or not', () {
      for (final inset in [0.0, 52.0]) {
        final e = edges(
          scale: 1,
          focusX: 0.3,
          focusY: 0.8,
          sourceWidth: 640,
          sourceHeight: 640,
          panelWidth: 366,
          panelHeight: 423,
          topInset: inset,
        );
        final b = boardSafeVideoBox(
          sourceWidth: 640,
          sourceHeight: 640,
          panelWidth: 366,
          panelHeight: 423,
          topInset: inset,
        );
        expect(e.left, closeTo(b.left, 1e-9));
        expect(e.top, closeTo(b.top, 1e-9));
      }
    });

    test('keeps a central focus still once the panel is covered', () {
      final box = boardSafeVideoBox(
        sourceWidth: 640,
        sourceHeight: 640,
        panelWidth: 366,
        panelHeight: 423,
      );
      final t = videoZoomTranslation(
        scale: 2.2,
        focusX: 0.5,
        focusY: 0.5,
        boxWidth: box.width,
        boxHeight: box.height,
        panelWidth: 366,
        panelHeight: 423,
        boxLeft: box.left,
        boxTop: box.top,
      );
      // Focus F = (183, 183) in box px maps to F·s + t → must equal F.
      expect(183 * 2.2 + t.dx, closeTo(183, 1e-6));
      expect(183 * 2.2 + t.dy, closeTo(183, 1e-6));
    });

    test('never shows a black band for a dart in the double ring', () {
      for (final inset in [0.0, 52.0]) {
        final e = edges(
          scale: 2.2,
          focusX: 0.93,
          focusY: 0.06,
          sourceWidth: 640,
          sourceHeight: 640,
          panelWidth: 366,
          panelHeight: 423,
          topInset: inset,
        );
        expect(e.left, lessThanOrEqualTo(0));
        expect(e.right, greaterThanOrEqualTo(366));
        expect(e.top, lessThanOrEqualTo(0));
        expect(e.bottom, greaterThanOrEqualTo(423));
      }
    });

    test('covers a landscape panel with a square feed', () {
      final e = edges(
        scale: 2.2,
        focusX: 0.05,
        focusY: 0.95,
        sourceWidth: 640,
        sourceHeight: 640,
        panelWidth: 406,
        panelHeight: 361,
        topInset: 52,
      );
      expect(e.left, lessThanOrEqualTo(0));
      expect(e.right, greaterThanOrEqualTo(406));
      expect(e.top, lessThanOrEqualTo(0));
      expect(e.bottom, greaterThanOrEqualTo(361));
    });

    test('glides to the centre without a jump while the box is still small', () {
      // Square feed in a tall panel: the scaled box only covers the panel
      // from scale 423/366. Just below and just above that point the
      // translation must agree.
      final box = boardSafeVideoBox(
        sourceWidth: 640,
        sourceHeight: 640,
        panelWidth: 366,
        panelHeight: 423,
      );
      double dyAt(double s) => videoZoomTranslation(
            scale: s,
            focusX: 0.5,
            focusY: 0.9,
            boxWidth: box.width,
            boxHeight: box.height,
            panelWidth: 366,
            panelHeight: 423,
            boxLeft: box.left,
            boxTop: box.top,
          ).dy;
      final s0 = 423 / 366;
      expect(dyAt(s0 - 1e-4), closeTo(dyAt(s0 + 1e-4), 0.2));
      // And on the way there the box never goes back up.
      var last = dyAt(1);
      for (var s = 1.0; s <= s0; s += 0.01) {
        final d = dyAt(s);
        expect(d, lessThanOrEqualTo(last + 1e-9));
        last = d;
      }
    });

    test('works for a full-frame portrait feed from an older sender', () {
      final e = edges(
        scale: 2.2,
        focusX: 0.5,
        focusY: 0.2,
        sourceWidth: 720,
        sourceHeight: 1280,
        panelWidth: 366,
        panelHeight: 423,
        topInset: 52,
      );
      expect(e.left, lessThanOrEqualTo(0));
      expect(e.right, greaterThanOrEqualTo(366));
      expect(e.top, lessThanOrEqualTo(0));
      expect(e.bottom, greaterThanOrEqualTo(423));
    });
  });
}

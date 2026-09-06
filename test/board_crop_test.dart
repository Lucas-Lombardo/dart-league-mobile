import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/services/board_crop.dart';
import 'package:mobile/services/board_framing.dart';
import 'package:mobile/services/dart_scoring_service.dart';

/// Rotates a raw image (rows of pixels) clockwise by [degrees] — the
/// reference model of what the AI does before analysis and what WebRTC does
/// with the frame's rotation metadata. The crop mapping must agree with it.
List<List<T>> rotateCw<T>(List<List<T>> img, int degrees) {
  var out = img;
  for (var k = 0; k < ((degrees % 360) ~/ 90); k++) {
    final h = out.length, w = out[0].length;
    // 90° CW: new[x][h-1-y] = old[y][x]  → new has w rows of h columns
    out = List.generate(w, (ny) => List.generate(h, (nx) => out[h - 1 - nx][ny]));
  }
  return out;
}

BoardFraming framingAt({
  required double cx,
  required double cy,
  required double extentX,
  required double extentY,
}) =>
    BoardFraming(
      spread: extentX > extentY ? extentX : extentY,
      centerX: cx,
      centerY: cy,
      fullyVisible: true,
      extentX: extentX,
      extentY: extentY,
    );

void main() {
  group('BoardCropPlanner.planFor', () {
    test('sizes the square on the board pixel diameter, not on a normalized extent', () {
      // Portrait 720×1280: a 540 px board is 0.75 of the width but 0.42 of the height.
      final plan = BoardCropPlanner.planFor(
        framingAt(cx: 0.5, cy: 0.35, extentX: 0.75, extentY: 540 / 1280),
        imageWidth: 720,
        imageHeight: 1280,
        rotation: 0,
      )!;
      expect(plan.sideOverHeight * 1280, closeTo(540 * kBoardCropMargin, 0.5));
      expect(plan.aspect, closeTo(720 / 1280, 1e-9));
    });

    test('refuses a degenerate measurement', () {
      expect(
        BoardCropPlanner.planFor(
          framingAt(cx: 0.5, cy: 0.5, extentX: 0, extentY: 0),
          imageWidth: 720,
          imageHeight: 1280,
          rotation: 0,
        ),
        isNull,
      );
    });
  });

  group('BoardCropPlanner.uprightRect', () {
    final plan = BoardCropPlanner.planFor(
      framingAt(cx: 0.5, cy: 0.35, extentX: 0.75, extentY: 540 / 1280),
      imageWidth: 720,
      imageHeight: 1280,
      rotation: 0,
    )!;

    test('centres the square on the board with even coordinates', () {
      final r = BoardCropPlanner.uprightRect(plan, 720, 1280)!;
      expect(r.width, r.height);
      expect(r.width, closeTo(540 * kBoardCropMargin, 2));
      expect(r.width.isEven, isTrue);
      expect(r.x.isEven, isTrue);
      expect(r.y.isEven, isTrue);
      expect(r.x + r.width / 2, closeTo(360, 2));
      expect(r.y + r.height / 2, closeTo(0.35 * 1280, 2));
    });

    test('clamps into the frame instead of leaving a black band', () {
      final nearTop = BoardCropPlanner.planFor(
        framingAt(cx: 0.5, cy: 0.12, extentX: 0.75, extentY: 540 / 1280),
        imageWidth: 720,
        imageHeight: 1280,
        rotation: 0,
      )!;
      final r = BoardCropPlanner.uprightRect(nearTop, 720, 1280)!;
      expect(r.y, 0);
      expect(r.x + r.width, lessThanOrEqualTo(720));
    });

    test('never exceeds the short side', () {
      final huge = BoardCropPlanner.planFor(
        framingAt(cx: 0.5, cy: 0.5, extentX: 0.95, extentY: 0.95 * 720 / 1280),
        imageWidth: 720,
        imageHeight: 1280,
        rotation: 0,
      )!;
      final r = BoardCropPlanner.uprightRect(huge, 720, 1280)!;
      expect(r.width, 720);
      expect(r.x, 0);
    });

    test('refuses a frame of another aspect (camera switched)', () {
      expect(BoardCropPlanner.uprightRect(plan, 1280, 720), isNull);
      expect(BoardCropPlanner.uprightRect(plan, 1080, 1920), isNotNull);
    });
  });

  group('BoardCropPlanner.toRaw', () {
    // A raw 6×4 image of unique cells, rotated by the reference model: the
    // rect mapped into raw space must cover exactly the cells the upright
    // rect covers.
    const rawW = 6, rawH = 4;
    final raw = List.generate(rawH, (y) => List.generate(rawW, (x) => y * 100 + x));

    Set<int> cellsOf(List<List<int>> img, PixelRect r) {
      final out = <int>{};
      for (var y = r.y; y < r.y + r.height; y++) {
        for (var x = r.x; x < r.x + r.width; x++) {
          out.add(img[y][x]);
        }
      }
      return out;
    }

    for (final rotation in [0, 90, 180, 270]) {
      test('agrees with a clockwise $rotation° rotation', () {
        final upright = rotateCw(raw, rotation);
        final uprightH = upright.length, uprightW = upright[0].length;
        // A 2×2 rect near the top-left of the UPRIGHT frame.
        const r = PixelRect(1, 0, 2, 2);
        final mapped = BoardCropPlanner.toRaw(r, uprightW, uprightH, rotation);
        expect(mapped.x, greaterThanOrEqualTo(0));
        expect(mapped.y, greaterThanOrEqualTo(0));
        expect(mapped.x + mapped.width, lessThanOrEqualTo(rawW));
        expect(mapped.y + mapped.height, lessThanOrEqualTo(rawH));
        expect(cellsOf(raw, mapped), equals(cellsOf(upright, r)));
      });
    }
  });

  group('BoardCropPlanner.differsBeyond', () {
    final a = BoardCropPlanner.planFor(
      framingAt(cx: 0.5, cy: 0.35, extentX: 0.75, extentY: 540 / 1280),
      imageWidth: 720,
      imageHeight: 1280,
      rotation: 0,
    )!;

    test('ignores a one-pixel wobble', () {
      final b = BoardCropPlanner.planFor(
        framingAt(cx: 0.5 + 1 / 720, cy: 0.35 + 1 / 1280, extentX: 0.75, extentY: 540 / 1280),
        imageWidth: 720,
        imageHeight: 1280,
        rotation: 0,
      )!;
      expect(BoardCropPlanner.differsBeyond(a, b, kBoardCropHysteresis), isFalse);
    });

    test('notices a real move', () {
      final b = BoardCropPlanner.planFor(
        framingAt(cx: 0.5, cy: 0.42, extentX: 0.75, extentY: 540 / 1280),
        imageWidth: 720,
        imageHeight: 1280,
        rotation: 0,
      )!;
      expect(BoardCropPlanner.differsBeyond(a, b, kBoardCropHysteresis), isTrue);
    });
  });

  group('OpponentVideoFraming turn rules', () {
    final f1 = framingAt(cx: 0.5, cy: 0.35, extentX: 0.75, extentY: 540 / 1280);
    final f2 = framingAt(cx: 0.5, cy: 0.55, extentX: 0.75, extentY: 540 / 1280);

    setUp(OpponentVideoFraming.reset);
    tearDown(OpponentVideoFraming.reset);

    void report(BoardFraming f) => OpponentVideoFraming.reportFraming(
          f,
          imageWidth: 720,
          imageHeight: 1280,
          rotation: 0,
        );

    test('measures during my turn until the first dart, then holds', () {
      OpponentVideoFraming.setMyTurn(true);
      report(f1);
      expect(OpponentVideoFraming.plan!.centerY, closeTo(0.35, 1e-9));
      OpponentVideoFraming.freeze();
      report(f2);
      expect(OpponentVideoFraming.plan!.centerY, closeTo(0.35, 1e-9));
    });

    test('ignores measurements outside my turn', () {
      report(f1);
      expect(OpponentVideoFraming.plan, isNull);
      OpponentVideoFraming.setMyTurn(false);
      report(f1);
      expect(OpponentVideoFraming.plan, isNull);
    });

    test('re-measures at my next turn, with hysteresis', () {
      OpponentVideoFraming.setMyTurn(true);
      report(f1);
      OpponentVideoFraming.freeze();
      OpponentVideoFraming.setMyTurn(false);
      OpponentVideoFraming.setMyTurn(true);
      report(framingAt(cx: 0.501, cy: 0.351, extentX: 0.75, extentY: 540 / 1280));
      expect(OpponentVideoFraming.plan!.centerY, closeTo(0.35, 1e-9));
      report(f2);
      expect(OpponentVideoFraming.plan!.centerY, closeTo(0.55, 1e-9));
    });
  });

  group('OpponentVideoFraming zoom points', () {
    setUp(OpponentVideoFraming.reset);
    tearDown(OpponentVideoFraming.reset);

    test('re-expresses an upright point inside the applied crop', () {
      OpponentVideoFraming.noteApplied(const PixelRect(90, 178, 540, 540), 720, 1280);
      final p = OpponentVideoFraming.videoPointForUpright(360 / 720, 448 / 1280)!;
      expect(p.x, closeTo(0.5, 1e-9));
      expect(p.y, closeTo(0.5, 1e-9));
      // Outside the square the opponent sees: no point at all.
      expect(OpponentVideoFraming.videoPointForUpright(0.01, 0.01), isNull);
    });

    test('follows the current plan rather than the last push', () {
      // Last push: whole frame. Since then a plan landed for that frame:
      // the next pushes will crop, so the dart must be placed in the crop.
      OpponentVideoFraming.setMyTurn(true);
      OpponentVideoFraming.noteApplied(null, 720, 1280);
      OpponentVideoFraming.reportFraming(
        framingAt(cx: 0.5, cy: 0.35, extentX: 0.75, extentY: 540 / 1280),
        imageWidth: 720,
        imageHeight: 1280,
        rotation: 0,
      );
      final rect = BoardCropPlanner.uprightRect(OpponentVideoFraming.plan!, 720, 1280)!;
      final p = OpponentVideoFraming.videoPointForUpright(0.5, 0.35)!;
      expect(p.x, closeTo((360 - rect.x) / rect.width, 1e-9));
      expect(p.y, closeTo((0.35 * 1280 - rect.y) / rect.height, 1e-9));
      // The plan was measured upright (0); a push rotated 90 cannot use it.
      OpponentVideoFraming.noteApplied(null, 1280, 720, rotation: 90);
      final q = OpponentVideoFraming.videoPointForUpright(0.3, 0.7)!;
      expect(q.x, closeTo(0.3, 1e-9));
      expect(q.y, closeTo(0.7, 1e-9));
    });

    test('refuses a homography measured on another rotation', () {
      const c = 170.0;
      final d = 170.0 * math.sin(math.pi / 4);
      List<double> pt(double bx, double by, int flag) => [bx / 340, by / 340, flag.toDouble()];
      final scorer = DartScoringService([
        pt(c + d, c - d, 1),
        pt(c + d, c + d, 4),
        pt(c - d, c + d, 5),
        pt(c - d, c - d, 8),
      ]);
      OpponentVideoFraming.noteScorer(scorer, rotation: 90);
      OpponentVideoFraming.noteApplied(null, 1000, 1000, rotation: 0);
      expect(OpponentVideoFraming.videoPointForBoardNorm(1, 1), isNull);
      OpponentVideoFraming.noteApplied(null, 1000, 1000, rotation: 90);
      expect(OpponentVideoFraming.videoPointForBoardNorm(1, 1), isNotNull);
    });

    test('passes the point through when the whole frame is streamed', () {
      OpponentVideoFraming.noteApplied(null, 720, 1280);
      final p = OpponentVideoFraming.videoPointForUpright(0.3, 0.7)!;
      expect(p.x, closeTo(0.3, 1e-9));
      expect(p.y, closeTo(0.7, 1e-9));
    });

    test('points a typed score at its bed through the last homography', () {
      // Calibration points placed exactly where the scorer's reference
      // points sit (flags 1/4/5/8 = the 45° diagonals of the 340-unit board
      // square), scaled by 1/340: the homography is then a pure scale, so
      // image = board / 340 and the expectations below are exact.
      const c = 170.0;
      final d = 170.0 * math.sin(math.pi / 4);
      List<double> pt(double bx, double by, int flag) => [bx / 340, by / 340, flag.toDouble()];
      final scorer = DartScoringService([
        pt(c + d, c - d, 1),
        pt(c + d, c + d, 4),
        pt(c - d, c + d, 5),
        pt(c - d, c - d, 8),
      ]);
      OpponentVideoFraming.noteScorer(scorer);
      OpponentVideoFraming.noteApplied(null, 1000, 1000);
      final bull = OpponentVideoFraming.videoPointForNotation(
        baseScore: 25,
        isDouble: true,
        isTriple: false,
      )!;
      expect(bull.x, closeTo(0.5, 1e-6));
      expect(bull.y, closeTo(0.5, 1e-6));
      final t20 = OpponentVideoFraming.videoPointForNotation(
        baseScore: 20,
        isDouble: false,
        isTriple: true,
      )!;
      // 20 is straight up: same x as the bull, on the triple ring above it
      // (radius 0.599 of the 170-unit board edge → 0.5 − 0.599 / 2 in the
      // unit image).
      expect(t20.x, closeTo(0.5, 1e-6));
      expect(t20.y, closeTo(0.5 - 0.59941 / 2, 1e-4));
      expect(
        OpponentVideoFraming.videoPointForNotation(
          baseScore: 0,
          isDouble: false,
          isTriple: false,
        ),
        isNull,
      );
    });
  });
}

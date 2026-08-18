import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/dart_detection_types.dart';
import 'package:mobile/services/detection_parsing.dart';
import 'package:mobile/services/model_selector.dart';

// Builds a [1, rows, 6] output buffer from rows of [x1,y1,x2,y2,conf,cls],
// padding to [rows] with near-zero filler like the real head does.
Float32List e2eBuffer(List<List<double>> rows, {int totalRows = 300}) {
  final floats = Float32List(totalRows * kEndToEndRowLen);
  for (int i = 0; i < rows.length; i++) {
    floats.setAll(i * kEndToEndRowLen, rows[i]);
  }
  // Padding rows keep conf = 0.0 (Float32List default) — like the model.
  return floats;
}

Detection cp(int classId, double x, double y, {double conf = 0.9}) => Detection(
      classId: classId,
      className: kDetectionLabels[classId],
      x: x,
      y: y,
      width: 0.05,
      height: 0.05,
      confidence: conf,
    );

void main() {
  const v10 = DetectionLayout.e2eDartFirst;
  const light = DetectionLayout.anchorDartLast;

  group('deriveOutputShape', () {
    test('recognizes the e2e head from its float count', () {
      expect(deriveOutputShape(300 * 6), [1, 300, 6]);
      expect(isEndToEndShape(deriveOutputShape(300 * 6)), isTrue);
    });

    test('recognizes the anchor head from its float count', () {
      expect(deriveOutputShape(13 * 21504), [1, 13, 21504]);
      expect(isEndToEndShape(deriveOutputShape(13 * 21504)), isFalse);
    });
  });

  group('DetectionLayout class order', () {
    // The migration's one silent failure mode: v10 puts the dart at class 0
    // and the calibration points at 1-8, the exact inverse of every earlier
    // export. Read the wrong way round, darts become control points and the
    // homography goes absurd without a single error being raised.
    test('v10 maps class 0 to the dart and 1-8 to p1-p8', () {
      expect(v10.toInternalClassId(0), 8); // dart → internal tip
      for (int c = 1; c <= 8; c++) {
        expect(v10.toInternalClassId(c), c - 1);
      }
      expect(v10.toInternalClassId(9), -1);
      expect(v10.toInternalClassId(-1), -1);
    });

    test('the light model keeps the historical order', () {
      expect(light.toInternalClassId(8), 8); // dart stays at 8
      expect(light.toInternalClassId(0), 0); // p1 stays at 0
      expect(light.toInternalClassId(9), -1);
    });

    test('layouts survive the round trip through the parse isolate', () {
      for (final l in DetectionLayout.values) {
        expect(DetectionLayout.byId(l.id), same(l));
      }
    });

    test('the bundled assets share the DartsMind anchor layout', () {
      // Both device tiers (light/heavy) parse under the same contract, so
      // whichever one init() picks, the const layout stays correct.
      expect(ModelSelector.currentLayout, DetectionLayout.anchorDartLast);
      expect(ModelSelector.currentAsset,
          anyOf(ModelSelector.lightAsset, ModelSelector.heavyAsset));
    });
  });

  group('parseEndToEndOutput (v10 layout)', () {
    // Portrait frame 720×1280 → xScale = 1280/720, yScale = 1.0 (same
    // convention as the preprocess in dart_detection_service.dart).
    const xScale = 1280 / 720;
    const yScale = 1.0;

    List<Detection> parse(List<List<double>> rows,
            {DetectionLayout layout = v10}) =>
        parseEndToEndOutput(e2eBuffer(rows), [1, 300, 6],
            xScale: xScale, yScale: yScale, layout: layout);

    test('class 0 is a dart, and its box CENTRE is the tip', () {
      // Box centred at canvas pixel (256, 512), 20px wide, 30px tall.
      final dets = parse([
        [246, 497, 266, 527, 0.95, 0],
      ]);
      expect(dets, hasLength(1));
      final d = dets.single;
      expect(d.isTip, isTrue);
      expect(d.className, 'tip');
      expect(d.confidence, closeTo(0.95, 1e-6));
      expect(d.x, closeTo(256 / 1024 * xScale, 1e-6));
      expect(d.y, closeTo(512 / 1024 * yScale, 1e-6));
      expect(d.width, closeTo(20 / 1024 * xScale, 1e-6));
      expect(d.height, closeTo(30 / 1024 * yScale, 1e-6));
    });

    test('classes 1-8 are calibration points with the right flag', () {
      // Portrait letterbox: the frame occupies canvas x ∈ [0, 576] — keep
      // the boxes inside it (beyond, the boundary check rightfully drops).
      final dets = parse([
        [100, 100, 110, 110, 0.97, 1], // cal_45  → p1
        [500, 100, 510, 110, 0.96, 4], // cal_135 → p4
        [100, 900, 110, 910, 0.98, 8], // cal_315 → p8
      ]);
      expect(dets.map((d) => d.className), ['p1', 'p4', 'p8']);
      expect(dets.map((d) => d.flag), [1, 4, 8]);
      expect(dets.every((d) => d.isControlPoint), isTrue);
    });

    test('the same rows read under the wrong class order give the WRONG board',
        () {
      // Guards the migration itself: parsed with the old order, v10's dart
      // row (class 0) turns into control point p1. Nothing throws — which is
      // exactly why the layout is explicit configuration. The candidate here
      // differs from v10 in the class order ALONE, so the assertion cannot
      // be satisfied by some other axis of the layout.
      const dartLastSameUnits = DetectionLayout(
        id: 'test-dart-last-px',
        dartClassIndex: DartClassIndex.last,
        boxUnits: BoxUnits.canvasPixels,
        tipThreshold: 0.50,
        controlPointThreshold: kConfidenceThreshold,
      );
      final asV10 = parse([
        [246, 497, 266, 527, 0.95, 0],
      ]);
      final asDartLast = parse([
        [246, 497, 266, 527, 0.95, 0],
      ], layout: dartLastSameUnits);
      expect(asV10.single.isTip, isTrue);
      expect(asDartLast.single.isControlPoint, isTrue);
      expect(asDartLast.single.className, 'p1');
    });

    test('canvas-pixel rows read as normalized are dropped, not mislabelled',
        () {
      // The units axis fails LOUDLY, unlike the class order: 246 read as a
      // normalized coordinate puts the box ~1000 frame-widths off screen and
      // the boundary check drops it. This is the whole reason
      // dartboard-v10_o2o_float16 "saw nothing" on 2026-08-13 rather than
      // scoring a garbage board.
      expect(parse([
        [246, 497, 266, 527, 0.95, 0],
      ], layout: light), isEmpty);
    });

    test('darts pass at 0.50 but calibration points need 0.80', () {
      final dets = parse([
        [246, 497, 266, 527, 0.55, 0], // dart, above 0.50 → kept
        [100, 100, 110, 110, 0.55, 1], // p1, below 0.80 → dropped
        [200, 200, 210, 210, 0.85, 2], // p2, above 0.80 → kept
      ]);
      expect(dets.map((d) => d.className), containsAll(['tip', 'p2']));
      expect(dets.map((d) => d.className), isNot(contains('p1')));
      expect(dets, hasLength(2));
    });

    test('padding rows and sub-threshold rows are dropped', () {
      expect(
          parse([
            [246, 497, 266, 527, 0.49, 0], // dart below 0.50
            [246, 497, 266, 527, 0.01, 0], // padding-level conf
          ]),
          isEmpty);
    });

    test('invalid class ids are dropped', () {
      expect(
          parse([
            [246, 497, 266, 527, 0.95, 11],
            [246, 497, 266, 527, 0.95, -1],
          ]),
          isEmpty);
    });

    test('only the best row per calibration class survives', () {
      final dets = parse([
        [100, 100, 110, 110, 0.97, 1],
        [300, 300, 310, 310, 0.99, 1], // same class, higher conf → wins
        [200, 200, 210, 210, 0.95, 1],
      ]);
      expect(dets, hasLength(1));
      expect(dets.single.confidence, closeTo(0.99, 1e-6));
      expect(dets.single.x, closeTo(305 / 1024 * xScale, 1e-6));
    });

    test('best-per-class does not depend on the rows being sorted', () {
      final ascending = parse([
        [100, 100, 110, 110, 0.85, 1],
        [300, 300, 310, 310, 0.99, 1],
      ]);
      expect(ascending.single.confidence, closeTo(0.99, 1e-6));
    });

    test('no NMS: two close darts both survive', () {
      // Two rows 6 canvas px apart — the anchor NMS's dist filter would
      // merge them; the e2e path must keep both (the head deduplicates).
      final dets = parseModelOutput(
          e2eBuffer([
            [246, 497, 266, 527, 0.95, 0],
            [252, 497, 272, 527, 0.90, 0],
          ]),
          [1, 300, 6],
          xScale: xScale,
          yScale: yScale,
          layout: v10);
      expect(dets, hasLength(2));
    });

    test('parseModelOutput routes the anchor shape through NMS', () {
      // Minimal anchor buffer: 2 elements, 13 channels, both the same tip —
      // NMS must collapse the duplicate (IoU 1.0 > 0.958).
      const elements = 2;
      final floats = Float32List(13 * elements);
      for (int i = 0; i < elements; i++) {
        floats[i] = 0.25; // cx
        floats[elements + i] = 0.5; // cy
        floats[elements * 2 + i] = 0.02; // w
        floats[elements * 3 + i] = 0.03; // h
        floats[elements * 12 + i] = 0.9; // tip conf (channel 4+8)
      }
      final dets = parseModelOutput(floats, [1, 13, elements],
          xScale: xScale, yScale: yScale, layout: light);
      expect(dets, hasLength(1));
      expect(dets.single.isTip, isTrue);
    });
  });

  group('dropCollidingControlPoints', () {
    // Points on a circle of diameter 0.5 centred at (0.5, 0.5).
    test('keeps a well-spread board untouched', () {
      final pts = [
        cp(0, 0.75, 0.50),
        cp(2, 0.50, 0.75),
        cp(4, 0.25, 0.50),
        cp(6, 0.50, 0.25),
      ];
      expect(dropCollidingControlPoints(pts), hasLength(4));
    });

    test('drops BOTH members of a colliding pair, never one at random', () {
      final pts = [
        cp(0, 0.75, 0.50),
        cp(1, 0.7505, 0.50), // 0.1% of the 0.5 diameter away → collides
        cp(4, 0.25, 0.50),
        cp(6, 0.50, 0.25),
      ];
      final kept = dropCollidingControlPoints(pts);
      expect(kept.map((d) => d.classId), [4, 6]);
    });

    test('a pair just outside the 2% floor is kept', () {
      // Diameter here is 0.5, so the floor is 0.01.
      final pts = [
        cp(0, 0.75, 0.50),
        cp(1, 0.7389, 0.50), // 0.0111 apart → above the floor
        cp(4, 0.25, 0.50),
        cp(6, 0.50, 0.25),
      ];
      expect(dropCollidingControlPoints(pts), hasLength(4));
    });

    test('fewer than three points are left alone', () {
      final pts = [cp(0, 0.5, 0.5), cp(1, 0.5001, 0.5)];
      expect(dropCollidingControlPoints(pts), hasLength(2));
    });
  });
}

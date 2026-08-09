import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/detection_parsing.dart';

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

void main() {
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

  group('parseEndToEndOutput', () {
    // Portrait frame 720×1280 → xScale = 1280/720, yScale = 1.0 (same
    // convention as the preprocess in dart_detection_service.dart).
    const xScale = 1280 / 720;
    const yScale = 1.0;

    test('tip row maps to the anchor parser coordinate space', () {
      // Box centred at canvas pixel (256, 512), 20px wide, 30px tall.
      final floats = e2eBuffer([
        [246, 497, 266, 527, 0.95, 8],
      ]);
      final dets = parseEndToEndOutput(floats, [1, 300, 6],
          xScale: xScale, yScale: yScale);
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

    test('calibration classes keep their id and flag', () {
      // Portrait letterbox: the frame occupies canvas x ∈ [0, 576] — keep
      // the boxes inside it (beyond, the boundary check rightfully drops).
      final floats = e2eBuffer([
        [100, 100, 110, 110, 0.97, 0], // p1
        [500, 100, 510, 110, 0.96, 3], // p4
        [100, 900, 110, 910, 0.98, 7], // p8
      ]);
      final dets = parseEndToEndOutput(floats, [1, 300, 6],
          xScale: xScale, yScale: yScale);
      expect(dets.map((d) => d.className), ['p1', 'p4', 'p8']);
      expect(dets.map((d) => d.flag), [1, 4, 8]);
      expect(dets.every((d) => d.isControlPoint), isTrue);
    });

    test('padding rows and sub-threshold rows are dropped', () {
      final floats = e2eBuffer([
        [246, 497, 266, 527, 0.79, 8], // below kConfidenceThreshold (0.80)
        [246, 497, 266, 527, 0.01, 8], // padding-level conf
      ]);
      expect(
          parseEndToEndOutput(floats, [1, 300, 6],
              xScale: xScale, yScale: yScale),
          isEmpty);
    });

    test('invalid class ids are dropped', () {
      final floats = e2eBuffer([
        [246, 497, 266, 527, 0.95, 11],
        [246, 497, 266, 527, 0.95, -1],
      ]);
      expect(
          parseEndToEndOutput(floats, [1, 300, 6],
              xScale: xScale, yScale: yScale),
          isEmpty);
    });

    test('no NMS: two close tips both survive', () {
      // Two rows 6 canvas px apart — the anchor NMS's dist filter would
      // merge them; the e2e path must keep both (the head deduplicates).
      final floats = e2eBuffer([
        [246, 497, 266, 527, 0.95, 8],
        [252, 497, 272, 527, 0.90, 8],
      ]);
      final dets = parseModelOutput(floats, [1, 300, 6],
          xScale: xScale, yScale: yScale);
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
          xScale: xScale, yScale: yScale);
      expect(dets, hasLength(1));
    });
  });
}

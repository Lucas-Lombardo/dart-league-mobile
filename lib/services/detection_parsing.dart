import 'dart:math';
import 'dart:typed_data';

import 'dart_detection_types.dart';

// ---------------------------------------------------------------------------
// Pure output-tensor parsing (DartsMind: findBestBox + classSpecificNMS).
//
// Extracted from DartDetectionService so the SAME code runs either inline or
// inside the persistent parse isolate (output_parse_isolate.dart) — the
// ~194k-float scan per inference used to run on the Flutter UI isolate.
// No Flutter imports allowed here: this file is loaded by a worker isolate.
// ---------------------------------------------------------------------------

const double kConfidenceThreshold = 0.8;
const double kIouThresholdTip = 0.958;
const double kIouThresholdP = 0.85;

const List<String> kDetectionLabels = [
  'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'tip'
];

// ---------------------------------------------------------------------------
// Two output formats coexist, dispatched on the output-tensor shape:
//   [1, 13, 21504] — anchor head (DartsMind + v3..v6 exports):
//                    parseOutputFloats, then classSpecificNms.
//   [1, 300, 6]    — end-to-end head (YOLO26, v7s+): rows of
//                    [x1, y1, x2, y2, conf, cls], already deduplicated —
//                    parseEndToEndOutput, NO NMS.
// ---------------------------------------------------------------------------

/// Row length of the end-to-end (YOLO26) head: [x1, y1, x2, y2, conf, cls].
const int kEndToEndRowLen = 6;

/// The model input canvas is 1024×1024; e2e coordinates are in pixels of
/// that canvas (the anchor head emits them already normalized to [0,1]).
const double _e2eCanvasSize = 1024.0;

bool isEndToEndShape(List<int> shape) =>
    shape.isNotEmpty && shape.last == kEndToEndRowLen;

/// Reconstruct the output shape from a raw float count when the tensor shape
/// is not available (native inference returns bare bytes). The two head
/// populations are orders of magnitude apart — anchor is ≥ 13×21504 ≈ 280k
/// floats, e2e is ≤ 300×6 = 1800 — so a small buffer is e2e.
List<int> deriveOutputShape(int totalFloats) => totalFloats <= 6000
    ? [1, totalFloats ~/ kEndToEndRowLen, kEndToEndRowLen]
    : [1, 13, totalFloats ~/ 13];

/// Parse the end-to-end head ([1, 300, 6]): one row per object, xyxy in
/// pixels of the 1024 letterbox canvas. Same confidence threshold and the
/// same xScale/yScale de-letterboxing as the anchor parser; padding rows
/// (conf ≈ 0) fall out with the threshold. The head is already
/// deduplicated — callers must NOT run NMS on the result.
List<Detection> parseEndToEndOutput(
  Float32List floats,
  List<int> shape, {
  required double xScale,
  required double yScale,
}) {
  final numRows = shape[1]; // 300
  final detections = <Detection>[];

  for (int i = 0; i < numRows; i++) {
    final off = i * kEndToEndRowLen;
    final conf = floats[off + 4];
    if (conf <= kConfidenceThreshold) continue;
    final classId = floats[off + 5].round();
    if (classId < 0 || classId >= kDetectionLabels.length) continue;

    // xyxy pixels → [0,1] canvas → the anchor parser's scaled space.
    final cx = (floats[off] + floats[off + 2]) / 2.0 / _e2eCanvasSize * xScale;
    final cy =
        (floats[off + 1] + floats[off + 3]) / 2.0 / _e2eCanvasSize * yScale;
    final w =
        (floats[off + 2] - floats[off]).abs() / _e2eCanvasSize * xScale;
    final h =
        (floats[off + 3] - floats[off + 1]).abs() / _e2eCanvasSize * yScale;

    // Same boundary check as the anchor parser.
    if (cx - w / 2 > 1.0 ||
        cy - h / 2 > 1.0 ||
        cx + w / 2 < 0.0 ||
        cy + h / 2 < 0.0) {
      continue;
    }

    detections.add(Detection(
      classId: classId,
      className: kDetectionLabels[classId],
      x: cx.clamp(0.0, 1.5), // can exceed 1.0 due to aspect ratio
      y: cy.clamp(0.0, 1.5),
      width: w,
      height: h,
      confidence: conf,
    ));
  }
  return detections;
}

/// Shape-dispatched parse: e2e head comes back ready (already deduplicated),
/// anchor head goes through parseOutputFloats + classSpecificNms. Single
/// entry point so the inline path and the parse isolate cannot diverge.
List<Detection> parseModelOutput(
  Float32List floats,
  List<int> shape, {
  required double xScale,
  required double yScale,
}) {
  if (isEndToEndShape(shape)) {
    return parseEndToEndOutput(floats, shape, xScale: xScale, yScale: yScale);
  }
  return classSpecificNms(
      parseOutputFloats(floats, shape, xScale: xScale, yScale: yScale));
}

/// Matches DartsMind's `findBestBox` exactly:
/// - Iterates 21504 elements, 9 class channels (p1-p8 + tip)
/// - Confidence threshold 0.8
/// - Coordinates scaled by xScale/yScale (aspect ratio correction)
/// - Boundary check: minX ≤ 1, minY ≤ 1, maxX ≥ 0, maxY ≥ 0
List<Detection> parseOutputFloats(
  Float32List floats,
  List<int> shape, {
  required double xScale,
  required double yScale,
}) {
  final numChannels = shape[1]; // 13
  final numElements = shape[2]; // 21504
  final detections = <Detection>[];

  for (int i = 0; i < numElements; i++) {
    // Find best class (channels 4..12 = p1..tip)
    int bestClass = -1;
    double bestConf = kConfidenceThreshold;
    for (int c = 4; c < numChannels; c++) {
      final conf = floats[numElements * c + i];
      if (conf > bestConf) {
        bestClass = c - 4;
        bestConf = conf;
      }
    }
    if (bestConf <= kConfidenceThreshold) continue;

    // Raw model output in [0,1] relative to 1024×1024 canvas
    final cx = floats[i];
    final cy = floats[numElements + i];
    final w = floats[numElements * 2 + i];
    final h = floats[numElements * 3 + i];

    // Apply xScale / yScale  (DartsMind's findBestBox)
    final scaledCx = cx * xScale;
    final scaledCy = cy * yScale;
    final halfW = (w / 2.0) * xScale;
    final halfH = (h / 2.0) * yScale;

    final minX = scaledCx - halfW;
    final minY = scaledCy - halfH;
    final maxX = scaledCx + halfW;
    final maxY = scaledCy + halfH;

    // DartsMind boundary check
    if (minX > 1.0 || minY > 1.0 || maxX < 0.0 || maxY < 0.0) continue;

    detections.add(Detection(
      classId: bestClass,
      className: kDetectionLabels[bestClass],
      x: scaledCx.clamp(0.0, 1.5), // can exceed 1.0 due to aspect ratio
      y: scaledCy.clamp(0.0, 1.5),
      width: w * xScale,
      height: h * yScale,
      confidence: bestConf,
    ));
  }
  return detections;
}

double detectionIou(Detection a, Detection b) {
  final aLeft = a.x - a.width / 2;
  final aRight = a.x + a.width / 2;
  final aTop = a.y - a.height / 2;
  final aBottom = a.y + a.height / 2;

  final bLeft = b.x - b.width / 2;
  final bRight = b.x + b.width / 2;
  final bTop = b.y - b.height / 2;
  final bBottom = b.y + b.height / 2;

  final interLeft = max(aLeft, bLeft);
  final interRight = min(aRight, bRight);
  final interTop = max(aTop, bTop);
  final interBottom = min(aBottom, bBottom);

  if (interLeft >= interRight || interTop >= interBottom) return 0.0;

  final interArea = (interRight - interLeft) * (interBottom - interTop);
  final aArea = a.width * a.height;
  final bArea = b.width * b.height;
  final unionArea = aArea + bArea - interArea;

  return unionArea > 0 ? interArea / unionArea : 0.0;
}

/// Groups by className, applies IoU threshold per class:
///   tip → 0.958, p1-p8 → 0.85
List<Detection> classSpecificNms(List<Detection> detections) {
  final grouped = <String, List<Detection>>{};
  for (final d in detections) {
    grouped.putIfAbsent(d.className, () => []).add(d);
  }

  final result = <Detection>[];
  for (final entry in grouped.entries) {
    final cls = entry.key;
    final bboxes = entry.value
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final threshold = cls == 'tip' ? kIouThresholdTip : kIouThresholdP;

    final kept = <Detection>[];
    for (final bbox in bboxes) {
      bool suppressed = false;
      for (final k in kept) {
        if (detectionIou(bbox, k) > threshold) {
          suppressed = true;
          break;
        }
      }
      if (!suppressed) kept.add(bbox);
    }
    result.addAll(kept);
  }
  return result;
}

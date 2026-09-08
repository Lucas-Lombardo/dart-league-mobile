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

/// INTERNAL class ids, shared by every model: 0-7 = p1..p8 (the double-ring
/// wire intersections at 45°, 63°, 117°, 135°, 225°, 243°, 297°, 315° from
/// midnight, clockwise), 8 = dart tip. [Detection.flag], [Detection.isTip],
/// the per-class dedup in _bestPerClass and the homography all key off these —
/// every parser remaps the MODEL's class ids onto this order.
const List<String> kDetectionLabels = [
  'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'tip'
];

/// How many control points the board has in total. The homography only needs
/// four, so most of the pipeline works with four — but "did I read the WHOLE
/// ring?" is a different question, and this is the number that answers it.
const int kControlPointCount = 8;

/// Which class index a model gives the DART. This is the one thing about an
/// export that cannot be read off the tensor — both conventions emit 9
/// classes, so a mix-up raises no error anywhere: darts get read as
/// calibration points, calibration points as darts, and the homography
/// silently goes absurd. It therefore lives in the model's configuration
/// ([DetectionLayout]) and is passed explicitly to every parse call.
enum DartClassIndex {
  /// DartsMind and the v3..v9 exports: 0-7 = p1..p8, 8 = dart.
  last,

  /// dartboard-v10: 0 = dart, 1-8 = cal_45..cal_315 (i.e. p1..p8).
  first,
}

/// Units of the box coordinates in a model's output. Like [DartClassIndex]
/// this is invisible in the tensor — and unlike a wrong class order, a wrong
/// unit is at least loud: pixel coordinates read as normalized ones land
/// ~1000× outside the frame and every detection dies on the boundary check,
/// so the model simply "sees nothing" (dartboard-v10_o2o_float16, 2026-08-13).
enum BoxUnits {
  /// cx, cy, w, h already in [0,1] — DartsMind and the v3..v9 anchor exports.
  normalized,

  /// cx, cy, w, h in pixels of the 1024×1024 letterbox canvas — the e2e head,
  /// and any export whose graph keeps the head in input-space.
  canvasPixels,
}

/// Everything about a model's output that the parser cannot infer from the
/// tensor: the class order, the box units, and the confidence floors per kind
/// of object.
class DetectionLayout {
  /// Stable key — the parse isolate ships this string rather than the object.
  final String id;
  final DartClassIndex dartClassIndex;

  /// Confidence floor for a dart tip.
  final double tipThreshold;

  /// Confidence floor for a calibration point. Higher than [tipThreshold]:
  /// a missed dart costs one frame, a misplaced control point skews every
  /// score on the board.
  final double controlPointThreshold;

  final BoxUnits boxUnits;

  const DetectionLayout({
    required this.id,
    required this.dartClassIndex,
    required this.boxUnits,
    required this.tipThreshold,
    required this.controlPointThreshold,
  });

  /// DartsMind anchor head (dart-rival-ia-heavy): dart last, single 0.80
  /// floor for every class — the historical behaviour, unchanged.
  static const anchorDartLast = DetectionLayout(
    id: 'anchor-dart-last',
    dartClassIndex: DartClassIndex.last,
    boxUnits: BoxUnits.normalized,
    tipThreshold: kConfidenceThreshold,
    controlPointThreshold: kConfidenceThreshold,
  );

  /// dartboard-v10 end-to-end head: dart FIRST, 0.87 on darts / 0.80 on
  /// calibration points. Le floor darts était 0.50 au lancement de v13 ;
  /// remonté à 0.87 le 2026-09-01 (décision Lucas) : sur 81k fléchettes prod,
  /// les détections sous 0.87 étaient corrigées par le joueur ~15-18 % du
  /// temps (contre 0,9 % au-dessus de 0.95) et alimentaient les doublons.
  /// Une fléchette sous le floor n'est simplement pas comptée — le joueur
  /// l'ajoute à la main, comme avant v13.
  static const e2eDartFirst = DetectionLayout(
    id: 'e2e-dart-first',
    dartClassIndex: DartClassIndex.first,
    boxUnits: BoxUnits.canvasPixels,
    tipThreshold: 0.87,
    controlPointThreshold: kConfidenceThreshold,
  );

  /// dartboard-v10 float16 o2o export: the ANCHOR tensor [1, 13, 21504], but
  /// with the boxes left in canvas pixels like the e2e head — the two axes
  /// are independent, which is why they are separate fields rather than one
  /// "model format" enum. Class order and thresholds match [e2eDartFirst]
  /// (same training run).
  static const anchorPixelsDartFirst = DetectionLayout(
    id: 'anchor-px-dart-first',
    dartClassIndex: DartClassIndex.first,
    boxUnits: BoxUnits.canvasPixels,
    tipThreshold: 0.87,
    controlPointThreshold: kConfidenceThreshold,
  );

  static const List<DetectionLayout> values = [
    anchorDartLast,
    e2eDartFirst,
    anchorPixelsDartFirst,
  ];

  static DetectionLayout byId(String id) =>
      values.firstWhere((l) => l.id == id);

  /// Model class id → internal class id (0-7 = p1..p8, 8 = tip).
  /// Returns -1 for an id the layout does not define.
  int toInternalClassId(int modelClassId) {
    switch (dartClassIndex) {
      case DartClassIndex.last:
        return modelClassId >= 0 && modelClassId <= 8 ? modelClassId : -1;
      case DartClassIndex.first:
        if (modelClassId == 0) return 8; // dart
        if (modelClassId >= 1 && modelClassId <= 8) return modelClassId - 1;
        return -1;
    }
  }

  /// Confidence floor for an INTERNAL class id.
  double thresholdFor(int internalClassId) =>
      internalClassId == 8 ? tipThreshold : controlPointThreshold;

  /// Lowest floor of the layout — nothing below this can survive.
  double get minThreshold => min(tipThreshold, controlPointThreshold);
}

// ---------------------------------------------------------------------------
// Two output formats coexist, dispatched on the output-tensor shape:
//   [1, 13, 21504] — anchor head (DartsMind + v3..v6 exports):
//                    parseOutputFloats, then classSpecificNms.
//   [1, 300, 6]    — end-to-end head (YOLO26, v7+ / v10): rows of
//                    [x1, y1, x2, y2, conf, cls], already deduplicated —
//                    parseEndToEndOutput, NO NMS.
// The SHAPE picks the parser; the DetectionLayout supplies the class order
// and thresholds, which the shape cannot reveal (v7 and v10 share this head
// but disagree on where the dart sits).
// ---------------------------------------------------------------------------

/// Row length of the end-to-end (YOLO26) head: [x1, y1, x2, y2, conf, cls].
const int kEndToEndRowLen = 6;

/// The model input canvas is 1024×1024; e2e coordinates are in pixels of
/// that canvas. Whether a given export uses it is [DetectionLayout.boxUnits],
/// not the parser: both heads have been seen in both units.
const double _canvasSize = 1024.0;

/// What to divide raw box coordinates by to reach the [0,1] canvas space the
/// rest of the pipeline works in.
double _boxDivisor(DetectionLayout layout) =>
    layout.boxUnits == BoxUnits.canvasPixels ? _canvasSize : 1.0;

/// Two control points closer than this fraction of the board diameter make
/// the homography singular. Measured at 0% of frames on dartboard-v10, but
/// the check is three lines and the failure it prevents is silent.
const double kMinControlPointSeparation = 0.02;

bool isEndToEndShape(List<int> shape) =>
    shape.isNotEmpty && shape.last == kEndToEndRowLen;

/// Reconstruct the output shape from a raw float count when the tensor shape
/// is not available (native inference returns bare bytes). The two head
/// populations are orders of magnitude apart — anchor is ≥ 13×21504 ≈ 280k
/// floats, e2e is ≤ 300×6 = 1800 — so a small buffer is e2e.
List<int> deriveOutputShape(int totalFloats) => totalFloats <= 6000
    ? [1, totalFloats ~/ kEndToEndRowLen, kEndToEndRowLen]
    : [1, 13, totalFloats ~/ 13];

/// Parse the end-to-end head ([1, 300, 6]): one row per object,
/// [x1, y1, x2, y2, conf, cls] with the box corners in PIXELS of the 1024
/// letterbox canvas (the anchor head emits centre+size already normalized).
/// The point of interest is the box CENTRE — the tip for a dart, the wire
/// intersection for a calibration point.
///
/// The head is already deduplicated (one object = one row), so callers must
/// NOT run NMS on the result. Only the best row per calibration class is
/// kept; darts all pass through and are thinned downstream by _filterDarts.
///
/// The rows arrive sorted by descending confidence, which would allow an
/// early break — but this export has no exact-zero padding rows (the tail
/// bottoms out around 1e-6, and the whole tensor is 1800 floats against the
/// anchor head's 280k), so the scan runs to the end and picks the best per
/// class by comparing confidences. Nothing here depends on the sort order.
List<Detection> parseEndToEndOutput(
  Float32List floats,
  List<int> shape, {
  required double xScale,
  required double yScale,
  required DetectionLayout layout,
}) {
  final numRows = shape[1]; // 300
  final floor = layout.minThreshold;
  final tips = <Detection>[];
  final bestControlPoint = <int, Detection>{};

  for (int i = 0; i < numRows; i++) {
    final off = i * kEndToEndRowLen;
    final conf = floats[off + 4];
    if (conf < floor) continue;
    final classId = layout.toInternalClassId(floats[off + 5].round());
    if (classId < 0) continue;
    if (conf < layout.thresholdFor(classId)) continue;

    // Box centre, xyxy → [0,1] canvas → the anchor parser's space.
    final divisor = _boxDivisor(layout);
    final cx = (floats[off] + floats[off + 2]) / 2.0 / divisor * xScale;
    final cy = (floats[off + 1] + floats[off + 3]) / 2.0 / divisor * yScale;
    final w = (floats[off + 2] - floats[off]).abs() / divisor * xScale;
    final h = (floats[off + 3] - floats[off + 1]).abs() / divisor * yScale;

    // Same boundary check as the anchor parser.
    if (cx - w / 2 > 1.0 ||
        cy - h / 2 > 1.0 ||
        cx + w / 2 < 0.0 ||
        cy + h / 2 < 0.0) {
      continue;
    }

    final det = Detection(
      classId: classId,
      className: kDetectionLabels[classId],
      x: cx.clamp(0.0, 1.5), // can exceed 1.0 due to aspect ratio
      y: cy.clamp(0.0, 1.5),
      width: w,
      height: h,
      confidence: conf,
    );

    if (det.isTip) {
      tips.add(det);
    } else {
      final prev = bestControlPoint[classId];
      if (prev == null || conf > prev.confidence) {
        bestControlPoint[classId] = det;
      }
    }
  }

  return [...bestControlPoint.values, ...tips];
}

/// Drop control points that sit on top of each other. Two DIFFERENT wire
/// intersections landing within [kMinControlPointSeparation] of the board
/// diameter give the homography two near-identical correspondences, which
/// makes it singular — the resulting board mapping is arbitrary. Both go:
/// keeping one at random is a coin flip on which of the two is the real
/// point, and a wrong control point skews every score on the board.
///
/// The board diameter is estimated as the widest span across the control
/// points themselves — they all sit on the double ring, so that is the ring
/// diameter as soon as a few of them are present.
List<Detection> dropCollidingControlPoints(List<Detection> controlPoints) {
  if (controlPoints.length < 3) return controlPoints;

  double sq(Detection a, Detection b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return dx * dx + dy * dy;
  }

  double widestSq = 0.0;
  for (int i = 0; i < controlPoints.length; i++) {
    for (int j = i + 1; j < controlPoints.length; j++) {
      final d = sq(controlPoints[i], controlPoints[j]);
      if (d > widestSq) widestSq = d;
    }
  }
  if (widestSq <= 0.0) return controlPoints;

  final minSq =
      widestSq * kMinControlPointSeparation * kMinControlPointSeparation;
  final colliding = <int>{};
  for (int i = 0; i < controlPoints.length; i++) {
    for (int j = i + 1; j < controlPoints.length; j++) {
      if (sq(controlPoints[i], controlPoints[j]) < minSq) {
        colliding.add(i);
        colliding.add(j);
      }
    }
  }
  if (colliding.isEmpty) return controlPoints;

  return [
    for (int i = 0; i < controlPoints.length; i++)
      if (!colliding.contains(i)) controlPoints[i]
  ];
}

/// Shape-dispatched parse: e2e head comes back ready (already deduplicated),
/// anchor head goes through parseOutputFloats + classSpecificNms. Single
/// entry point so the inline path and the parse isolate cannot diverge.
List<Detection> parseModelOutput(
  Float32List floats,
  List<int> shape, {
  required double xScale,
  required double yScale,
  required DetectionLayout layout,
}) {
  if (isEndToEndShape(shape)) {
    return parseEndToEndOutput(floats, shape,
        xScale: xScale, yScale: yScale, layout: layout);
  }
  return classSpecificNms(parseOutputFloats(floats, shape,
      xScale: xScale, yScale: yScale, layout: layout));
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
  required DetectionLayout layout,
}) {
  final numChannels = shape[1]; // 13
  final numElements = shape[2]; // 21504
  final floor = layout.minThreshold;
  final detections = <Detection>[];

  for (int i = 0; i < numElements; i++) {
    // Find best class (channels 4..12 = the model's 9 classes)
    int bestClass = -1;
    double bestConf = floor;
    for (int c = 4; c < numChannels; c++) {
      final conf = floats[numElements * c + i];
      if (conf > bestConf) {
        bestClass = layout.toInternalClassId(c - 4);
        bestConf = conf;
      }
    }
    if (bestClass < 0) continue;
    if (bestConf <= layout.thresholdFor(bestClass)) continue;

    // Raw box output → [0,1] relative to the 1024×1024 canvas. Exports of
    // this same head disagree on the units: DartsMind emits [0,1] already,
    // the v10 float16 o2o export emits canvas pixels.
    final divisor = _boxDivisor(layout);
    final cx = floats[i] / divisor;
    final cy = floats[numElements + i] / divisor;
    final w = floats[numElements * 2 + i] / divisor;
    final h = floats[numElements * 3 + i] / divisor;

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

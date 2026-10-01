import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/auto_scoring_service.dart';
import 'package:mobile/services/dart_detection_types.dart';
import 'package:mobile/services/dart_scoring_service.dart';

/// The scorer's rules, one failure mode at a time, on synthetic frames.
///
/// The camera looks straight at the board: board space (340 units = 340 mm,
/// centre 170,170) maps linearly onto a 1000×1000 px frame, so a board point
/// b sits at b/340 in normalised image coordinates. Frames are 0.25 s apart,
/// the app's capture cadence.
void main() {
  late AutoScoringService svc;
  late List<(int, String)> emitted;
  late int autoConfirms;
  var t = 1000.0;
  var seq = 0;
  final savedPrint = debugPrint;

  setUp(() {
    debugPrint = (String? message, {int? wrapWidth}) {};
    AutoScoringService.verboseScoringLog = false;
    t = 1000.0;
    seq = 0;
    AutoScoringService.clock = () => t;
    svc = AutoScoringService();
    emitted = [];
    autoConfirms = 0;
    svc.resetTurn();
    svc.debugMarkCaptureStart();
  });

  tearDown(() {
    svc.dispose();
    debugPrint = savedPrint;
  });

  Future<FrameDisposition> feed(ScoringResult r) async {
    seq++;
    final d = await svc.debugProcessResult(
      r,
      seq: seq,
      onDartDetected: (slot, score) => emitted.add((seq, score.formatted)),
      onAutoConfirm: () => autoConfirms++,
    );
    t += 0.25;
    return d;
  }

  Future<void> feedN(int n, ScoringResult Function() r) async {
    for (var i = 0; i < n; i++) {
      await feed(r());
    }
  }

  /// Five still, empty frames: the stable calibration's reference.
  Future<void> settleEmptyBoard() => feedN(5, () => frame());

  test('a dart is shown on its third read in a row, not before', () async {
    await settleEmptyBoard();
    final t20 = bed(20, triple: true);
    await feed(frame(tips: [t20]));
    await feed(frame(tips: [t20]));
    expect(emitted, isEmpty);
    await feed(frame(tips: [t20]));
    expect(emitted.map((e) => e.$2), ['T20 (60)']);
  });

  test('a dart on a wire waits for more reads, then scores from their mean',
      () async {
    await settleEmptyBoard();
    // Outer single, 0.15 mm either side of the 20|1 wire.
    final on20 = polar(0.78, _wire20to1 - 0.15 / (0.78 * 170));
    final on1 = polar(0.78, _wire20to1 + 0.15 / (0.78 * 170));
    final reads = [on20, on1, on20, on20, on1];
    for (final p in reads) {
      await feed(frame(tips: [p]));
    }
    // 3 reads to confirm + 2 wire holds: shown on the 5th frame.
    expect(emitted.length, 1);
    expect(emitted.single.$1, 5 + 5);
    final mean = [
      reads.map((p) => p[0]).reduce((a, b) => a + b) / reads.length,
      reads.map((p) => p[1]).reduce((a, b) => a + b) / reads.length,
    ];
    expect(emitted.single.$2,
        DartScoringService.scoreBoardPoint(mean[0], mean[1]).formatted);
  });

  test('a tip read far off the board is never a dart', () async {
    await settleEmptyBoard();
    await feedN(6, () => frame(tips: [[170 + 400, 170]]));
    expect(emitted, isEmpty);
  });

  test('a frame that cannot see the board does not break a confirmation',
      () async {
    await settleEmptyBoard();
    final s5 = bed(5);
    await feed(frame(tips: [s5]));
    await feed(frame(tips: [s5]));
    await feed(frame(cps: const {}, tips: const [])); // hand over the camera
    expect(emitted, isEmpty);
    await feed(frame(tips: [s5]));
    expect(emitted.map((e) => e.$2), ['S5 (5)']);
  });

  test('a flight pulling a ring point does not move the board', () async {
    await settleEmptyBoard();
    // 0.4 mm inside the 20, next to the 20|1 wire.
    final dart = polar(0.78, _wire20to1 - 0.4 / (0.78 * 170));
    // A flight over p1 (18|4 wire) drags its detection 12 mm up: the fit of
    // that frame alone turns the board and pushes this dart over into the 1.
    final pulled = {1: const [0.0, -12.0]};
    final raw = frame(tips: [dart], cpShift: pulled);
    final perFrameFit = DartScoringService(raw.calibrationPoints
            .map((c) => [c.x, c.y, c.flag.toDouble()])
            .toList())
        .score(dart[0] / 340, dart[1] / 340)
        .formatted;
    expect(perFrameFit, isNot('S20 (20)'),
        reason: 'precondition: the disturbed fit alone misreads this dart');
    await feedN(3, () => frame(tips: [dart], cpShift: pulled));
    expect(emitted.map((e) => e.$2), ['S20 (20)']);
  });

  test('one dart read as two tips 2.4 mm apart is counted once', () async {
    await settleEmptyBoard();
    final a = bed(19, triple: true);
    final split = [a[0] + 2.4, a[1]];
    await feedN(3, () => frame(tips: [a]));
    await feedN(8, () => frame(tips: [a, split]));
    expect(emitted.map((e) => e.$2), ['T19 (57)']);
  });

  test('two real darts that appear together are both counted', () async {
    await settleEmptyBoard();
    final a = bed(20, triple: true);
    final b = [a[0] + 9, a[1] + 1];
    await feedN(8, () => frame(tips: [a, b]));
    expect(emitted.length, 2);
  });

  test('darts already in the board when the visit starts are never counted',
      () async {
    await settleEmptyBoard();
    svc.waitForEmptyBoardOnce();
    final left1 = bed(1), left2 = bed(18);
    await feedN(4, () => frame(tips: [left1, left2]));
    expect(svc.showRemoveDartsHint, isTrue);
    final thrown = bed(20, triple: true);
    await feedN(4, () => frame(tips: [left1, left2, thrown]));
    expect(emitted.map((e) => e.$2), ['T20 (60)']);
    // Everything pulled: the board is seen empty, the hint goes away.
    await feedN(4, () => frame());
    expect(svc.showRemoveDartsHint, isFalse);
  });

  test('darts the previous visit left in the board are recognised', () async {
    await settleEmptyBoard();
    final d1 = bed(5), d2 = bed(20), d3 = bed(1);
    await feedN(6, () => frame(tips: [d1, d2, d3]));
    expect(emitted.length, 3);
    // Visit closed by hand, darts left in place.
    svc.resetTurn();
    svc.waitForEmptyBoardOnce();
    emitted.clear();
    // The player stands in front of them at first: the board is seen, the
    // darts are not — then they show up again.
    await feed(frame());
    await feedN(5, () => frame(tips: [d1, d2, d3]));
    expect(emitted, isEmpty);
    final next = bed(12);
    await feedN(4, () => frame(tips: [d1, d2, d3, next]));
    expect(emitted.map((e) => e.$2), ['S12 (12)']);
  });

  test('a body in front of the board never passes for an empty board',
      () async {
    await settleEmptyBoard();
    final a = bed(20), b = bed(5);
    await feedN(5, () => frame(tips: [a, b]));
    expect(emitted.length, 2);
    // No tip, but only 5 of the 8 ring points: someone is in front.
    await feedN(8, () => frame(cps: const {1, 2, 3, 4, 5}));
    expect(autoConfirms, 0);
    // Out of the way: four frames that see the whole ring and no dart.
    await feedN(4, () => frame());
    expect(autoConfirms, 1);
  });

  test('a one-dart visit asks for CONFIRM instead of passing the hand',
      () async {
    await settleEmptyBoard();
    await feedN(4, () => frame(tips: [bed(20)]));
    expect(emitted.length, 1);
    await feedN(12, () => frame());
    expect(autoConfirms, 0);
    expect(svc.manualConfirmNeeded, isTrue);
  });

  test('a dart born 10 mm from the previous one 1.15–2 s later needs a '
      'longer track', () async {
    await settleEmptyBoard();
    final a = bed(20, triple: true);
    await feedN(3, () => frame(tips: [a]));
    expect(emitted.length, 1);
    final wait = 1.5 - 3 * 0.25; // land the next dart 1.5 s after the first
    await feedN((wait / 0.25).round(), () => frame(tips: [a]));
    final b = [a[0] + 6, a[1]];
    final before = seq;
    await feedN(8, () => frame(tips: [a, b]));
    expect(emitted.length, 2);
    // Not on its 3rd read like a plain dart: it needs 5 frames of track.
    expect(emitted.last.$1 - before, greaterThan(3));
  });
}

// ---- Synthetic frames ------------------------------------------------------

const double _c = 170.0;
const double _px = 1000.0;
const double _wire20to1 = 4.86946870;

/// Board point at normalised radius [r] (1 = outer double wire) and angle
/// [a] (radians, atan2 in screen space: y down).
List<double> polar(double r, double a) =>
    [_c + r * _c * cos(a), _c + r * _c * sin(a)];

/// Centre of a bed, as the app places a typed score.
List<double> bed(int n, {bool triple = false, bool double = false}) =>
    DartScoringService.boardPointForNotation(
        baseScore: n, isDouble: double, isTriple: triple)!;

List<double> _flag(int f) {
  final s25 = sin(pi / 4), c25 = cos(pi / 4);
  final s35 = sin(0.35 * pi), c35 = cos(0.35 * pi);
  switch (f) {
    case 1:
      return [_c + s25 * _c, _c - c25 * _c];
    case 2:
      return [_c + s35 * _c, _c - c35 * _c];
    case 3:
      return [_c + s35 * _c, _c + c35 * _c];
    case 4:
      return [_c + s25 * _c, _c + c25 * _c];
    case 5:
      return [_c - s25 * _c, _c + c25 * _c];
    case 6:
      return [_c - s35 * _c, _c + c35 * _c];
    case 7:
      return [_c - s35 * _c, _c - c35 * _c];
    default:
      return [_c - s25 * _c, _c - c25 * _c];
  }
}

/// One analysed frame: ring points [cps] (flags 1-8; each detected at 0.95),
/// optionally dragged by [cpShift] (board units), and dart tips [tips].
ScoringResult frame({
  Set<int> cps = const {1, 2, 3, 4, 5, 6, 7, 8},
  List<List<double>> tips = const [],
  Map<int, List<double>> cpShift = const {},
}) {
  final points = [
    for (final f in cps)
      Detection(
        classId: f - 1,
        className: 'p$f',
        x: (_flag(f)[0] + (cpShift[f]?[0] ?? 0)) / 340,
        y: (_flag(f)[1] + (cpShift[f]?[1] ?? 0)) / 340,
        width: 0.02,
        height: 0.02,
        confidence: 0.95,
      ),
  ];
  final darts = [
    for (final p in tips)
      Detection(
        classId: 8,
        className: 'tip',
        x: p[0] / 340,
        y: p[1] / 340,
        width: 0.01,
        height: 0.01,
        confidence: 0.93,
      ),
  ];
  final scores = points.length >= 4 && darts.isNotEmpty
      ? (() {
          final s = DartScoringService(
              points.map((c) => [c.x, c.y, c.flag.toDouble()]).toList());
          return darts.map((d) => s.score(d.x, d.y)).toList();
        })()
      : <DartScore>[];
  return ScoringResult(
    calibrationPoints: points,
    dartTips: darts,
    scores: scores,
    totalScore: scores.fold(0, (a, s) => a + s.score),
    imageWidth: _px.toInt(),
    imageHeight: _px.toInt(),
    detectedControlPoints: points.length,
    error: points.length < 4
        ? 'Need 4 control points'
        : (darts.isEmpty ? 'No darts detected' : null),
  );
}

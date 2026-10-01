import 'dart:math';

import 'dart_detection_types.dart';

/// Board calibration that holds still while darts are in the board — a port
/// of DartsMind's calculateCPGroup / analyseCPFlow (DVMind, 4.4.12).
///
/// The scorer used to fit the board on every frame from whatever control
/// points the model saw in THAT frame. With darts in the board, a flight can
/// hide a point or pull it a few pixels: the fit moves, and a dart near a
/// wire changes bed. DartsMind instead keeps a REFERENCE, the average of
/// several consecutive frames where every point was sharp and still, taken
/// while the board was empty. Whenever darts are present (or points are
/// missing), it reuses that reference, shifted by how far the points still
/// visible have moved — so a nudged camera is followed, but a single point
/// disturbed by a dart is not.
///
/// One deliberate difference: DartsMind shifts the reference by the mean
/// offset of EVERY detected point, outliers included, so one point dragged
/// 20 px by a flight drags the whole board ~3 px. Here the shift is the mean
/// over the points that actually match the reference (within the stability
/// threshold) — the disturbed point is the one the reference exists to ignore.
///
/// Distances are in pixels of the analysed frame, as in DartsMind, so its
/// thresholds apply unchanged: 3 px on a frame whose short side is ≤ 722,
/// 4 px above.
///
/// Our detector hands over at most one point per class (best per class).
/// DartsMind requires all 8 for a "clean" frame; here any set of ≥ 4 classes
/// can form a reference, provided it is the same set on every frame of the
/// window — an older pipeline or a partly framed board still gets one.
class StableCalibration {
  StableCalibration({this.window = 5});

  /// Frames per stability check — DartsMind's tipThreshold + 2.
  final int window;

  /// Minimum classes to build a reference from.
  static const int minPoints = 4;

  /// Reference points must have been seen at least this sure on every frame.
  static const double minConfidence = 0.85;

  /// Classes that must match a reference before it is reused.
  static const int minMatches = 2;

  final List<Map<int, _Cp>> _flow = [];
  Map<int, _Cp> _stableAvg = {};
  Map<int, _Cp> _backupStableAvg = {};
  Map<int, _Cp> _stableNoDartAvg = {};

  /// Mean distance (px) between this frame's points and the reference — the
  /// value DartsMind's shake detector watches. Null when nothing compared.
  double? lastShift;

  /// Whether the last [update] substituted the (shifted) reference.
  bool lastFromReference = false;

  bool get hasEmptyBoardReference => _stableNoDartAvg.isNotEmpty;

  void reset() {
    _flow.clear();
    _stableAvg = {};
    _backupStableAvg = {};
    _stableNoDartAvg = {};
    lastShift = null;
    lastFromReference = false;
  }

  /// Feed one frame's control points (normalised to the frame) and get back
  /// the points to calibrate this frame with — the shifted reference when it
  /// applies, the frame's own points otherwise.
  List<Detection> update(
    List<Detection> points, {
    required bool hasTip,
    required int imageWidth,
    required int imageHeight,
  }) {
    lastShift = null;
    lastFromReference = false;
    final w = imageWidth <= 0 ? 1 : imageWidth;
    final h = imageHeight <= 0 ? 1 : imageHeight;
    final threshold = min(w, h) > 722 ? 4.0 : 3.0;

    final current = <int, _Cp>{};
    for (final p in points) {
      if (p.flag < 1 || p.flag > 8) continue;
      final cp = _Cp(p.x * w, p.y * h, p.confidence, hasTip, p);
      final kept = current[p.flag];
      if (kept == null || cp.cnf > kept.cnf) current[p.flag] = cp;
    }

    // Clean frame: no dart and a full enough ring — the frame's own points
    // are the truth, and they feed the next reference.
    if (!hasTip && current.length >= minPoints) {
      if (_stableNoDartAvg.isNotEmpty) {
        lastShift = _meanDistance(_stableNoDartAvg, current);
      }
      _flow.add(current);
      _analyseFlow(threshold);
      return points;
    }

    Map<int, _Cp>? out;
    (int, double, double, double?) match;
    if (_stableNoDartAvg.isNotEmpty) {
      match = _match(_stableNoDartAvg, current, threshold);
      lastShift = match.$4;
      if (match.$1 >= minMatches) {
        out = _shifted(_stableNoDartAvg, match.$2, match.$3);
        _flow.add(_stableNoDartAvg);
      }
    }
    final ref2 = _stableAvg.isNotEmpty ? _stableAvg : _backupStableAvg;
    if (out == null && ref2.isNotEmpty) {
      match = _match(ref2, current, threshold);
      lastShift = match.$4 ?? lastShift;
      if (match.$1 >= minMatches) {
        out = _shifted(ref2, match.$2, match.$3);
        _flow.add(ref2);
      } else if (_stableAvg.isNotEmpty) {
        // The board moved away from the reference: keep it only as a backup.
        _backupStableAvg = _stableAvg;
        _stableAvg = {};
      }
    }
    if (out == null) {
      _flow.add(current.length >= minPoints ? current : const {});
      _analyseFlow(threshold);
      return points;
    }
    _analyseFlow(threshold);
    lastFromReference = true;
    return [
      for (final e in out.entries)
        Detection(
          classId: e.key - 1,
          className: 'p${e.key}',
          x: e.value.x / w,
          y: e.value.y / h,
          width: e.value.source?.width ?? 0.02,
          height: e.value.source?.height ?? 0.02,
          confidence: e.value.cnf,
        ),
    ];
  }

  /// Matched classes, mean dx/dy over the MATCHED classes, and the mean
  /// distance over every class both sides have (DartsMind's shift value).
  (int, double, double, double?) _match(
      Map<int, _Cp> ref, Map<int, _Cp> current, double threshold) {
    var matched = 0;
    double sdx = 0, sdy = 0, sd = 0;
    var compared = 0;
    for (final e in ref.entries) {
      final c = current[e.key];
      if (c == null) continue;
      final d = _dist(e.value, c);
      sd += d;
      compared++;
      if (d < threshold) {
        matched++;
        sdx += c.x - e.value.x;
        sdy += c.y - e.value.y;
      }
    }
    return (
      matched,
      matched == 0 ? 0 : sdx / matched,
      matched == 0 ? 0 : sdy / matched,
      compared == 0 ? null : sd / compared,
    );
  }

  Map<int, _Cp> _shifted(Map<int, _Cp> ref, double dx, double dy) => {
        for (final e in ref.entries)
          e.key: _Cp(e.value.x + dx, e.value.y + dy, e.value.cnf,
              e.value.hasDart, e.value.source),
      };

  /// DartsMind analyseCPFlow: every [window] frames, if the same points were
  /// seen sharp (> 0.85) and still (within the threshold of the first frame)
  /// throughout, their average becomes the reference — and the empty-board
  /// reference when no frame of the window had a dart.
  void _analyseFlow(double threshold) {
    if (_flow.length < window) return;
    final frames = List.of(_flow);
    _flow.clear();
    final first = frames.first;
    if (first.length < minPoints) return;
    for (final f in frames) {
      if (f.length != first.length) return;
      for (final e in first.entries) {
        final c = f[e.key];
        if (c == null || c.cnf <= minConfidence) return;
        if (_dist(e.value, c) >= threshold) return;
      }
    }
    final noDart = frames.every((f) => !f.values.first.hasDart);
    final avg = <int, _Cp>{};
    for (final k in first.keys) {
      double sx = 0, sy = 0, sc = 0;
      for (final f in frames) {
        sx += f[k]!.x;
        sy += f[k]!.y;
        sc += f[k]!.cnf;
      }
      final n = frames.length;
      avg[k] = _Cp(sx / n, sy / n, sc / n, !noDart, first[k]!.source);
    }
    _stableAvg = avg;
    if (noDart) _stableNoDartAvg = avg;
  }

  double? _meanDistance(Map<int, _Cp> ref, Map<int, _Cp> current) {
    double s = 0;
    var n = 0;
    for (final e in ref.entries) {
      final c = current[e.key];
      if (c == null) continue;
      s += _dist(e.value, c);
      n++;
    }
    return n == 0 ? null : s / n;
  }

  static double _dist(_Cp a, _Cp b) =>
      sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

class _Cp {
  const _Cp(this.x, this.y, this.cnf, this.hasDart, this.source);
  final double x, y, cnf;
  final bool hasDart;
  final Detection? source;
}

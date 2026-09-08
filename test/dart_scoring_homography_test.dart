import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/dart_scoring_service.dart';

// The canonical board the scorer maps onto: centre (170, 170), the eight wire
// intersections on a 170 mm radius at 45°, 63°, 117°, 135°, 225°, 243°, 297°,
// 315° from midnight. Mirrors _flagDestination, which is private.
const double _c = 170.0;
const double _r = 170.0;
final double _s25 = sin(pi / 4), _k25 = cos(pi / 4);
final double _s35 = sin(1.0995574287564276), _k35 = cos(1.0995574287564276);

/// Canonical board position of flag 1..8, in millimetres.
List<double> _dst(int flag) => switch (flag) {
      1 => [_c + _s25 * _r, _c - _k25 * _r],
      2 => [_c + _s35 * _r, _c - _k35 * _r],
      3 => [_c + _s35 * _r, _c + _k35 * _r],
      4 => [_c + _s25 * _r, _c + _k25 * _r],
      5 => [_c - _s25 * _r, _c + _k25 * _r],
      6 => [_c - _s35 * _r, _c + _k35 * _r],
      7 => [_c - _s35 * _r, _c - _k35 * _r],
      _ => [_c - _s25 * _r, _c - _k25 * _r],
    };

/// A fixed, deliberately non-trivial perspective: the phone sees the board
/// from below and off to one side, which is how it is actually propped up.
List<double> _project(List<double> board) {
  final u = board[0] / 340.0, v = board[1] / 340.0;
  const a = 0.62, b = 0.05, c = 0.14;
  const d = -0.04, e = 0.58, f = 0.19;
  const g = 0.10, h = 0.16;
  final w = g * u + h * v + 1.0;
  return [(a * u + b * v + c) / w, (d * u + e * v + f) / w];
}

/// Image-space control points for the flags asked for, optionally nudged.
List<List<double>> _points(
  List<int> flags, {
  Map<int, List<double>> offsets = const {},
}) =>
    [
      for (final f in flags)
        () {
          final p = _project(_dst(f));
          final o = offsets[f] ?? const [0.0, 0.0];
          return [p[0] + o[0], p[1] + o[1], f.toDouble()];
        }()
    ];

/// Where the scorer puts a board point that the REAL camera projected.
///
/// It has to be the true projection going in: feeding back what the scorer's
/// own [DartScoringService.boardToImage] produced would invert the fitted
/// homography with itself and return the input whatever the fit is worth.
List<double> _whereScorerPutsIt(DartScoringService s, List<double> board) {
  final img = _project(board);
  final d = s.score(img[0], img[1]);
  return [
    _c + d.radius * _r * cos(d.angle),
    _c + d.radius * _r * sin(d.angle),
  ];
}

/// Mean board error, in millimetres, over a grid covering the scoring area.
double _meanError(DartScoringService s) {
  final errors = <double>[];
  for (double rad = 0.15; rad <= 0.95; rad += 0.2) {
    for (double ang = 0; ang < 2 * pi; ang += pi / 8) {
      final truth = [
        _c + rad * _r * cos(ang),
        _c + rad * _r * sin(ang),
      ];
      final got = _whereScorerPutsIt(s, truth);
      errors.add(sqrt(pow(got[0] - truth[0], 2) + pow(got[1] - truth[1], 2)));
    }
  }
  return errors.reduce((a, b) => a + b) / errors.length;
}

const _allEight = [1, 2, 3, 4, 5, 6, 7, 8];
// What _bestPerClass used to hand over: one point per quadrant pair.
const _quadrantFour = [1, 3, 5, 7];

void main() {
  group('homography fit', () {
    test('four exact points still reproduce the board exactly', () {
      final s = DartScoringService(_points(_quadrantFour));
      for (final flag in _quadrantFour) {
        final truth = _dst(flag);
        final got = _whereScorerPutsIt(s, truth);
        expect(got[0], closeTo(truth[0], 1e-6));
        expect(got[1], closeTo(truth[1], 1e-6));
      }
      // Four points determine the homography, so the fit is exact everywhere,
      // not just on its own points. This is the invariant that says switching
      // to least squares changed nothing when only four are visible.
      expect(_meanError(s), lessThan(1e-6));
    });

    test('eight exact points are just as exact — no averaging penalty', () {
      expect(_meanError(DartScoringService(_points(_allEight))), lessThan(1e-6));
    });

    test('under detection noise, eight points beat four', () {
      // Averaged over many draws on purpose: on any SINGLE draw the four
      // points can happen to be the accurate ones, so a threshold pinned to
      // one seed pins luck rather than the property being claimed.
      const draws = 50;
      final rng = Random(20260908);
      var eightWins = 0;
      var sumFour = 0.0, sumEight = 0.0;

      for (var i = 0; i < draws; i++) {
        // Per-point jitter of ~1.5 px on a 720-wide frame.
        final offsets = {
          for (final f in _allEight)
            f: [
              (rng.nextDouble() - 0.5) * 0.004,
              (rng.nextDouble() - 0.5) * 0.004,
            ]
        };
        final four = _meanError(
            DartScoringService(_points(_quadrantFour, offsets: offsets)));
        final eight =
            _meanError(DartScoringService(_points(_allEight, offsets: offsets)));
        sumFour += four;
        sumEight += eight;
        if (eight < four) eightWins++;
      }

      expect(eightWins, greaterThanOrEqualTo((draws * 0.9).round()));
      expect(sumEight / sumFour, lessThan(0.8));
    });

    test('one badly placed point tilts a four-point fit, not an eight', () {
      // p3 lands 2% of the frame away — a wire intersection read one segment
      // over, which is exactly what dropCollidingControlPoints cannot catch
      // because the point is nowhere near another one.
      const offsets = {
        3: [0.02, -0.015]
      };
      final four = _meanError(
          DartScoringService(_points(_quadrantFour, offsets: offsets)));
      final eight =
          _meanError(DartScoringService(_points(_allEight, offsets: offsets)));

      expect(eight, lessThan(four));
    });

    test('fewer than four points is still refused', () {
      expect(() => DartScoringService(_points([1, 3, 5])), throwsArgumentError);
    });
  });
}

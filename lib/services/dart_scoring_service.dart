import 'dart:math';

// ---------------------------------------------------------------------------
// Dartboard constants from DartsMind (dvBoard)
// Constructor: DartboardData(tMidR=101.9, dtThickness=10.0, sBullR=16.85, dBullR=6.9)
// All radii normalised to 170 mm board radius = 1.0
// ---------------------------------------------------------------------------

const double _innerBullR = 6.9 / 170.0; // 0.04059
const double _outerBullR = 16.85 / 170.0; // 0.09912
const double _tripleMidR = 101.9 / 170.0; // 0.59941
const double _dtHalf = 10.0 / (170.0 * 2.0); // half ring thickness 0.02941

// Double ring: distance in (zone2Lo, zone2Hi] = (0.94118, 1.0]
const double _zone2Hi = 1.0;
const double _zone2Lo = (170.0 - 10.0 * 0.5) / 170.0 - _dtHalf; // 0.94118

// Triple ring: distance in (zone3Lo, zone3Hi] = (0.57000, 0.62882]
const double _zone3Hi = _dtHalf + _tripleMidR; // 0.62882
const double _zone3Lo = _tripleMidR - _dtHalf; // 0.57000

// ---------------------------------------------------------------------------
// Segment / zone angle lookup  (radians, atan2(dy,dx), screen y-down)
// ---------------------------------------------------------------------------

/// Zone radian ranges – each entry maps segment number ➜ (startRad, endRad).
/// Angles measured with atan2(dy, dx) in screen-space (y-down), [0, 2π].
const Map<int, (double, double)> _zoneRadianDict = {
  10: (0.15707964, 0.47123891),
  15: (0.47123891, 0.78539819),
  2: (0.78539819, 1.09955747),
  17: (1.09955747, 1.41371674),
  3: (1.41371674, 1.72787602),
  19: (1.72787602, 2.04203530),
  7: (2.04203530, 2.35619450),
  16: (2.35619450, 2.67035380),
  8: (2.67035380, 2.98451310),
  11: (2.98451310, 3.29867240),
  14: (3.29867240, 3.61283160),
  9: (3.61283160, 3.92699090),
  12: (3.92699090, 4.24115040),
  5: (4.24115040, 4.55530930),
  20: (4.55530930, 4.86946870),
  1: (4.86946870, 5.18362800),
  18: (5.18362800, 5.49778750),
  4: (5.49778750, 5.81194640),
  13: (5.81194640, 6.12610600),
  6: (6.12610600, 6.44026470),
};

/// Ring boundaries (normalised radius).
const List<(double, double, String)> rings = [
  (0.0, _innerBullR, 'double_bull'),
  (_innerBullR, _outerBullR, 'single_bull'),
  (_outerBullR, _zone3Lo, 'inner_single'),
  (_zone3Lo, _zone3Hi, 'triple'),
  (_zone3Hi, _zone2Lo, 'outer_single'),
  (_zone2Lo, _zone2Hi, 'double'),
];

// ---------------------------------------------------------------------------
// Canonical dartboard space used by the perspective transform.
// centre = (_c, _c), calibration reference radius = _calibR,
// board-edge (scoring) radius = _boardR.
// ---------------------------------------------------------------------------

// DartsMind autoScore remaps to a 340×340 space: centre at (170, 170),
// board-edge radius = 170.  dartTipToShoot is called with boardR = 170.
// Calibration points (p1-p8) sit at the board edge (normalised distance 1.0).
// _calibR == _boardR == _c so that centre/boardR = 1.0.
const double _c = 170.0;
const double _calibR = 170.0;
const double _boardR = 170.0;

// Pre-computed flag → destination coordinate on canonical dartboard.
// Flags 1-8 correspond to 8 control points around the board at distance
// _calibR from centre.  The DartsMind source names these sin025/cos025 and
// sin035/cos035, but the actual radian values are π/4 (45°) and ~1.0996 (63°).
// (Verified from DVMind.java lines 113-116.)
final double _sin025 = sin(0.7853981633974483); // sin(45°) = 0.7071
final double _cos025 = cos(0.7853981633974483); // cos(45°) = 0.7071
final double _sin035 = sin(1.0995574287564276); // sin(63°) = 0.8910
final double _cos035 = cos(1.0995574287564276); // cos(63°) = 0.4540

List<double> _flagDestination(int flag) {
  switch (flag) {
    case 1:
      return [_c + _sin025 * _calibR, _c - _cos025 * _calibR];
    case 2:
      return [_c + _sin035 * _calibR, _c - _cos035 * _calibR];
    case 3:
      return [_c + _sin035 * _calibR, _c + _cos035 * _calibR];
    case 4:
      return [_c + _sin025 * _calibR, _c + _cos025 * _calibR];
    case 5:
      return [_c - _sin025 * _calibR, _c + _cos025 * _calibR];
    case 6:
      return [_c - _sin035 * _calibR, _c + _cos035 * _calibR];
    case 7:
      return [_c - _sin035 * _calibR, _c - _cos035 * _calibR];
    case 8:
      return [_c - _sin025 * _calibR, _c - _cos025 * _calibR];
    default:
      return [_c + _sin025 * _calibR, _c - _cos025 * _calibR];
  }
}

// ---------------------------------------------------------------------------
// DartScore
// ---------------------------------------------------------------------------

class DartScore {
  final int score;
  final int segment;
  final String ring;
  final double radius;
  final double angle;

  DartScore({
    required this.score,
    required this.segment,
    required this.ring,
    required this.radius,
    required this.angle,
  });

  String get formatted {
    if (ring == 'double_bull') return 'DBull (50)';
    if (ring == 'single_bull') return 'SBull (25)';
    if (ring == 'triple') return 'T$segment (${segment * 3})';
    if (ring == 'double') return 'D$segment (${segment * 2})';
    if (ring == 'inner_single' || ring == 'outer_single') {
      return 'S$segment ($segment)';
    }
    return 'Miss (0)';
  }
}

// ---------------------------------------------------------------------------
// DartScoringService – perspective transform + DartsMind scoring
// ---------------------------------------------------------------------------

class DartScoringService {
  late List<List<double>> _h;

  /// Build from 4 calibration points. Each entry is [x, y, flag]
  /// where x,y are normalised image coordinates and flag is 1-8.
  DartScoringService(List<List<double>> calibPointsWithFlags) {
    if (calibPointsWithFlags.length < 4) {
      throw ArgumentError(
          'Need 4 calibration points, got ${calibPointsWithFlags.length}');
    }
    _h = _computePerspectiveTransform(calibPointsWithFlags.sublist(0, 4));
  }

  // ---- Perspective transform (DLT + Hartley normalisation) ----------------

  (List<List<double>>, List<List<double>>) _hartleyNormalize(
      List<List<double>> pts) {
    double cx = 0, cy = 0;
    for (final p in pts) {
      cx += p[0];
      cy += p[1];
    }
    cx /= pts.length;
    cy /= pts.length;

    double avgDist = 0;
    for (final p in pts) {
      avgDist += sqrt(pow(p[0] - cx, 2) + pow(p[1] - cy, 2));
    }
    avgDist /= pts.length;
    final s = sqrt(2) / (avgDist == 0 ? 1 : avgDist);

    final norm = pts.map((p) => [s * (p[0] - cx), s * (p[1] - cy)]).toList();
    final t = [
      [s, 0.0, -s * cx],
      [0.0, s, -s * cy],
      [0.0, 0.0, 1.0],
    ];
    return (norm, t);
  }

  List<List<double>> _matMul3x3(List<List<double>> a, List<List<double>> b) {
    final r = List.generate(3, (_) => List.filled(3, 0.0));
    for (int i = 0; i < 3; i++) {
      for (int j = 0; j < 3; j++) {
        for (int k = 0; k < 3; k++) {
          r[i][j] += a[i][k] * b[k][j];
        }
      }
    }
    return r;
  }

  List<List<double>> _invertSimilarity(List<List<double>> t) {
    final s = t[0][0];
    final tx = t[0][2];
    final ty = t[1][2];
    final si = 1.0 / s;
    return [
      [si, 0.0, -si * tx],
      [0.0, si, -si * ty],
      [0.0, 0.0, 1.0],
    ];
  }

  /// Compute perspective transform from src (image) to dst (canonical dartboard).
  /// Each entry in [src] is [x, y, flag]. Flag determines destination point.
  List<List<double>> _computePerspectiveTransform(List<List<double>> src) {
    final srcXY = src.map((p) => [p[0], p[1]]).toList();
    final dst =
        src.map((p) => _flagDestination(p[2].round())).toList();

    final (normSrc, tSrc) = _hartleyNormalize(srcXY);
    final (normDst, tDst) = _hartleyNormalize(dst);

    final a = List.generate(8, (_) => List.filled(8, 0.0));
    final b = List.filled(8, 0.0);

    for (int i = 0; i < 4; i++) {
      final sx = normSrc[i][0], sy = normSrc[i][1];
      final dx = normDst[i][0], dy = normDst[i][1];

      a[i * 2][0] = sx;
      a[i * 2][1] = sy;
      a[i * 2][2] = 1;
      a[i * 2][6] = -dx * sx;
      a[i * 2][7] = -dx * sy;
      b[i * 2] = dx;

      a[i * 2 + 1][3] = sx;
      a[i * 2 + 1][4] = sy;
      a[i * 2 + 1][5] = 1;
      a[i * 2 + 1][6] = -dy * sx;
      a[i * 2 + 1][7] = -dy * sy;
      b[i * 2 + 1] = dy;
    }

    final hVec = _solveLinearSystem(a, b);
    final hNorm = [
      [hVec[0], hVec[1], hVec[2]],
      [hVec[3], hVec[4], hVec[5]],
      [hVec[6], hVec[7], 1.0],
    ];

    return _matMul3x3(_matMul3x3(_invertSimilarity(tDst), hNorm), tSrc);
  }

  List<double> _solveLinearSystem(List<List<double>> a, List<double> b) {
    final n = b.length;
    final aug = List.generate(
        n, (i) => List.generate(n + 1, (j) => j < n ? a[i][j] : b[i]));

    for (int col = 0; col < n; col++) {
      int maxRow = col;
      for (int row = col + 1; row < n; row++) {
        if (aug[row][col].abs() > aug[maxRow][col].abs()) maxRow = row;
      }
      final temp = aug[col];
      aug[col] = aug[maxRow];
      aug[maxRow] = temp;

      if (aug[col][col].abs() < 1e-12) continue;

      for (int row = col + 1; row < n; row++) {
        final factor = aug[row][col] / aug[col][col];
        for (int j = col; j <= n; j++) {
          aug[row][j] -= factor * aug[col][j];
        }
      }
    }

    final x = List.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      x[i] = aug[i][n];
      for (int j = i + 1; j < n; j++) {
        x[i] -= aug[i][j] * x[j];
      }
      if (aug[i][i].abs() < 1e-12) {
        throw ArgumentError(
            'Singular matrix: calibration points may be collinear');
      }
      x[i] /= aug[i][i];
    }
    return x;
  }

  // ---- Coordinate transform & scoring ------------------------------------

  List<double> _toBoard(double x, double y) {
    final w = _h[2][0] * x + _h[2][1] * y + _h[2][2];
    final bx = (_h[0][0] * x + _h[0][1] * y + _h[0][2]) / w;
    final by = (_h[1][0] * x + _h[1][1] * y + _h[1][2]) / w;
    return [bx, by];
  }

  /// Replicate DartsMind's `dartTipToShoot` exactly.
  DartScore score(double x, double y) {
    final board = _toBoard(x, y);

    // Normalise to unit circle centred at (1.0, 1.0)
    final normX = board[0] / _boardR;
    final normY = board[1] / _boardR;

    // Distance from centre (1.0, 1.0)
    final dist = sqrt(pow(normX - 1.0, 2) + pow(normY - 1.0, 2));

    // Angle using atan2(dy, dx) – screen coords (y-down)
    double angle =
        atan2(normY - 1.0, normX - 1.0);
    while (angle < 0) {
      angle += 2 * pi;
    }
    // Wrap at ±π/20 to keep zone 6 contiguous
    if (angle < 0.15707964) {
      angle += 2 * pi;
    } else if (angle > 6.44026470) {
      angle -= 2 * pi;
    }

    // --- Bull / miss ---
    if (dist <= _innerBullR) {
      return DartScore(
          score: 50, segment: 25, ring: 'double_bull', radius: dist, angle: angle);
    }
    if (dist <= _outerBullR) {
      return DartScore(
          score: 25, segment: 25, ring: 'single_bull', radius: dist, angle: angle);
    }
    if (dist > 1.0) {
      return DartScore(
          score: 0, segment: 0, ring: 'miss', radius: dist, angle: angle);
    }

    // --- Segment from angle ---
    // DartsMind iterates zones 1..20 without break (last match wins).
    // Zones don't overlap so result is the same, but we match the pattern.
    int segment = 20; // default (DartsMind: i2 = 20)
    for (int i = 1; i <= 20; i++) {
      final range = _zoneRadianDict[i];
      if (range != null && angle >= range.$1 && angle < range.$2) {
        segment = i;
      }
    }

    // --- Ring from distance (exact DartsMind conditions) ---
    int ringMul = 1; // single
    String ringName;
    if (dist <= _zone2Hi && dist > _zone2Lo) {
      ringMul = 2;
      ringName = 'double';
    } else if (dist <= _zone3Hi && dist > _zone3Lo) {
      ringMul = 3;
      ringName = 'triple';
    } else if (dist < _zone3Lo) {
      ringName = 'inner_single';
    } else {
      ringName = 'outer_single';
    }

    final pts = ringMul == 1 ? segment : segment * ringMul;
    return DartScore(
        score: pts, segment: segment, ring: ringName, radius: dist, angle: angle);
  }
}

import 'dart:math';

/// Standard dartboard segment order (clockwise from top)
const List<int> segmentOrder = [
  20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5
];
const double segmentDeg = 360.0 / 20; // 18° per segment

/// Ring boundaries normalized to double ring center radius = 1.0
const List<(double, double, String)> rings = [
  (0.000, 0.040, "double_bull"),
  (0.040, 0.100, "single_bull"),
  (0.100, 0.570, "inner_single"),
  (0.570, 0.625, "triple"),
  (0.625, 0.930, "outer_single"),
  (0.930, 1.070, "double"),
];

/// Canonical dartboard space: center at (500, 500), calibration radius = 400
const double _c = 500.0;
const double _r = 400.0;

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
    if (ring == "double_bull") return "DBull (50)";
    if (ring == "single_bull") return "SBull (25)";
    if (ring == "triple") return "T$segment (${segment * 3})";
    if (ring == "double") return "D$segment (${segment * 2})";
    if (ring == "inner_single" || ring == "outer_single") {
      return "S$segment ($segment)";
    }
    return "Miss (0)";
  }
}

class DartScoringService {
  /// Perspective transform matrix (3x3)
  late List<List<double>> _h;

  DartScoringService(List<List<double>> calibPoints) {
    if (calibPoints.length < 4) {
      throw ArgumentError(
          'Need 4 calibration points, got ${calibPoints.length}');
    }
    final sorted = _sortCalibPoints(calibPoints.sublist(0, 4));
    _h = _computePerspectiveTransform(sorted);
  }

  /// Sort 4 calibration points into order: top, right, bottom, left
  List<List<double>> _sortCalibPoints(List<List<double>> pts) {
    final indexed = List.generate(4, (i) => i);

    // Sort by Y to find top (min y) and bottom (max y)
    indexed.sort((a, b) => pts[a][1].compareTo(pts[b][1]));
    final topIdx = indexed[0];
    final bottomIdx = indexed[3];

    // Remaining two: left (min x) and right (max x)
    final remaining = indexed.sublist(1, 3);
    int leftIdx, rightIdx;
    if (pts[remaining[0]][0] < pts[remaining[1]][0]) {
      leftIdx = remaining[0];
      rightIdx = remaining[1];
    } else {
      leftIdx = remaining[1];
      rightIdx = remaining[0];
    }

    return [pts[topIdx], pts[rightIdx], pts[bottomIdx], pts[leftIdx]];
  }

  /// Hartley normalization: compute similarity transform T such that
  /// points have centroid at origin and average distance sqrt(2)
  /// Returns (normalizedPoints, T as 3x3 matrix)
  (List<List<double>>, List<List<double>>) _hartleyNormalize(List<List<double>> pts) {
    double cx = 0, cy = 0;
    for (final p in pts) { cx += p[0]; cy += p[1]; }
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

  /// 3x3 matrix multiply
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

  /// Invert a 3x3 similarity matrix [[s,0,tx],[0,s,ty],[0,0,1]]
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

  /// Compute 3x3 perspective transform from src to dst using DLT with Hartley normalization
  List<List<double>> _computePerspectiveTransform(List<List<double>> src) {
    // Destination: canonical dartboard coordinates
    final dst = [
      [_c, _c - _r], // D20 — top
      [_c + _r, _c], // D6  — right
      [_c, _c + _r], // D3  — bottom
      [_c - _r, _c], // D11 — left
    ];

    // Hartley normalization for numerical stability
    final (normSrc, tSrc) = _hartleyNormalize(src);
    final (normDst, tDst) = _hartleyNormalize(dst);

    // Build the 8x8 matrix for DLT on normalized points
    final a = List.generate(8, (_) => List.filled(8, 0.0));
    final b = List.filled(8, 0.0);

    for (int i = 0; i < 4; i++) {
      final sx = normSrc[i][0], sy = normSrc[i][1];
      final dx = normDst[i][0], dy = normDst[i][1];

      a[i * 2][0] = sx;
      a[i * 2][1] = sy;
      a[i * 2][2] = 1;
      a[i * 2][3] = 0;
      a[i * 2][4] = 0;
      a[i * 2][5] = 0;
      a[i * 2][6] = -dx * sx;
      a[i * 2][7] = -dx * sy;
      b[i * 2] = dx;

      a[i * 2 + 1][0] = 0;
      a[i * 2 + 1][1] = 0;
      a[i * 2 + 1][2] = 0;
      a[i * 2 + 1][3] = sx;
      a[i * 2 + 1][4] = sy;
      a[i * 2 + 1][5] = 1;
      a[i * 2 + 1][6] = -dy * sx;
      a[i * 2 + 1][7] = -dy * sy;
      b[i * 2 + 1] = dy;
    }

    // Solve using Gaussian elimination
    final hVec = _solveLinearSystem(a, b);
    final hNorm = [
      [hVec[0], hVec[1], hVec[2]],
      [hVec[3], hVec[4], hVec[5]],
      [hVec[6], hVec[7], 1.0],
    ];

    // Denormalize: H = T_dst^(-1) * H_norm * T_src
    return _matMul3x3(_matMul3x3(_invertSimilarity(tDst), hNorm), tSrc);
  }

  List<double> _solveLinearSystem(List<List<double>> a, List<double> b) {
    final n = b.length;
    // Augmented matrix
    final aug =
        List.generate(n, (i) => List.generate(n + 1, (j) => j < n ? a[i][j] : b[i]));

    // Forward elimination with partial pivoting
    for (int col = 0; col < n; col++) {
      int maxRow = col;
      for (int row = col + 1; row < n; row++) {
        if (aug[row][col].abs() > aug[maxRow][col].abs()) {
          maxRow = row;
        }
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

    // Back substitution
    final x = List.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      x[i] = aug[i][n];
      for (int j = i + 1; j < n; j++) {
        x[i] -= aug[i][j] * x[j];
      }
      x[i] /= aug[i][i];
    }
    return x;
  }

  /// Transform normalized image point to canonical dartboard point
  List<double> _toBoard(double x, double y) {
    final w = _h[2][0] * x + _h[2][1] * y + _h[2][2];
    final bx = (_h[0][0] * x + _h[0][1] * y + _h[0][2]) / w;
    final by = (_h[1][0] * x + _h[1][1] * y + _h[1][2]) / w;
    return [bx, by];
  }

  /// Board point to (normalized radius, angle CW from top)
  /// Uses actual center and radius computed from transformed calibration points
  (double, double) _polar(double bx, double by) {
    final dx = bx - _c;
    final dy = by - _c;
    final r = sqrt(dx * dx + dy * dy) / _r;
    final angle = (atan2(dx, -dy) * 180.0 / pi) % 360;
    return (r, angle);
  }

  /// Angle (degrees CW from top) to segment number
  static int _segment(double angle) {
    final idx = ((angle + segmentDeg / 2) % 360 / segmentDeg).floor();
    return segmentOrder[idx];
  }

  /// Normalized radius to ring name
  static String _ring(double r) {
    for (final (rMin, rMax, name) in rings) {
      if (r >= rMin && r < rMax) return name;
    }
    return "miss";
  }

  /// Ring + segment to point value
  static int _points(String ring, int segment) {
    if (ring == "double_bull") return 50;
    if (ring == "single_bull") return 25;
    if (ring == "triple") return segment * 3;
    if (ring == "double") return segment * 2;
    if (ring == "inner_single" || ring == "outer_single") return segment;
    return 0;
  }

  /// Score a dart at normalized image position (x, y)
  DartScore score(double x, double y) {
    final board = _toBoard(x, y);
    final (r, angle) = _polar(board[0], board[1]);
    final segment = _segment(angle);
    final ring = _ring(r);
    final pts = _points(ring, segment);
    print('[Scoring] Dart (${x.toStringAsFixed(3)}, ${y.toStringAsFixed(3)}) -> board (${board[0].toStringAsFixed(1)}, ${board[1].toStringAsFixed(1)}) r=${r.toStringAsFixed(4)} angle=${angle.toStringAsFixed(1)} => $ring $segment');
    return DartScore(
      score: pts,
      segment: segment,
      ring: ring,
      radius: r,
      angle: angle,
    );
  }
}

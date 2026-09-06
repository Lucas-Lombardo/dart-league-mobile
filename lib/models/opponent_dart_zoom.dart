/// The "look here" point that rides on a dart announcement (score_updated,
/// pending_win, pending_bust) for the opponent's screen: where, in the video
/// frame the thrower is streaming, the dart just landed — the detected tip
/// for an AI dart, the centre of the named bed for a typed one.
///
/// [seq] increments on every announcement so the watching screen can tell a
/// new dart from a redraw even when two darts land on the same point.
class OpponentDartZoom {
  /// Normalized (0..1) coordinates in the received video frame.
  final double x;
  final double y;

  /// The score was typed, not detected: the point is a bed centre, not a tip.
  final bool manual;

  /// Backend notation of the dart ('T19', 'S20', 'D25', 'MISS').
  final String notation;

  /// 1-based position of the dart in the visit.
  final int dartIndex;

  final int seq;

  const OpponentDartZoom({
    required this.x,
    required this.y,
    required this.manual,
    required this.notation,
    required this.dartIndex,
    required this.seq,
  });

  /// Parses the `zoom` block of a socket payload. Null when absent or not a
  /// sane point — an old server strips the field, an old app never sends it.
  static ({double x, double y, bool manual})? parse(dynamic raw) {
    if (raw is! Map) return null;
    final x = _finite(raw['x']);
    final y = _finite(raw['y']);
    if (x == null || y == null) return null;
    if (x < 0 || x > 1 || y < 0 || y > 1) return null;
    return (x: x, y: y, manual: raw['manual'] == true);
  }

  static double? _finite(dynamic v) {
    if (v is num) {
      final d = v.toDouble();
      return d.isFinite ? d : null;
    }
    return null;
  }
}

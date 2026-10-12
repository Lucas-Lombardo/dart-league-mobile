// Where a player's darts actually landed — the boards of the stats pages.
//
// Coordinates travel exactly as the on-device scorer stored them: `radius`
// normalised on the outer edge of the double ring (1 = 170 mm), `angle` as
// atan2(dy, dx) with y pointing DOWN. Mapping them onto a drawn board is the
// widget's job (see ImpactBoard), because the board the app draws widens its
// rings to stay readable and is not to scale.

double _d(dynamic v) => v is num ? v.toDouble() : 0;

class DartImpact {
  final double radius;
  final double angle;

  /// The dart did its job: a treble on the scoring board, the checkout on the
  /// doubles board. Drawn in the accent colour.
  final bool good;

  const DartImpact({required this.radius, required this.angle, this.good = false});

  static DartImpact? fromJson(Map<String, dynamic> json, String goodKey) {
    final radius = json['radius'];
    final angle = json['angle'];
    // A dart without a position is not a dart this board can show.
    if (radius is! num || angle is! num) return null;
    return DartImpact(
      radius: _d(radius),
      angle: _d(angle),
      good: json[goodKey] == true,
    );
  }
}

/// The most recent located darts of a window, oldest first.
class StatsImpacts {
  /// Thrown while more than 170 remained. `good` = landed in a treble.
  final List<DartImpact> scoring;

  /// Thrown at a finishing double. `good` = checked out.
  final List<DartImpact> doubles;

  const StatsImpacts({this.scoring = const [], this.doubles = const []});

  bool get isEmpty => scoring.isEmpty && doubles.isEmpty;

  static List<DartImpact> _list(dynamic raw, String goodKey) => raw is List
      ? raw
            .whereType<Map<String, dynamic>>()
            .map((json) => DartImpact.fromJson(json, goodKey))
            .whereType<DartImpact>()
            .toList()
      : const [];

  static StatsImpacts? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final impacts = StatsImpacts(
      scoring: _list(json['scoring'], 'treble'),
      doubles: _list(json['doubles'], 'hit'),
    );
    return impacts.isEmpty ? null : impacts;
  }
}

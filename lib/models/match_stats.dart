// Models for GET /stats/match/:matchId — the end-of-match card.
//
// Covers the whole series when the match is a leg of one, because that is the
// match the player just finished. Cricket returns no dart figures at all
// (marks and points are not the same unit), which the screen renders as an
// absent card rather than a card full of dashes.

double? _dn(dynamic v) => v is num ? v.toDouble() : null;
int _i(dynamic v) => v is num ? v.toInt() : 0;
int? _in(dynamic v) => v is num ? v.toInt() : null;

class MatchStatsSide {
  final String username;
  final double? average;
  final int bestVisit;
  final int count180;
  final int doublesHit;
  final int doublesAttempted;
  final double? checkoutPct;
  final int? bestCheckout;

  const MatchStatsSide({
    this.username = '',
    this.average,
    this.bestVisit = 0,
    this.count180 = 0,
    this.doublesHit = 0,
    this.doublesAttempted = 0,
    this.checkoutPct,
    this.bestCheckout,
  });

  factory MatchStatsSide.fromJson(Map<String, dynamic> json) {
    return MatchStatsSide(
      username: json['username'] as String? ?? '',
      average: _dn(json['average']),
      bestVisit: _i(json['bestVisit']),
      count180: _i(json['count180']),
      doublesHit: _i(json['doublesHit']),
      doublesAttempted: _i(json['doublesAttempted']),
      checkoutPct: _dn(json['checkoutPct']),
      bestCheckout: _in(json['bestCheckout']),
    );
  }
}

class MatchStats {
  final String matchId;
  final String? seriesId;

  /// Legs aggregated — more than one only for a series.
  final int legs;
  final String gameMode;
  final MatchStatsSide me;
  final MatchStatsSide opponent;

  /// The player's three-dart average over the window, this match excluded.
  final double? windowAverage;
  final int windowDays;

  const MatchStats({
    required this.matchId,
    this.seriesId,
    this.legs = 0,
    this.gameMode = 'x01',
    required this.me,
    required this.opponent,
    this.windowAverage,
    this.windowDays = 30,
  });

  /// Nothing worth drawing: cricket, or a match whose darts were never stored.
  bool get isEmpty => legs == 0 || me.average == null;

  /// How this match compares with the player's recent form. Null when there is
  /// no history to compare against yet.
  double? get deltaVsWindow {
    final mine = me.average;
    final window = windowAverage;
    if (mine == null || window == null) return null;
    return double.parse((mine - window).toStringAsFixed(1));
  }

  factory MatchStats.fromJson(Map<String, dynamic> json) {
    return MatchStats(
      matchId: json['matchId'] as String? ?? '',
      seriesId: json['seriesId'] as String?,
      legs: _i(json['legs']),
      gameMode: json['gameMode'] as String? ?? 'x01',
      me: MatchStatsSide.fromJson(
        json['me'] is Map<String, dynamic> ? json['me'] : const {},
      ),
      opponent: MatchStatsSide.fromJson(
        json['opponent'] is Map<String, dynamic> ? json['opponent'] : const {},
      ),
      windowAverage: _dn(json['windowAverage']),
      windowDays: json['windowDays'] is num ? (json['windowDays'] as num).toInt() : 30,
    );
  }
}

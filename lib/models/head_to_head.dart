// Models for GET /stats/head-to-head/:opponentId.
//
// `record` counts ENCOUNTERS — a ranked best-of-3 is one, not three — while
// `legs` counts the X01 legs the dart figures were replayed from. The two are
// deliberately different numbers and the screen labels them apart.

double? _dn(dynamic v) => v is num ? v.toDouble() : null;
int _i(dynamic v) => v is num ? v.toInt() : 0;
int? _in(dynamic v) => v is num ? v.toInt() : null;

class HeadToHeadOpponent {
  final String id;
  final String username;
  final int elo;
  final String rank;
  final bool isPremium;

  const HeadToHeadOpponent({
    required this.id,
    required this.username,
    required this.elo,
    required this.rank,
    required this.isPremium,
  });

  factory HeadToHeadOpponent.fromJson(Map<String, dynamic> json) {
    return HeadToHeadOpponent(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      elo: _i(json['elo']),
      rank: json['rank'] as String? ?? 'bronze',
      isPremium: json['isPremium'] == true,
    );
  }
}

/// One side's totals across every leg the two played.
class HeadToHeadPlayer {
  final double? average;
  final int bestVisit;
  final int count180;

  /// Visits of 100 or more, 180s included.
  final int tons;
  final int? bestCheckout;
  final double? checkoutPct;
  final int legsWon;
  final int? bestLeg;

  const HeadToHeadPlayer({
    this.average,
    this.bestVisit = 0,
    this.count180 = 0,
    this.tons = 0,
    this.bestCheckout,
    this.checkoutPct,
    this.legsWon = 0,
    this.bestLeg,
  });

  factory HeadToHeadPlayer.fromJson(Map<String, dynamic> json) {
    return HeadToHeadPlayer(
      average: _dn(json['average']),
      bestVisit: _i(json['bestVisit']),
      count180: _i(json['count180']),
      tons: _i(json['tons']),
      bestCheckout: _in(json['bestCheckout']),
      checkoutPct: _dn(json['checkoutPct']),
      legsWon: _i(json['legsWon']),
      bestLeg: _in(json['bestLeg']),
    );
  }
}

class HeadToHeadEncounter {
  final String matchId;
  final String? seriesId;
  final String mode;
  final String gameMode;
  final DateTime? playedAt;

  /// Null when the match never resolved to a winner.
  final bool? won;
  final int? myLegs;
  final int? theirLegs;
  final double? myAverage;
  final double? theirAverage;
  final int eloChange;

  const HeadToHeadEncounter({
    required this.matchId,
    this.seriesId,
    required this.mode,
    required this.gameMode,
    this.playedAt,
    this.won,
    this.myLegs,
    this.theirLegs,
    this.myAverage,
    this.theirAverage,
    this.eloChange = 0,
  });

  bool get isCricket => gameMode.startsWith('cricket');

  factory HeadToHeadEncounter.fromJson(Map<String, dynamic> json) {
    return HeadToHeadEncounter(
      matchId: json['matchId'] as String? ?? '',
      seriesId: json['seriesId'] as String?,
      mode: json['mode'] as String? ?? 'ranked',
      gameMode: json['gameMode'] as String? ?? 'x01',
      playedAt: DateTime.tryParse(json['playedAt'] as String? ?? ''),
      won: json['won'] is bool ? json['won'] as bool : null,
      myLegs: _in(json['myLegs']),
      theirLegs: _in(json['theirLegs']),
      myAverage: _dn(json['myAverage']),
      theirAverage: _dn(json['theirAverage']),
      eloChange: _i(json['eloChange']),
    );
  }
}

class HeadToHeadRecord {
  final int wins;
  final int losses;
  final int encounters;

  const HeadToHeadRecord({this.wins = 0, this.losses = 0, this.encounters = 0});

  factory HeadToHeadRecord.fromJson(Map<String, dynamic> json) {
    return HeadToHeadRecord(
      wins: _i(json['wins']),
      losses: _i(json['losses']),
      encounters: _i(json['encounters']),
    );
  }
}

class HeadToHeadModeRecord {
  final String mode;
  final int wins;
  final int losses;

  const HeadToHeadModeRecord({
    required this.mode,
    required this.wins,
    required this.losses,
  });

  factory HeadToHeadModeRecord.fromJson(Map<String, dynamic> json) {
    return HeadToHeadModeRecord(
      mode: json['mode'] as String? ?? '',
      wins: _i(json['wins']),
      losses: _i(json['losses']),
    );
  }
}

class HeadToHead {
  final HeadToHeadOpponent opponent;
  final HeadToHeadRecord record;
  final List<HeadToHeadModeRecord> byMode;

  /// X01 legs behind the dart figures — not the same count as `record`.
  final int legs;
  final HeadToHeadPlayer me;
  final HeadToHeadPlayer them;
  final List<HeadToHeadEncounter> recent;

  const HeadToHead({
    required this.opponent,
    required this.record,
    this.byMode = const [],
    this.legs = 0,
    required this.me,
    required this.them,
    this.recent = const [],
  });

  bool get hasHistory => record.encounters > 0 || recent.isNotEmpty;

  factory HeadToHead.fromJson(Map<String, dynamic> json) {
    final byMode = json['byMode'];
    final recent = json['recent'];
    return HeadToHead(
      opponent: HeadToHeadOpponent.fromJson(
        json['opponent'] is Map<String, dynamic> ? json['opponent'] : const {},
      ),
      record: HeadToHeadRecord.fromJson(
        json['record'] is Map<String, dynamic> ? json['record'] : const {},
      ),
      byMode: byMode is List
          ? byMode
                .whereType<Map<String, dynamic>>()
                .map(HeadToHeadModeRecord.fromJson)
                .toList()
          : const [],
      legs: _i(json['legs']),
      me: HeadToHeadPlayer.fromJson(
        json['me'] is Map<String, dynamic> ? json['me'] : const {},
      ),
      them: HeadToHeadPlayer.fromJson(
        json['them'] is Map<String, dynamic> ? json['them'] : const {},
      ),
      recent: recent is List
          ? recent
                .whereType<Map<String, dynamic>>()
                .map(HeadToHeadEncounter.fromJson)
                .toList()
          : const [],
    );
  }
}

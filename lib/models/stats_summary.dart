// Models for GET /stats/summary.
//
// Every block is nullable, and a null block means the backend had nothing to
// report for the current filter — not zero. The screens render only the blocks
// they receive, which is what lets a brand-new account and a five-hundred-leg
// account share one layout with no special cases.

enum StatsPeriod { last7Days, last30Days, last90Days, all }

extension StatsPeriodX on StatsPeriod {
  int? get days => switch (this) {
    StatsPeriod.last7Days => 7,
    StatsPeriod.last30Days => 30,
    StatsPeriod.last90Days => 90,
    StatsPeriod.all => null,
  };

  DateTime? get from {
    final d = days;
    return d == null ? null : DateTime.now().subtract(Duration(days: d));
  }
}

enum MatchMode { ranked, friendly, tournament, placement }

extension MatchModeX on MatchMode {
  String get apiValue => switch (this) {
    MatchMode.ranked => 'ranked',
    MatchMode.friendly => 'friendly',
    MatchMode.tournament => 'tournament',
    // Matches against bots are stored as placement legs; the app calls them
    // "Bot" because that is what the player experienced.
    MatchMode.placement => 'placement',
  };
}

double _d(dynamic v) => v is num ? v.toDouble() : 0;
double? _dn(dynamic v) => v is num ? v.toDouble() : null;
int _i(dynamic v) => v is num ? v.toInt() : 0;
int? _in(dynamic v) => v is num ? v.toInt() : null;

class StatsSummary {
  final int legs;
  final StatsRecordLine? record;
  final StatsForm? form;
  final StatsScoring? scoring;
  final StatsFinishing? finishing;
  final StatsConsistency? consistency;
  final List<StatsRecord> records;

  const StatsSummary({
    required this.legs,
    this.record,
    this.form,
    this.scoring,
    this.finishing,
    this.consistency,
    this.records = const [],
  });

  bool get isEmpty => legs == 0;

  factory StatsSummary.fromJson(Map<String, dynamic> json) {
    return StatsSummary(
      legs: _i(json['legs']),
      record: json['record'] is Map<String, dynamic>
          ? StatsRecordLine.fromJson(json['record'])
          : null,
      form: json['form'] is Map<String, dynamic>
          ? StatsForm.fromJson(json['form'])
          : null,
      scoring: json['scoring'] is Map<String, dynamic>
          ? StatsScoring.fromJson(json['scoring'])
          : null,
      finishing: json['finishing'] is Map<String, dynamic>
          ? StatsFinishing.fromJson(json['finishing'])
          : null,
      consistency: json['consistency'] is Map<String, dynamic>
          ? StatsConsistency.fromJson(json['consistency'])
          : null,
      records: (json['records'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(StatsRecord.fromJson)
              .toList() ??
          const [],
    );
  }
}

class StatsRecordLine {
  final int wins;
  final int losses;
  final double winRate;

  const StatsRecordLine({
    required this.wins,
    required this.losses,
    required this.winRate,
  });

  factory StatsRecordLine.fromJson(Map<String, dynamic> json) => StatsRecordLine(
    wins: _i(json['wins']),
    losses: _i(json['losses']),
    winRate: _d(json['winRate']),
  );
}

class StatsForm {
  final double average;
  final double? previousAverage;
  final double? delta;
  final List<double> curve;
  final int sampleLegs;

  /// Legs still missing before a curve is worth drawing. Zero once it is.
  final int legsUntilCurve;

  const StatsForm({
    required this.average,
    this.previousAverage,
    this.delta,
    this.curve = const [],
    this.sampleLegs = 0,
    this.legsUntilCurve = 0,
  });

  bool get hasCurve => curve.length >= 2;

  factory StatsForm.fromJson(Map<String, dynamic> json) => StatsForm(
    average: _d(json['average']),
    previousAverage: _dn(json['previousAverage']),
    delta: _dn(json['delta']),
    curve: (json['curve'] as List?)?.whereType<num>().map((n) => n.toDouble()).toList() ?? const [],
    sampleLegs: _i(json['sampleLegs']),
    legsUntilCurve: _i(json['legsUntilCurve']),
  );
}

class StatsBucket {
  final String label;
  final int count;

  const StatsBucket({required this.label, required this.count});

  factory StatsBucket.fromJson(Map<String, dynamic> json) =>
      StatsBucket(label: json['label']?.toString() ?? '', count: _i(json['count']));
}

class StatsScoring {
  final double average;
  final double? first9;
  final double? trebleTwentyRate;
  final int bestVisit;
  final int totalVisits;
  final List<StatsBucket> buckets;

  const StatsScoring({
    required this.average,
    this.first9,
    this.trebleTwentyRate,
    this.bestVisit = 0,
    this.totalVisits = 0,
    this.buckets = const [],
  });

  factory StatsScoring.fromJson(Map<String, dynamic> json) => StatsScoring(
    average: _d(json['average']),
    first9: _dn(json['first9']),
    trebleTwentyRate: _dn(json['trebleTwentyRate']),
    bestVisit: _i(json['bestVisit']),
    totalVisits: _i(json['totalVisits']),
    buckets: (json['buckets'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(StatsBucket.fromJson)
            .toList() ??
        const [],
  );
}

/// One row of either breakdown: a checkout band or a single double.
class StatsRate {
  final String label;
  final int hits;
  final int attempts;
  final double pct;

  const StatsRate({
    required this.label,
    required this.hits,
    required this.attempts,
    required this.pct,
  });

  factory StatsRate.fromJson(Map<String, dynamic> json, String labelKey) => StatsRate(
    label: json[labelKey]?.toString() ?? '',
    hits: _i(json['hits']),
    attempts: _i(json['attempts']),
    pct: _d(json['pct']),
  );
}

class StatsFinishing {
  final double checkoutPct;
  final int hits;
  final int attempts;
  final int? best;
  final double? average;
  final List<StatsRate> bands;
  final List<StatsRate> doubles;

  const StatsFinishing({
    required this.checkoutPct,
    this.hits = 0,
    this.attempts = 0,
    this.best,
    this.average,
    this.bands = const [],
    this.doubles = const [],
  });

  factory StatsFinishing.fromJson(Map<String, dynamic> json) => StatsFinishing(
    checkoutPct: _d(json['checkoutPct']),
    hits: _i(json['hits']),
    attempts: _i(json['attempts']),
    best: _in(json['best']),
    average: _dn(json['average']),
    bands: (json['bands'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map((e) => StatsRate.fromJson(e, 'band'))
            .toList() ??
        const [],
    doubles: (json['doubles'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map((e) => StatsRate.fromJson(e, 'double'))
            .toList() ??
        const [],
  );
}

class StatsConsistency {
  final double? dartsToWinLeg;
  final int? bestLeg;
  final double? bustRate;
  final int legsWon;

  const StatsConsistency({
    this.dartsToWinLeg,
    this.bestLeg,
    this.bustRate,
    this.legsWon = 0,
  });

  factory StatsConsistency.fromJson(Map<String, dynamic> json) => StatsConsistency(
    dartsToWinLeg: _dn(json['dartsToWinLeg']),
    bestLeg: _in(json['bestLeg']),
    bustRate: _dn(json['bustRate']),
    legsWon: _i(json['legsWon']),
  );
}

enum StatsRecordKey { bestCheckout, bestLeg, bestLegAverage, longestWinStreak, unknown }

class StatsRecord {
  final StatsRecordKey key;
  final double value;
  final String matchId;
  final String? opponentUsername;
  final DateTime? playedAt;

  const StatsRecord({
    required this.key,
    required this.value,
    required this.matchId,
    this.opponentUsername,
    this.playedAt,
  });

  factory StatsRecord.fromJson(Map<String, dynamic> json) => StatsRecord(
    key: switch (json['key']) {
      'bestCheckout' => StatsRecordKey.bestCheckout,
      'bestLeg' => StatsRecordKey.bestLeg,
      'bestLegAverage' => StatsRecordKey.bestLegAverage,
      'longestWinStreak' => StatsRecordKey.longestWinStreak,
      _ => StatsRecordKey.unknown,
    },
    value: _d(json['value']),
    matchId: json['matchId']?.toString() ?? '',
    opponentUsername: json['opponentUsername']?.toString(),
    playedAt: DateTime.tryParse(json['playedAt']?.toString() ?? '')?.toLocal(),
  );
}

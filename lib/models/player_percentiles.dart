// Models for GET /stats/percentiles — the comparison screen.
//
// Every figure here is a STANDING among other players, not a personal number,
// so the model keeps the cohort it was measured against attached to it. A
// percentile without "against whom" is the kind of statistic that reads as a
// fact and isn't one.

double _d(dynamic v) => v is num ? v.toDouble() : 0;
int _i(dynamic v) => v is num ? v.toInt() : 0;

/// The five axes of the comparison. Unknown keys from a newer backend are
/// dropped rather than rendered raw.
enum PercentileMetric { average, checkoutPct, dartsToWinLeg, tonRate, bustRate }

PercentileMetric? _metricFrom(String? key) => switch (key) {
  'average' => PercentileMetric.average,
  'checkoutPct' => PercentileMetric.checkoutPct,
  'dartsToWinLeg' => PercentileMetric.dartsToWinLeg,
  'tonRate' => PercentileMetric.tonRate,
  'bustRate' => PercentileMetric.bustRate,
  _ => null,
};

/// The five figures the stats pages lead with: the average, and where it is
/// made and lost — the first nine darts, scoring above 170, finishing from 170
/// down, and the doubles. Unknown keys from a newer backend are dropped.
enum LevelMetric { average, first9, scoringAverage, finishingAverage, checkoutPct }

LevelMetric? _levelMetricFrom(String? key) => switch (key) {
  'average' => LevelMetric.average,
  'first9' => LevelMetric.first9,
  'scoringAverage' => LevelMetric.scoringAverage,
  'finishingAverage' => LevelMetric.finishingAverage,
  'checkoutPct' => LevelMetric.checkoutPct,
  _ => null,
};

/// Who the player is being compared against.
class PercentileCohort {
  /// True when the cohort is the player's own rank; false when it widened to
  /// everyone because too few players of that rank had played enough.
  final bool byRank;
  final String? rank;
  final int size;
  final int windowDays;
  final int minLegs;

  const PercentileCohort({
    required this.byRank,
    required this.rank,
    required this.size,
    required this.windowDays,
    required this.minLegs,
  });

  factory PercentileCohort.fromJson(Map<String, dynamic> json) {
    return PercentileCohort(
      byRank: json['scope'] == 'rank',
      rank: json['rank'] as String?,
      size: _i(json['size']),
      windowDays: _i(json['windowDays']),
      minLegs: _i(json['minLegs']),
    );
  }
}

class PercentileEntry {
  final PercentileMetric key;
  final double value;

  /// Share of the cohort this player beats, 0-100.
  final double percentile;

  /// The cohort's middle value — drawn as the reference marker.
  final double median;

  /// False for figures where a lower number is the better one (bust rate,
  /// darts to win a leg). The bar still fills to the right for "better".
  final bool higherIsBetter;

  const PercentileEntry({
    required this.key,
    required this.value,
    required this.percentile,
    required this.median,
    required this.higherIsBetter,
  });

  static PercentileEntry? fromJson(Map<String, dynamic> json) {
    final key = _metricFrom(json['key'] as String?);
    if (key == null) return null;
    return PercentileEntry(
      key: key,
      value: _d(json['value']),
      percentile: _d(json['percentile']),
      median: _d(json['median']),
      higherIsBetter: json['higherIsBetter'] != false,
    );
  }
}

/// One of the five figures: the player's own value, and where it sits in the
/// cohort when it can be placed there.
class LevelEntry {
  final LevelMetric key;
  final double value;

  /// Share of the cohort this player beats, 0-100. Null while the figure
  /// cannot be placed — too few legs, or too few players carrying it — in
  /// which case the value still stands on its own, without a bar.
  final double? percentile;
  final double? median;

  const LevelEntry({
    required this.key,
    required this.value,
    this.percentile,
    this.median,
  });

  /// "Better than N %", kept inside 1–99: nobody beats all of a cohort they
  /// are part of, and "better than 0 %" reads as an insult rather than a rank.
  int? get beatsPercent => percentile?.round().clamp(1, 99);

  static LevelEntry? fromJson(Map<String, dynamic> json) {
    final key = _levelMetricFrom(json['key'] as String?);
    if (key == null) return null;
    return LevelEntry(
      key: key,
      value: _d(json['value']),
      percentile: json['percentile'] is num ? _d(json['percentile']) : null,
      median: json['median'] is num ? _d(json['median']) : null,
    );
  }
}

class PlayerLevel {
  /// Standing across the five figures. Null until every one can be placed.
  final double? overall;
  final List<LevelEntry> metrics;

  const PlayerLevel({this.overall, this.metrics = const []});

  /// "Top N %" — never "top 0 %": a player who beats everyone is top 1 %.
  int? get topPercent {
    final value = overall;
    if (value == null) return null;
    return (100 - value).round().clamp(1, 100);
  }

  /// True when at least one figure is placed in the cohort.
  bool get isPlaced => metrics.any((m) => m.percentile != null);

  LevelEntry? entry(LevelMetric key) {
    for (final metric in metrics) {
      if (metric.key == key) return metric;
    }
    return null;
  }

  static PlayerLevel? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final raw = json['metrics'];
    final metrics = raw is List
        ? raw
              .whereType<Map<String, dynamic>>()
              .map(LevelEntry.fromJson)
              .whereType<LevelEntry>()
              .toList()
        : const <LevelEntry>[];
    if (metrics.isEmpty) return null;
    return PlayerLevel(
      overall: json['overall'] is num ? _d(json['overall']) : null,
      metrics: metrics,
    );
  }

  /// A backend that predates the five figures still sends two of them as
  /// radar axes. Rebuilding the level from those keeps one screen for both
  /// instead of a second layout nobody would see after the next deploy.
  static PlayerLevel? fromLegacy(List<PercentileEntry> axes, double? overall) {
    const kept = {
      PercentileMetric.average: LevelMetric.average,
      PercentileMetric.checkoutPct: LevelMetric.checkoutPct,
    };
    final metrics = [
      for (final axis in axes)
        if (kept[axis.key] != null)
          LevelEntry(
            key: kept[axis.key]!,
            value: axis.value,
            percentile: axis.percentile,
            median: axis.median,
          ),
    ];
    if (metrics.isEmpty) return null;
    return PlayerLevel(overall: overall, metrics: metrics);
  }
}

class PlayerPercentiles {
  final PercentileCohort cohort;

  /// False while the player has too few legs to be placed at all.
  final bool eligible;
  final int legs;
  final int legsUntilEligible;

  /// Share of the cohort beaten across every axis. Null when not eligible.
  final double? overall;
  final List<PercentileEntry> metrics;
  final PercentileMetric? strongest;
  final PercentileMetric? weakest;
  final DateTime? computedAt;

  /// The five headline figures. Present as soon as the player has thrown a
  /// dart in the window, placed or not.
  final PlayerLevel? level;

  const PlayerPercentiles({
    required this.cohort,
    required this.eligible,
    required this.legs,
    required this.legsUntilEligible,
    this.overall,
    this.metrics = const [],
    this.strongest,
    this.weakest,
    this.computedAt,
    this.level,
  });

  /// "Top N %" — the headline. 90th percentile means top 10 %.
  int? get topPercent {
    final value = overall;
    if (value == null) return null;
    // Never claim "top 0 %": a player who beats everyone is still top 1 %.
    return (100 - value).round().clamp(1, 100);
  }

  PercentileEntry? entry(PercentileMetric key) {
    for (final metric in metrics) {
      if (metric.key == key) return metric;
    }
    return null;
  }

  factory PlayerPercentiles.fromJson(Map<String, dynamic> json) {
    final rawMetrics = json['metrics'];
    final metrics = rawMetrics is List
        ? rawMetrics
              .whereType<Map<String, dynamic>>()
              .map(PercentileEntry.fromJson)
              .whereType<PercentileEntry>()
              .toList()
        : const <PercentileEntry>[];
    final overall = json['overall'] is num ? (json['overall'] as num).toDouble() : null;
    return PlayerPercentiles(
      cohort: PercentileCohort.fromJson(
        json['cohort'] is Map<String, dynamic> ? json['cohort'] : const {},
      ),
      eligible: json['eligible'] == true,
      legs: _i(json['legs']),
      legsUntilEligible: _i(json['legsUntilEligible']),
      overall: overall,
      metrics: metrics,
      level: PlayerLevel.fromJson(json['level']) ?? PlayerLevel.fromLegacy(metrics, overall),
      strongest: _metricFrom(json['strongest'] as String?),
      weakest: _metricFrom(json['weakest'] as String?),
      computedAt: DateTime.tryParse(json['computedAt'] as String? ?? ''),
    );
  }
}

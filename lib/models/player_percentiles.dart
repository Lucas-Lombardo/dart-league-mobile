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
    return PlayerPercentiles(
      cohort: PercentileCohort.fromJson(
        json['cohort'] is Map<String, dynamic> ? json['cohort'] : const {},
      ),
      eligible: json['eligible'] == true,
      legs: _i(json['legs']),
      legsUntilEligible: _i(json['legsUntilEligible']),
      overall: json['overall'] is num ? (json['overall'] as num).toDouble() : null,
      metrics: rawMetrics is List
          ? rawMetrics
                .whereType<Map<String, dynamic>>()
                .map(PercentileEntry.fromJson)
                .whereType<PercentileEntry>()
                .toList()
          : const [],
      strongest: _metricFrom(json['strongest'] as String?),
      weakest: _metricFrom(json['weakest'] as String?),
      computedAt: DateTime.tryParse(json['computedAt'] as String? ?? ''),
    );
  }
}

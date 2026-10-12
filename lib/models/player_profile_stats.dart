import 'player_percentiles.dart';
import 'stats_impacts.dart';
import 'stats_summary.dart';

/// GET /stats/profile/:userId — what another player's page shows beyond their
/// career record, all of it drawn from the comparison window.
class PlayerProfileStats {
  final PlayerPercentiles percentiles;
  final StatsImpacts? impacts;

  /// Per-double success, most played first.
  final List<StatsRate> doubles;

  const PlayerProfileStats({
    required this.percentiles,
    this.impacts,
    this.doubles = const [],
  });

  factory PlayerProfileStats.fromJson(Map<String, dynamic> json) {
    final doubles = json['doubles'];
    return PlayerProfileStats(
      percentiles: PlayerPercentiles.fromJson(
        json['percentiles'] is Map<String, dynamic> ? json['percentiles'] : const {},
      ),
      impacts: StatsImpacts.fromJson(json['impacts']),
      doubles: doubles is List
          ? doubles
                .whereType<Map<String, dynamic>>()
                .map((d) => StatsRate.fromJson(d, 'double'))
                .toList()
          : const [],
    );
  }
}

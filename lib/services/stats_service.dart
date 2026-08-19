import '../models/head_to_head.dart';
import '../models/match_stats.dart';
import '../models/player_percentiles.dart';
import '../models/stats_summary.dart';
import 'api_service.dart';

class StatsService {
  /// One request serves the whole Matches tab: the four sub-tabs are four views
  /// of this single response, so switching between them never hits the network.
  ///
  /// An empty [modes] means every mode — the backend treats a missing parameter
  /// the same way, so we simply omit it.
  static Future<StatsSummary> getSummary({
    required StatsPeriod period,
    required Set<MatchMode> modes,
  }) async {
    final params = <String>[];
    final from = period.from;
    if (from != null) params.add('from=${Uri.encodeComponent(from.toUtc().toIso8601String())}');
    if (modes.isNotEmpty) {
      params.add('modes=${modes.map((m) => m.apiValue).join(',')}');
    }
    final query = params.isEmpty ? '' : '?${params.join('&')}';

    final response = await ApiService.get('/stats/summary$query');
    if (response is Map<String, dynamic>) {
      return StatsSummary.fromJson(response);
    }
    throw Exception('Unexpected stats summary response');
  }

  /// Where the player stands among comparable players. Served from nightly
  /// snapshots, so it is cheap to call and does not move between two legs.
  static Future<PlayerPercentiles> getPercentiles() async {
    final response = await ApiService.get('/stats/percentiles');
    if (response is Map<String, dynamic>) {
      return PlayerPercentiles.fromJson(response);
    }
    throw Exception('Unexpected percentiles response');
  }

  /// The stats card shown when a match ends. Covers the whole series when the
  /// match is a leg of one.
  static Future<MatchStats> getMatchCard(String matchId) async {
    final response = await ApiService.get('/stats/match/$matchId');
    if (response is Map<String, dynamic>) {
      return MatchStats.fromJson(response);
    }
    throw Exception('Unexpected match stats response');
  }

  /// Everything the player and one opponent have done to each other.
  static Future<HeadToHead> getHeadToHead(String opponentId) async {
    final response = await ApiService.get('/stats/head-to-head/$opponentId');
    if (response is Map<String, dynamic>) {
      return HeadToHead.fromJson(response);
    }
    throw Exception('Unexpected head-to-head response');
  }
}

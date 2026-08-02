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
}

import 'api_service.dart';

class MatchService {
  static Future<Map<String, dynamic>> acceptMatchResult(
    String matchId,
    String playerId,
  ) async {
    final response = await ApiService.post(
      '/matches/$matchId/accept',
      {'playerId': playerId},
    );
    return response as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> disputeMatchResult(
    String matchId,
    String playerId,
    String reason,
  ) async {
    final response = await ApiService.post(
      '/matches/$matchId/dispute',
      {'playerId': playerId, 'reason': reason},
    );
    return response as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getActiveMatch(String userId) async {
    final response = await ApiService.get('/matches/active/$userId');
    return response as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getMatchDetail(String matchId) async {
    final response = await ApiService.get('/matches/$matchId');
    return response as Map<String, dynamic>;
  }
}

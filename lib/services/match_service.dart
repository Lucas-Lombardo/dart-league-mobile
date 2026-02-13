import 'api_service.dart';

class MatchService {
  static Future<Map<String, dynamic>> acceptMatchResult(
    String matchId,
    String playerId,
  ) async {
    try {
      final response = await ApiService.post(
        '/matches/$matchId/accept',
        {'playerId': playerId},
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> disputeMatchResult(
    String matchId,
    String playerId,
    String reason,
  ) async {
    try {
      final response = await ApiService.post(
        '/matches/$matchId/dispute',
        {'playerId': playerId, 'reason': reason},
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getActiveMatch(String userId) async {
    try {
      final response = await ApiService.get('/matches/active/$userId');
      return response as Map<String, dynamic>;
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getMatchDetail(String matchId) async {
    try {
      final response = await ApiService.get('/matches/$matchId');
      return response as Map<String, dynamic>;
    } catch (e) {
      rethrow;
    }
  }
}

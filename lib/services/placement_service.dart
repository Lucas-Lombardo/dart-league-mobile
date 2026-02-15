import 'api_service.dart';

class PlacementService {
  static Future<Map<String, dynamic>> getStatus() async {
    try {
      final response = await ApiService.get('/placement/status');
      return response as Map<String, dynamic>;
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> startMatch() async {
    try {
      final response = await ApiService.post('/placement/start', {});
      return response as Map<String, dynamic>;
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> triggerBotTurn(String matchId) async {
    try {
      final response = await ApiService.post(
        '/placement/bot-turn',
        {'matchId': matchId},
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> completeMatch(
    String matchId,
    String? winnerId, {
    int? player1Score,
  }) async {
    try {
      final body = <String, dynamic>{'matchId': matchId, 'winnerId': winnerId};
      if (player1Score != null) body['player1Score'] = player1Score;
      final response = await ApiService.post(
        '/placement/complete',
        body,
      );
      return response as Map<String, dynamic>;
    } catch (e) {
      rethrow;
    }
  }
}

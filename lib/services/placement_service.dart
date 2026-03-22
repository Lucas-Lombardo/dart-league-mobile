import 'api_service.dart';

class PlacementService {
  static Future<Map<String, dynamic>> getStatus() async {
    final response = await ApiService.get('/placement/status');
    if (response is Map<String, dynamic>) return response;
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> startMatch() async {
    final response = await ApiService.post('/placement/start', {});
    if (response is Map<String, dynamic>) return response;
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> triggerBotTurn(
    String matchId, {
    int? playerRoundScore,
    List<String>? playerRoundThrows,
  }) async {
    final body = <String, dynamic>{'matchId': matchId};
    if (playerRoundScore != null) body['playerRoundScore'] = playerRoundScore;
    if (playerRoundThrows != null) body['playerRoundThrows'] = playerRoundThrows;
    final response = await ApiService.post('/placement/bot-turn', body);
    if (response is Map<String, dynamic>) return response;
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> completeMatch(
    String matchId,
    String? winnerId, {
    int? player1Score,
  }) async {
    final body = <String, dynamic>{'matchId': matchId, 'winnerId': winnerId};
    if (player1Score != null) body['player1Score'] = player1Score;
    final response = await ApiService.post('/placement/complete', body);
    if (response is Map<String, dynamic>) return response;
    return <String, dynamic>{};
  }
}

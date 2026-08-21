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

  static Future<Map<String, dynamic>> getActiveMatch() async {
    final response = await ApiService.get('/placement/active');
    if (response is Map<String, dynamic>) return response;
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> triggerBotTurn(
    String matchId, {
    int? playerRoundScore,
    List<String>? playerRoundThrows,
    // A busted visit is posted with playerRoundScore = 0 and darts that scored,
    // which the server used to record as an ordinary zero-point round — making
    // every placement bust invisible to the bust and checkout stats. Saying so
    // outright removes the guesswork. Optional: a server that predates it
    // ignores the field and infers the same thing from the score and the darts.
    bool? playerBusted,
    // The same visit dart by dart, carrying what the AI read and where it read
    // it. Sent alongside playerRoundThrows, never instead of it: a server that
    // only knows the notations scores the visit exactly as before.
    List<Map<String, dynamic>>? playerRoundDarts,
  }) async {
    final body = <String, dynamic>{'matchId': matchId};
    if (playerRoundScore != null) body['playerRoundScore'] = playerRoundScore;
    if (playerRoundThrows != null) body['playerRoundThrows'] = playerRoundThrows;
    if (playerBusted != null) body['playerBusted'] = playerBusted;
    if (playerRoundDarts != null) body['playerRoundDarts'] = playerRoundDarts;
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

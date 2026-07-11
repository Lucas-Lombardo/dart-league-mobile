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
    if (response is Map<String, dynamic>) return response;
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> disputeMatchResult(
    String matchId,
    String playerId,
    String reason, {
    String? comment,
  }) async {
    final body = <String, dynamic>{'playerId': playerId, 'reason': reason};
    if (comment != null && comment.isNotEmpty) body['comment'] = comment;
    final response = await ApiService.post('/matches/$matchId/dispute', body);
    if (response is Map<String, dynamic>) return response;
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> getActiveMatch(String userId) async {
    final response = await ApiService.get('/matches/active/$userId');
    if (response is Map<String, dynamic>) return response;
    return <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> getMatchDetail(String matchId) async {
    final response = await ApiService.get('/matches/$matchId');
    if (response is Map<String, dynamic>) return response;
    return <String, dynamic>{};
  }
}

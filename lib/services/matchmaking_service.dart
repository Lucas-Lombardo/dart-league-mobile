import 'api_service.dart';

class MatchmakingService {
  static Future<Map<String, dynamic>> joinQueue(String userId) async {
    try {
      final response = await ApiService.post(
        '/matchmaking/join',
        {'userId': userId},
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> leaveQueue(String userId) async {
    try {
      await ApiService.delete('/matchmaking/leave?userId=$userId');
    } catch (e) {
      rethrow;
    }
  }
}

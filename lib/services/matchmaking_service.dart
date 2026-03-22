import 'api_service.dart';

class MatchmakingService {
  static Future<Map<String, dynamic>> joinQueue(String userId) async {
    return await ApiService.post('/matchmaking/join', {'userId': userId});
  }

  static Future<void> leaveQueue(String userId) async {
    await ApiService.delete('/matchmaking/leave?userId=$userId');
  }
}

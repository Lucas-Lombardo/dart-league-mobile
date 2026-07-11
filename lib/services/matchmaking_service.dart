import 'api_service.dart';
import 'socket_service.dart';

class MatchmakingService {
  static Future<Map<String, dynamic>> joinQueue(String userId) async {
    return await ApiService.post('/matchmaking/join', {
      'userId': userId,
      // BO3 opt-in: only declared when the connected server announced
      // supportsRankedBo3 (so an older backend never sees an unknown field —
      // its ValidationPipe runs with forbidNonWhitelisted and would 400).
      // The server pairs us into a BO3 series only when BOTH players sent it.
      if (SocketService.supportsRankedBo3) 'supportsRankedBo3': true,
    });
  }

  static Future<void> leaveQueue(String userId) async {
    await ApiService.delete('/matchmaking/leave?userId=$userId');
  }
}

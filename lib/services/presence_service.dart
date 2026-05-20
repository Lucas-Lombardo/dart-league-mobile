import 'api_service.dart';

class PresenceService {
  static Future<int?> ping() async {
    try {
      final result = await ApiService.post('/presence/ping', const {});
      if (result is Map && result['count'] is int) {
        return result['count'] as int;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> getOnlineCount() async {
    try {
      final result = await ApiService.get('/presence/online-count');
      if (result is Map && result['count'] is int) {
        return result['count'] as int;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

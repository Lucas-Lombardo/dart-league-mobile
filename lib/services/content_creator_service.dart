import 'api_service.dart';

class ContentCreatorService {
  static Future<Map<String, dynamic>> setCreatorCode(String code) async {
    final response = await ApiService.post('/content-creator/set', {'code': code});
    return response as Map<String, dynamic>;
  }

  static Future<void> clearCreatorCode() async {
    await ApiService.delete('/content-creator/clear');
  }

  static Future<Map<String, dynamic>?> getMyCreator() async {
    try {
      final response = await ApiService.get('/content-creator/mine');
      if (response == null) return null;
      if (response is Map<String, dynamic> && response.containsKey('code')) {
        return response;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}

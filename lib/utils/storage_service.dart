import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _tokenKey = 'jwt_token';
  static const String _languageKey = 'user_language';
  static const String _autoScoringKey = 'auto_scoring_enabled';

  static Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  static Future<void> deleteToken() async {
    await _storage.delete(key: _tokenKey);
  }

  static Future<void> saveLanguage(String languageCode) async {
    await _storage.write(key: _languageKey, value: languageCode);
  }

  static Future<String?> getLanguage() async {
    return await _storage.read(key: _languageKey);
  }

  static Future<void> deleteLanguage() async {
    await _storage.delete(key: _languageKey);
  }

  static Future<void> saveAutoScoring(bool enabled) async {
    await _storage.write(key: _autoScoringKey, value: enabled.toString());
  }

  static Future<bool> getAutoScoring() async {
    final value = await _storage.read(key: _autoScoringKey);
    // Default to true on first launch (no value stored yet)
    if (value == null) return true;
    return value == 'true';
  }
}

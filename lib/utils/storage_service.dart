import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _tokenKey = 'jwt_token';
  static const String _languageKey = 'user_language';

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
}

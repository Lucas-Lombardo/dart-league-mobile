import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _tokenKey = 'jwt_token';
  static const String _refreshTokenKey = 'refresh_token';
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

  static Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: _refreshTokenKey, value: token);
  }

  static Future<String?> getRefreshToken() async {
    return await _storage.read(key: _refreshTokenKey);
  }

  static Future<void> deleteRefreshToken() async {
    await _storage.delete(key: _refreshTokenKey);
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

  static const String _cameraZoomKey = 'camera_zoom';

  static Future<void> saveCameraZoom(double zoom) async {
    await _storage.write(key: _cameraZoomKey, value: zoom.toString());
  }

  static Future<double> getCameraZoom() async {
    final value = await _storage.read(key: _cameraZoomKey);
    if (value == null) return 1.0;
    return double.tryParse(value) ?? 1.0;
  }

  // The latest version for which the user dismissed the "update available"
  // banner. A newer published version differs from this, so the banner returns.
  static const String _dismissedUpdateVersionKey = 'dismissed_update_version';

  static Future<void> saveDismissedUpdateVersion(String version) async {
    await _storage.write(key: _dismissedUpdateVersionKey, value: version);
  }

  static Future<String?> getDismissedUpdateVersion() async {
    return await _storage.read(key: _dismissedUpdateVersionKey);
  }

  // Whether the voice caller announces visit scores / checkouts. Defaults on.
  static const String _callerEnabledKey = 'caller_enabled';

  static Future<void> saveCallerEnabled(bool enabled) async {
    await _storage.write(key: _callerEnabledKey, value: enabled.toString());
  }

  static Future<bool> getCallerEnabled() async {
    final value = await _storage.read(key: _callerEnabledKey);
    if (value == null) return true;
    return value == 'true';
  }
}

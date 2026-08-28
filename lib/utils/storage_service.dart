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

  // Per-category sound & haptics toggles (Settings > Sounds). The keys are
  // owned by DartSoundService/HapticService since the categories map 1:1 to
  // their play methods. Default on, like the caller.
  static Future<void> saveSoundEnabled(String key, bool enabled) async {
    await _storage.write(key: key, value: enabled.toString());
  }

  static Future<bool> getSoundEnabled(String key) async {
    final value = await _storage.read(key: key);
    if (value == null) return true;
    return value == 'true';
  }

  // Whether the user shares dartboard photos to train the detection AI
  // (Settings > "Help improve the AI"). Default on, like the sound toggles.
  static const String _datasetShareEnabledKey = 'dataset_share_enabled';

  static Future<void> saveDatasetShareEnabled(bool enabled) async {
    await _storage.write(key: _datasetShareEnabledKey, value: enabled.toString());
  }

  static Future<bool> getDatasetShareEnabled() async {
    final value = await _storage.read(key: _datasetShareEnabledKey);
    if (value == null) return true;
    return value == 'true';
  }

  // Whether to use the front (selfie) camera instead of the back one for the
  // dartboard feed. Remembered across screens and app launches so the last
  // choice sticks. Defaults off (back camera).
  static const String _useFrontCameraKey = 'use_front_camera';

  static Future<void> saveUseFrontCamera(bool useFront) async {
    await _storage.write(key: _useFrontCameraKey, value: useFront.toString());
  }

  static Future<bool> getUseFrontCamera() async {
    final value = await _storage.read(key: _useFrontCameraKey);
    if (value == null) return false;
    return value == 'true';
  }

  // Last bot-training setup (mode, format, rank) as a JSON string — restored
  // when the setup screen opens so replaying "your" match is zero taps.
  static const String _botMatchConfigKey = 'bot_match_config';

  static Future<void> saveBotMatchConfig(String configJson) async {
    await _storage.write(key: _botMatchConfigKey, value: configJson);
  }

  static Future<String?> getBotMatchConfig() async {
    return await _storage.read(key: _botMatchConfigKey);
  }

  // The AI-model rollout as the backend last described it, replayed at the
  // next launch: ModelSelector needs it before main() has done any network
  // call, and the version-config request only fires once the home screen asks.
  // Storing the RAW rollout rather than the resolved model keeps the draw
  // honest — the decision is re-made at startup, so a percentage change takes
  // effect without the install having to be told twice.
  static const String _aiModelChoiceKey = 'ai_model_choice';
  static const String _aiModelPercentKey = 'ai_model_rollout_percent';
  static const String _aiModelCapableOnlyKey = 'ai_model_capable_only';

  static Future<void> saveAiModelRollout({
    required String? model,
    required int percent,
    required bool capableOnly,
  }) async {
    await _storage.write(key: _aiModelChoiceKey, value: model ?? 'auto');
    await _storage.write(key: _aiModelPercentKey, value: percent.toString());
    await _storage.write(
        key: _aiModelCapableOnlyKey, value: capableOnly.toString());
  }

  static Future<String?> getAiModelChoice() async {
    return await _storage.read(key: _aiModelChoiceKey);
  }

  static Future<int> getAiModelRolloutPercent() async {
    final value = await _storage.read(key: _aiModelPercentKey);
    return int.tryParse(value ?? '') ?? 100;
  }

  static Future<bool> getAiModelCapableOnly() async {
    return (await _storage.read(key: _aiModelCapableOnlyKey)) == 'true';
  }

  // This install's stable draw for percentage rollouts (0-99). Written once,
  // then never again: a re-draw would move the install between models and mix
  // both into every per-model statistic.
  static const String _aiRolloutBucketKey = 'ai_rollout_bucket';

  static Future<void> saveAiRolloutBucket(int bucket) async {
    await _storage.write(key: _aiRolloutBucketKey, value: bucket.toString());
  }

  static Future<int?> getAiRolloutBucket() async {
    return int.tryParse(await _storage.read(key: _aiRolloutBucketKey) ?? '');
  }
}

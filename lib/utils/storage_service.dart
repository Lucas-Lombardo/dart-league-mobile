import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _tokenKey = 'jwt_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _languageKey = 'user_language';

  // The session tokens live here once read or written; the keychain is only
  // their backup. On 2026-10-10 a phone received a freshly refreshed token
  // (HTTP 201) and could not write it to the keychain: with the keychain as
  // the source of truth the next request carried the stale token, the app
  // signed the player out mid-match and the match was forfeited. A failed
  // write is now retried in the background and never changes what the app
  // sends.
  static String? _token;
  static bool _tokenLoaded = false;
  static String? _refreshToken;
  static bool _refreshTokenLoaded = false;
  static final Map<String, String?> _pendingWrites = {};
  static Timer? _persistRetry;
  static const Duration _persistRetryEvery = Duration(seconds: 20);

  /// Fired once per failed keychain write so the failure can be reported;
  /// the write itself is retried regardless.
  static void Function(String key, Object error)? onPersistFailure;

  static Future<void> saveToken(String token) async {
    _token = token;
    _tokenLoaded = true;
    await _persist(_tokenKey, token);
  }

  static Future<String?> getToken() async {
    if (_tokenLoaded) return _token;
    final value = await _readOrNull(_tokenKey);
    if (value == null) return null;
    _token = value;
    _tokenLoaded = true;
    return value;
  }

  static Future<void> deleteToken() async {
    _token = null;
    _tokenLoaded = true;
    await _persist(_tokenKey, null);
  }

  static Future<void> saveRefreshToken(String token) async {
    _refreshToken = token;
    _refreshTokenLoaded = true;
    await _persist(_refreshTokenKey, token);
  }

  static Future<String?> getRefreshToken() async {
    if (_refreshTokenLoaded) return _refreshToken;
    final value = await _readOrNull(_refreshTokenKey);
    if (value == null) return null;
    _refreshToken = value;
    _refreshTokenLoaded = true;
    return value;
  }

  static Future<void> deleteRefreshToken() async {
    _refreshToken = null;
    _refreshTokenLoaded = true;
    await _persist(_refreshTokenKey, null);
  }

  /// Whether a keychain write is still waiting to land (diagnostics).
  static bool get hasPendingPersist => _pendingWrites.isNotEmpty;

  /// Forgets the in-memory copies so the next read goes to the keychain.
  @visibleForTesting
  static void resetSessionCache() {
    _token = null;
    _tokenLoaded = false;
    _refreshToken = null;
    _refreshTokenLoaded = false;
    _pendingWrites.clear();
    _persistRetry?.cancel();
    _persistRetry = null;
  }

  // A read that throws (locked keychain, plugin hiccup) is treated as "not
  // there yet" without caching the miss: the next call tries again.
  static Future<String?> _readOrNull(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('StorageService: read of $key failed: $e');
      return null;
    }
  }

  static Future<void> _persist(String key, String? value) async {
    try {
      if (value == null) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
      _pendingWrites.remove(key);
      if (_pendingWrites.isEmpty) {
        _persistRetry?.cancel();
        _persistRetry = null;
      }
    } catch (e) {
      debugPrint('StorageService: write of $key failed, will retry: $e');
      _pendingWrites[key] = value;
      onPersistFailure?.call(key, e);
      _persistRetry ??= Timer.periodic(_persistRetryEvery, (_) => _retryPending());
    }
  }

  static Future<void> _retryPending() async {
    for (final entry in Map.of(_pendingWrites).entries) {
      // A newer value for the key removes it from the map on success, so a
      // retry can never put an older token back.
      if (!identical(_pendingWrites[entry.key], entry.value)) continue;
      await _persist(entry.key, entry.value);
    }
  }

  // The e-mail of the last successful sign-in, so the login form only ever
  // asks for the password again.
  static const String _rememberedEmailKey = 'remembered_email';

  static Future<void> saveRememberedEmail(String email) async {
    try {
      await _storage.write(key: _rememberedEmailKey, value: email.trim());
    } catch (e) {
      debugPrint('StorageService: could not remember e-mail: $e');
    }
  }

  static Future<String?> getRememberedEmail() async {
    return _readOrNull(_rememberedEmailKey);
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

  // Match proof: retention key → matchIds/seriesId registry (JSON), so a
  // result dispute filed after an app relaunch still finds its footage.
  static const String _matchProofRegistryKey = 'match_proof_registry';

  static Future<void> saveMatchProofRegistry(String json) async {
    await _storage.write(key: _matchProofRegistryKey, value: json);
  }

  static Future<String?> getMatchProofRegistry() async {
    return await _storage.read(key: _matchProofRegistryKey);
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

  // The measured heavy-model verdict for this Android phone (a
  // HeavyProbeVerdict, JSON-encoded). Persisted because the measurement
  // costs a model load; how long it stays valid is the verdict's business.
  static const String _aiHeavyProbeKey = 'ai_heavy_probe';

  static Future<void> saveAiHeavyProbe(String encodedVerdict) async {
    await _storage.write(key: _aiHeavyProbeKey, value: encodedVerdict);
  }

  static Future<String?> getAiHeavyProbe() async {
    return await _storage.read(key: _aiHeavyProbeKey);
  }
}

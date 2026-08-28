import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_update_info.dart';
import 'api_service.dart';
import 'dataset_capture_service.dart';
import 'model_selector.dart';
import 'placement_debug_capture_service.dart';

/// Asks the backend whether a newer app version is available for this install.
class AppUpdateService {
  /// Returns null on web, or on any error/offline — the update check must never
  /// block the app or wrongly prompt the user.
  static Future<AppUpdateInfo?> check() async {
    if (kIsWeb) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final platform = Platform.isIOS ? 'ios' : 'android';
      final version = Uri.encodeQueryComponent(info.version);
      final res = await ApiService.get(
        '/app/version-config?platform=$platform&version=$version',
        includeAuth: false,
      );
      if (res is Map<String, dynamic>) {
        final info = AppUpdateInfo.fromJson(res);
        // Arm/disarm the dataset capture for this session — this endpoint is
        // the flag's only transport, and it already runs once per launch.
        DatasetCaptureService.remoteEnabled = info.datasetCaptureEnabled;
        PlacementDebugCapture.remoteEnabled = info.placementDebugEnabled;
        // Same reasoning for the AI-model rollout: this call is its only
        // transport. It is persisted here and re-read by ModelSelector.init()
        // at the next launch, so a phone that is offline on launch still runs
        // the model it was last told to.
        await ModelSelector.applyRemoteConfig(
          model: info.aiModel,
          rolloutPercent: info.aiModelRolloutPercent,
          capableOnly: info.aiModelCapableOnly,
        );
        return info;
      }
      return null;
    } catch (e) {
      debugPrint('AppUpdateService.check failed: $e');
      return null;
    }
  }
}

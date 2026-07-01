import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:package_info_plus/package_info_plus.dart';

import '../models/app_update_info.dart';
import 'api_service.dart';

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
        return AppUpdateInfo.fromJson(res);
      }
      return null;
    } catch (e) {
      debugPrint('AppUpdateService.check failed: $e');
      return null;
    }
  }
}

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update_info.dart';
import '../services/app_update_service.dart';
import '../utils/storage_service.dart';

/// Drives the home-screen "update available" banner. Checks the backend once
/// per app session (non-blocking); the banner is shown only when an update is
/// available and the user hasn't already dismissed that exact version.
class AppUpdateProvider with ChangeNotifier {
  AppUpdateInfo? _info;
  String? _dismissedVersion;
  Future<void>? _checkFuture;

  AppUpdateInfo? get info => _info;
  String? get message => _info?.message;
  String? get latestVersion => _info?.latestVersion;

  bool get shouldShowBanner =>
      _info?.updateAvailable == true &&
      _info?.latestVersion != null &&
      _dismissedVersion != _info!.latestVersion;

  /// True when the backend refuses tournament entry for this app version.
  bool get tournamentUpdateRequired => _info?.tournamentUpdateRequired == true;

  /// Fire-and-forget; safe to call repeatedly (runs the network check once).
  /// Concurrent callers await the same in-flight check.
  Future<void> check() => _checkFuture ??= _doCheck();

  Future<void> _doCheck() async {
    _dismissedVersion = await StorageService.getDismissedUpdateVersion();
    final result = await AppUpdateService.check();
    if (result == null) return;
    _info = result;
    notifyListeners();
  }

  /// Ensures the version check ran, then reports the tournament gate. Used as
  /// a pre-check before registering — the backend enforces it regardless.
  Future<bool> requiresTournamentUpdate() async {
    await check();
    return tournamentUpdateRequired;
  }

  /// Hide the banner until a newer version is published.
  Future<void> dismiss() async {
    final v = _info?.latestVersion;
    if (v == null) return;
    _dismissedVersion = v;
    await StorageService.saveDismissedUpdateVersion(v);
    notifyListeners();
  }

  Future<void> openStore() async {
    final url = _info?.storeUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

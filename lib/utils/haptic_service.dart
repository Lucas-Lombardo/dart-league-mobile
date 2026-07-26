import 'package:flutter/services.dart';
import 'storage_service.dart';

class HapticService {
  static const _prefKey = 'haptics_enabled';

  static bool _enabled = true;

  static Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    await StorageService.saveSoundEnabled(_prefKey, enabled);
  }

  /// Called once at startup (main.dart), like DartCallerService.loadPreference.
  static Future<void> loadPreference() async {
    _enabled = await StorageService.getSoundEnabled(_prefKey);
  }

  static bool get isEnabled => _enabled;

  static void lightImpact() {
    if (_enabled) {
      HapticFeedback.lightImpact();
    }
  }

  static void mediumImpact() {
    if (_enabled) {
      HapticFeedback.mediumImpact();
    }
  }

  static void heavyImpact() {
    if (_enabled) {
      HapticFeedback.heavyImpact();
    }
  }

  static void selectionClick() {
    if (_enabled) {
      HapticFeedback.selectionClick();
    }
  }

  static void vibrate() {
    if (_enabled) {
      HapticFeedback.vibrate();
    }
  }
}

import 'package:flutter/services.dart';

class HapticService {
  static bool _enabled = true;

  static void setEnabled(bool enabled) {
    _enabled = enabled;
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

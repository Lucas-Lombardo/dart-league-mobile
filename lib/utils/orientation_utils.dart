import 'package:flutter/services.dart';

/// Helpers for per-screen orientation control. The app boots in portrait
/// (see main.dart), but game and camera-setup screens unlock landscape so
/// players who mount their phone sideways see a usable layout.
///
/// Uses a refcount so handoffs between landscape-capable screens (e.g.
/// camera setup → matchmaking → game) don't snap back to portrait
/// between routes — only the last screen to dispose locks back.
class OrientationUtils {
  static int _landscapeRefs = 0;

  static const _all = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  static const _portraitOnly = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ];

  static Future<void> allowAll() async {
    _landscapeRefs++;
    if (_landscapeRefs == 1) {
      await SystemChrome.setPreferredOrientations(_all);
    }
  }

  static Future<void> portraitOnly() async {
    if (_landscapeRefs > 0) _landscapeRefs--;
    if (_landscapeRefs == 0) {
      await SystemChrome.setPreferredOrientations(_portraitOnly);
    }
  }
}

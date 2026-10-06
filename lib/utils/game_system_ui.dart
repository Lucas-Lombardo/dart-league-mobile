import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Hides Android's status and navigation bars while a camera game is on
/// screen. In landscape the 3-button navigation bar docks on a side edge,
/// right over the score column (opponent's score, visit total, confirm
/// button) — reported 2026-10-02. A swipe from the edge brings the bars back
/// over the game for a few seconds, without moving the layout.
///
/// Native (MainActivity's `com.dartrivals/system_bars`), not
/// [SystemChrome.setEnabledSystemUIMode]: the app targets SDK 36, where
/// Android ignores Flutter's immersive modes — only WindowInsetsController
/// still hides the bars. iOS has no navigation bar and is left alone.
///
/// Refcounted like [OrientationUtils]: entering a match defers the previous
/// screen's dispose (~300 ms), so a game → game handoff must not flash the
/// bars back in between — only the last game screen to dispose shows them.
class GameSystemUi {
  static const _channel = MethodChannel('com.dartrivals/system_bars');
  static int _refs = 0;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static void enter() {
    if (!_supported) return;
    _refs++;
    if (_refs == 1) _setHidden(true);
  }

  static void exit() {
    if (!_supported) return;
    if (_refs > 0) _refs--;
    if (_refs == 0) _setHidden(false);
  }

  static Future<void> _setHidden(bool hidden) async {
    try {
      await _channel.invokeMethod('setHidden', {'hidden': hidden});
    } catch (e) {
      // Cosmetic only: the game layouts already keep clear of a bar that
      // stays up (see gameSideGutters).
      debugPrint('[GameSystemUi] setHidden($hidden) failed: $e');
    }
  }
}

/// Outer left/right margins of the landscape game layouts: 12, or the inset
/// on that edge when larger — the punch-hole camera, a navigation bar still
/// up despite [GameSystemUi] (split screen, freeform window), the iPhone's
/// notch or Dynamic Island. Bars revealed by a swipe are not insets: the
/// layout doesn't move under them.
({double left, double right}) gameSideGutters(BuildContext context) {
  final padding = MediaQuery.paddingOf(context);
  return (
    left: math.max(12, padding.left),
    right: math.max(12, padding.right),
  );
}

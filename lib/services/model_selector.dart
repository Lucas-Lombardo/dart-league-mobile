import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'detection_parsing.dart';

/// The AI scorer's model configuration: ONE model per device, picked once by
/// [init] at startup — no mid-match switching, no persisted speed profile.
///
/// Two sizes of the same DartsMind model are bundled, and they share a single
/// output contract — anchor head [1, 13, 21504], dart at class 8, normalized
/// boxes (read off both .tflite files, 2026-08-18). [currentLayout] is
/// therefore one const for both: pairing the "wrong" model with it costs
/// speed or accuracy, never scoring correctness.
class ModelSelector {
  ModelSelector._();

  /// DartsMind light model (3.9 MB) — acceptable everywhere, including
  /// low-RAM Androids on CPU. The pick whenever the device is weak, unknown,
  /// or the probe fails. iPhone 15 Pro: 56ms on CoreML (2026-08-10).
  static const String lightAsset = 'assets/models/dart-rival-ia-light.tflite';

  /// DartsMind heavy model (12.8 MB), the same architecture scaled up — more
  /// accurate, ~3× the weights. NOT benched per device: the capability
  /// thresholds below are heuristics, not measurements.
  static const String heavyAsset = 'assets/models/dart-rival-ia-heavy.tflite';

  /// Output contract shared by both bundled models (see class doc).
  static const DetectionLayout currentLayout = DetectionLayout.anchorDartLast;

  /// The model the app runs on THIS device. Stays [lightAsset] until [init]
  /// resolves — every load path sits behind user navigation (camera setup,
  /// match start), so in practice the probe from main() has long finished.
  static String get currentAsset => _currentAsset;
  static String _currentAsset = lightAsset;

  static bool _initialized = false;

  /// Android floor for the heavy model, in MB of physical RAM — meant as
  /// "nominal 6 GB and up". physicalRamSize lands under the marketing number
  /// (a "6 GB" phone reports ~5.6–5.9k MB), hence 5500 rather than 6144.
  static const int _androidHeavyRamMb = 5500;

  /// Pick light or heavy for this device. Called from main() before anything
  /// can loadModel; later calls are no-ops. A failed probe or an
  /// unrecognized device keeps [lightAsset] — safe on every phone.
  static Future<void> init() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    try {
      final plugin = DeviceInfoPlugin();
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await plugin.androidInfo;
          final heavy = !info.isLowRamDevice &&
              info.physicalRamSize >= _androidHeavyRamMb;
          _currentAsset = heavy ? heavyAsset : lightAsset;
          debugPrint('[ModelSelector] android ram=${info.physicalRamSize}MB '
              'lowRam=${info.isLowRamDevice} → $currentModelName');
          break;
        case TargetPlatform.iOS:
          final machine = (await plugin.iosInfo).utsname.machine;
          _currentAsset = _iosHeavyCapable(machine) ? heavyAsset : lightAsset;
          debugPrint(
              '[ModelSelector] ios machine=$machine → $currentModelName');
          break;
        default:
          break; // Desktop dev builds keep the light model.
      }
    } catch (e) {
      _currentAsset = lightAsset;
      debugPrint('[ModelSelector] device probe failed ($e) '
          '→ $currentModelName');
    }
  }

  /// iOS tiering off the hardware identifier ("iPhone14,2"): the major
  /// number tracks the chip generation, and 13 is the A14 line (iPhone 12 /
  /// iPad Air 4, 2020) — that generation and up takes the heavy model.
  /// Simulators report the host arch and count as capable. RAM is no proxy
  /// here: device_info_plus 13.x doesn't expose it on iOS, and the chip tier
  /// predicts inference speed better anyway.
  static bool _iosHeavyCapable(String machine) {
    if (machine == 'arm64' || machine == 'x86_64') return true; // simulator
    final m = RegExp(r'^(?:iPhone|iPad)(\d+),').firstMatch(machine);
    return m != null && int.parse(m.group(1)!) >= 13;
  }

  /// Model name without path/extension (what the iOS plugin expects).
  static String get currentModelName => modelNameOf(currentAsset);

  static String modelNameOf(String asset) =>
      asset.split('/').last.replaceAll('.tflite', '');
}

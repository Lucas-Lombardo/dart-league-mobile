/// The AI scorer's single-model configuration.
///
/// Until 2026-08-09 this was a two-model speed/accuracy ladder ported from
/// DartsMind (v7 "light" / v7s "heavy", mean-inference-time switching, a
/// persisted device speed profile). Decision (Lucas): v7 alone scores well
/// enough — the ladder, the speed profile and the 19MB v7s asset are gone,
/// and with them every mid-match model-switch failure mode (iOS CoreML
/// recompile freezes on hot devices, forceCpu poisoning, downgrade reload
/// wedges).
class ModelSelector {
  ModelSelector._();

  /// Original DartsMind light model (anchor head, [1,13,21504], 1024×1024
  /// input — same interface as the v6/v7 exports, detection_parsing
  /// dispatches on the shape).
  ///
  /// Reverted from v6 (2026-08-09): the v6/v7 trials scored worse in real
  /// matches than the original model. The plan is to return to a retrained
  /// YOLO26 (v7-class) model later — this constant (+ pubspec asset + native
  /// defaultModelOrder/asset-key fallbacks) is all that needs to flip.
  static const String currentAsset =
      'assets/models/dart-rival-ia-light.tflite';

  /// Model name without path/extension (what the iOS plugin expects).
  static String get currentModelName =>
      currentAsset.split('/').last.replaceAll('.tflite', '');
}

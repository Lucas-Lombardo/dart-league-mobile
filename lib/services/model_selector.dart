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

  /// v7 generation (YOLO26 end-to-end, [1,300,6] head — detection_parsing
  /// dispatches on the shape). Winner of the 6-model A/B campaign of 2026-08.
  static const String currentAsset =
      'assets/models/dartboard-v7_float16.tflite';

  /// Model name without path/extension (what the iOS plugin expects).
  static String get currentModelName =>
      currentAsset.split('/').last.replaceAll('.tflite', '');
}

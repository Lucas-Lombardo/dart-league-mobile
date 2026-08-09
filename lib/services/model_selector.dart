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

  /// v6 generation (YOLO11 anchor head, [1,13,21504] — detection_parsing
  /// dispatches on the shape, so both head formats stay supported).
  ///
  /// TEMPORARY revert from v7 (2026-08-09): the 09/08 leg analysis showed v7
  /// blind on wide framings and hallucinating duplicate p1 control points
  /// (34% of frames unscorable); v6 sees all 3 darts on the reference image.
  /// The plan is to return to a retrained YOLO26 (v7-class) model soon —
  /// this constant (+ pubspec asset + native defaultModelOrder/asset-key
  /// fallbacks) is all that needs to flip back.
  static const String currentAsset =
      'assets/models/dartboard-v6_float16.tflite';

  /// Model name without path/extension (what the iOS plugin expects).
  static String get currentModelName =>
      currentAsset.split('/').last.replaceAll('.tflite', '');
}

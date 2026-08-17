import 'detection_parsing.dart';

/// The AI scorer's single-model configuration.
///
/// Until 2026-08-09 this was a two-model speed/accuracy ladder ported from
/// DartsMind (v7 "light" / v7s "heavy", mean-inference-time switching, a
/// persisted device speed profile). Decision (Lucas): one model alone scores
/// well enough — the ladder, the speed profile and the 19MB v7s asset are
/// gone, and with them every mid-match model-switch failure mode (iOS CoreML
/// recompile freezes on hot devices, forceCpu poisoning, downgrade reload
/// wedges).
///
/// A model is a PAIR: the asset and its [DetectionLayout]. Swapping one
/// without the other is the failure this class exists to prevent — the two
/// bundled models disagree on which class index is the dart, and nothing at
/// runtime can tell them apart (see [DartClassIndex]).
class ModelSelector {
  ModelSelector._();

  /// dartboard-v10, int8 dynamic-range quantized YOLO26 (2.9 MB): end-to-end
  /// head [1, 300, 6], NMS baked in, dart at class 0. Validated on 441 unseen
  /// images: 7.83 calibration points per image at the 0.80 floor, 86% of
  /// images with all 8, 2.78 darts per image.
  ///
  /// SUPERSEDED and NO LONGER BUNDLED — kept as a constant because it is the
  /// only [DetectionLayout.e2eDartFirst] example we have. Bench 2026-08-13:
  /// dynamic-range int8 weights are a format no accelerator accepts, so both
  /// the iOS CoreML delegate (42/433 nodes) and the Android GPU delegate
  /// (12/433) dropped the graph on the CPU — 511ms per frame on a Pixel 8
  /// against 54ms for [lightAsset]. [v10FloatAsset] is the fix.
  static const String v10Asset = 'assets/models/dartboard-v10_int8dyn.tflite';

  /// dartboard-v10 re-exported float16 (5.0 MB) — the answer to the int8
  /// export's accelerator problem above. o2o head, but emitted in the ANCHOR
  /// tensor layout [1, 13, 21504] rather than [1, 300, 6], so
  /// detection_parsing dispatches it to parseOutputFloats + NMS (the head is
  /// already one-to-one, so that NMS pass is redundant work, not a
  /// correctness issue).
  ///
  /// Contract MEASURED by the bench's LAYOUT PROBE (2026-08-13), not assumed —
  /// the export carries no Ultralytics metadata, and the tensor shape reveals
  /// only the parser. On a 3-dart frame, dart-at-class-0 yields one detection
  /// per class p1..p8 plus 3 tips; dart-at-class-8 yields p1=3 plus 1 tip.
  /// Boxes are in canvas pixels: read as normalized they land ~1000 frame
  /// widths off screen and the model appears to detect NOTHING.
  ///
  /// Speed (2026-08-13): Pixel 8 66ms on the GPU delegate, which takes the
  /// whole graph (604/604 nodes); iPhone 15 Pro 106ms on XNNPACK, roughly 2×
  /// the shipped light model's 56ms — see [NativeInference.iosDelegate].
  static const String v10FloatAsset =
      'assets/models/dartboard-v10_o2o_float16.tflite';

  /// Same weights as [v10FloatAsset], with the two attention blocks' adjoint
  /// BATCH_MATMULs rewritten as an explicit TRANSPOSE + plain BATCH_MATMUL.
  ///
  /// The Android GPU delegate computes `BATCH_MATMUL` with `adjX=true` WRONG —
  /// measured on a Pixel 8, the q·kᵀ tensor comes back with 212% relative
  /// error while its input is still accurate to 6e-3, and the whole attention
  /// output is corrupted downstream. Nothing reports it: the delegate takes
  /// all 604 nodes and returns plausible numbers. The visible effect is that
  /// every calibration ceiling drops ~0.10 (0.977 → 0.87), which on some
  /// frames pushes a control point under its 0.80 floor, and on some devices
  /// lifts the dart channel over its 0.50 one — the phantom darts.
  ///
  /// Materializing the adjoint costs nothing: still one partition, 608/608
  /// nodes, 61ms on a Pixel 8 vs 64.6ms before. Ceiling deviation GPU vs CPU
  /// falls from 0.071-0.119 to 3e-4-6e-4 across the bench frames.
  /// Produced by autoscoreur/scripts/deadjoint_batchmatmul.py.
  static const String v10FloatGpuFixAsset =
      'assets/models/dartboard-v10_o2o_float16_gpufix.tflite';

  /// Original DartsMind light model (anchor head [1, 13, 21504], dart at
  /// class 8). Kept bundled so a replay can be scored under both models
  /// before v10 is trusted in ranked play — pair it with
  /// [DetectionLayout.anchorDartLast], never with the v10 layout.
  static const String lightAsset = 'assets/models/dart-rival-ia-light.tflite';

  /// The model the app actually runs.
  static const String currentAsset = v10FloatGpuFixAsset;
  static const DetectionLayout currentLayout =
      DetectionLayout.anchorPixelsDartFirst;

  /// Output contract of a bundled asset. The lookup is explicit rather than
  /// inferred: every export here emits 9 classes and two of the three share a
  /// tensor shape, so an asset parsed under the wrong layout produces a
  /// plausible-looking, completely wrong board.
  static DetectionLayout layoutForAsset(String asset) {
    switch (asset) {
      case lightAsset:
        return DetectionLayout.anchorDartLast;
      case v10Asset:
        return DetectionLayout.e2eDartFirst;
      default:
        return DetectionLayout.anchorPixelsDartFirst;
    }
  }

  /// Model name without path/extension (what the iOS plugin expects).
  static String get currentModelName => modelNameOf(currentAsset);

  static String modelNameOf(String asset) =>
      asset.split('/').last.replaceAll('.tflite', '');
}

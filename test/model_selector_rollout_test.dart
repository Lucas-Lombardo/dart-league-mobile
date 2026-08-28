import 'package:mobile/services/ai_model_telemetry.dart';
import 'package:mobile/services/detection_parsing.dart';
import 'package:mobile/services/model_selector.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rollout is a REMOTE OVERRIDE of a choice the app otherwise makes on its
/// own hardware, and the model it names decides how the output tensor is
/// PARSED. Both properties are load-bearing:
///
///  - every value the backend could send that this build cannot honour must
///    fall back to the device probe, never to "no model" and never to a model
///    the install does not carry;
///  - each model must keep its own layout, because pairing a model with the
///    wrong one raises no error anywhere — darts read as calibration points
///    and every score on the board is silently wrong.
void main() {
  _forceStickinessTests();

  group('rollout resolution', () {
    AiModel resolve({
      bool capable = true,
      int bucket = 0,
      String? model,
      int percent = 100,
      bool capableOnly = false,
    }) =>
        ModelSelector.debugResolve(
          capable: capable,
          bucket: bucket,
          model: model,
          rolloutPercent: percent,
          capableOnly: capableOnly,
        );

    test('no rollout keeps the device probe', () {
      expect(resolve(model: 'auto', capable: true).key, 'heavy');
      expect(resolve(model: 'auto', capable: false).key, 'light');
      expect(resolve(model: null, capable: false).key, 'light');
    });

    test('a model this build does not carry falls back to the probe', () {
      // The backend can name a model before every install ships with it; those
      // installs must keep scoring, not try to load a missing asset.
      expect(resolve(model: 'v99', capable: true).key, 'heavy');
      expect(resolve(model: '', capable: false).key, 'light');
    });

    test('a known model overrides the probe on both device tiers', () {
      expect(resolve(model: 'v13', capable: true).key, 'v13');
      expect(resolve(model: 'v13', capable: false).key, 'v13');
      expect(resolve(model: 'light', capable: true).key, 'light');
    });

    test('the bucket splits the population at the configured percent', () {
      // bucket < percent takes the override; the rest stay on the probe, and
      // that "rest" is the control group the comparison needs.
      expect(resolve(model: 'v13', percent: 50, bucket: 0).key, 'v13');
      expect(resolve(model: 'v13', percent: 50, bucket: 49).key, 'v13');
      expect(resolve(model: 'v13', percent: 50, bucket: 50).key, 'heavy');
      expect(resolve(model: 'v13', percent: 50, bucket: 99).key, 'heavy');
    });

    test('0% reaches nobody and 100% reaches everybody', () {
      expect(resolve(model: 'v13', percent: 0, bucket: 0).key, 'heavy');
      expect(resolve(model: 'v13', percent: 100, bucket: 99).key, 'v13');
    });

    test('an out-of-range percent is clamped, not trusted', () {
      expect(resolve(model: 'v13', percent: 200, bucket: 99).key, 'v13');
      expect(resolve(model: 'v13', percent: -10, bucket: 0).key, 'heavy');
    });

    test('capableOnly keeps weak phones on the probe', () {
      // The safety valve for a model that turns out expensive: the probe keeps
      // weak phones off heavy on purpose, and a rollout must be able to respect
      // that rather than undo it for the whole low end at once.
      expect(resolve(model: 'heavy', capableOnly: true, capable: false).key, 'light');
      expect(resolve(model: 'heavy', capableOnly: true, capable: true).key, 'heavy');
      expect(resolve(model: 'v13', capableOnly: true, capable: false).key, 'light');
    });
  });

  group('model registry', () {
    test('every model keeps the layout its own export needs', () {
      // Read off the .tflite files: light/heavy put the dart last with
      // normalized boxes, v13's o2o export puts it first in canvas pixels.
      expect(ModelSelector.light.layout, DetectionLayout.anchorDartLast);
      expect(ModelSelector.heavy.layout, DetectionLayout.anchorDartLast);
      expect(ModelSelector.v13.layout, DetectionLayout.anchorPixelsDartFirst);
    });

    test('keys match the wire names the backend sends and stores', () {
      expect(ModelSelector.all.map((m) => m.key), ['light', 'heavy', 'v13']);
    });

    test('bundles an asset per model, named after its key', () {
      for (final model in ModelSelector.all) {
        expect(model.asset, startsWith('assets/models/'));
        expect(model.asset, endsWith('.tflite'));
        expect(model.modelName, isNot(contains('/')));
      }
    });

    test('byKey only resolves models this build carries', () {
      expect(ModelSelector.byKey('v13'), ModelSelector.v13);
      expect(ModelSelector.byKey('auto'), isNull);
      expect(ModelSelector.byKey(null), isNull);
    });
  });

  group('telemetry counters', () {
    late AiModelTelemetry telemetry;

    setUp(() => telemetry = AiModelTelemetry());

    test('an engine failure is counted but is not a frame', () {
      telemetry.recordFrame(inferMs: null, calibrationPoints: 0, engineFailed: true);
      telemetry.recordFrame(inferMs: 40, calibrationPoints: 6, engineFailed: false);
      final snap = telemetry.debugSnapshot();
      expect(snap['engineFailures'], 1);
      expect(snap['frames'], 1);
      // A failed call measured nothing, so it must not drag the average down.
      expect(snap['inferMsSum'], 40);
    });

    test('only frames with 4+ control points count as "board seen"', () {
      telemetry.recordFrame(inferMs: 30, calibrationPoints: 3, engineFailed: false);
      telemetry.recordFrame(inferMs: 30, calibrationPoints: 4, engineFailed: false);
      expect(telemetry.debugSnapshot()['calibOkFrames'], 1);
      expect(telemetry.debugSnapshot()['frames'], 2);
    });

    test('edits split into corrections and darts the model never saw', () {
      telemetry.recordEdit(wasAiProposed: true);
      telemetry.recordEdit(wasAiProposed: false);
      telemetry.recordEdit(wasAiProposed: false);
      final snap = telemetry.debugSnapshot();
      expect(snap['dartsCorrected'], 1);
      expect(snap['dartsManual'], 2);
    });

    test('deleting a dart the model never proposed is not its failure', () {
      telemetry.recordRemoval(wasAiProposed: false);
      expect(telemetry.debugSnapshot()['dartsRemoved'], 0);
      telemetry.recordRemoval(wasAiProposed: true);
      expect(telemetry.debugSnapshot()['dartsRemoved'], 1);
    });

    test('percentiles come off the samples, not the running sum', () {
      for (final ms in [10, 20, 30, 40, 900]) {
        telemetry.recordFrame(inferMs: ms, calibrationPoints: 4, engineFailed: false);
      }
      final snap = telemetry.debugSnapshot();
      expect(snap['p50'], 30);
      expect(snap['p95'], 900);
    });
  });
}

/// A forced model must survive everything that lands after it.
///
/// On a cold Redmi 13C, ModelSelector.init()'s secure-storage reads took 4.6s
/// — long after the bench's 2s delay had forced its model. init() was already
/// past the `_initialized` guard, so it reassigned the model on the way out
/// and the 2026-08-28 Android run measured v13 on the GPU, heavy on the CPU,
/// and labelled both "v13". A bench that silently swaps its subject is worse
/// than no bench.
void _forceStickinessTests() {
  group('debugForceModel', () {
    tearDown(ModelSelector.debugClearForce);

    test('refuses a model this build does not carry', () {
      expect(ModelSelector.debugForceModel('v99'), isFalse);
      expect(ModelSelector.debugForceModel(''), isFalse);
    });

    test('selects the named model', () {
      expect(ModelSelector.debugForceModel('v13'), isTrue);
      expect(ModelSelector.currentModelKey, 'v13');
      expect(ModelSelector.currentLayout, DetectionLayout.anchorPixelsDartFirst);
    });

    test('a rollout arriving afterwards cannot override it', () async {
      ModelSelector.debugForceModel('v13');
      await ModelSelector.applyRemoteConfig(
        model: 'light',
        rolloutPercent: 100,
        capableOnly: false,
      );
      expect(ModelSelector.currentModelKey, 'v13');
    });

    test('the delegate follows the forced model, not the previous one', () {
      ModelSelector.debugForceModel('v13');
      expect(ModelSelector.currentIosDelegate, 'xnnpack');
      ModelSelector.debugForceModel('light');
      expect(ModelSelector.currentIosDelegate, 'auto');
    });
  });
}

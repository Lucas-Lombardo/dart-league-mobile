import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../services/dart_detection_service.dart';
import '../services/detection_parsing.dart';
import '../services/model_selector.dart';

/// On-device TFLite delegate bench (iOS + Android) — dev tool, never part
/// of the app.
///
/// 2026-08-28, all three bundled models, Redmi 13C (23108RN04Y, Helio G85 /
/// mt6768, Mali-G52 MC2, 7.6 GB, Android 15), thermal=0 throughout:
///            gpu-auto        cpu-forced
///   light    306ms [2925ms]   1658ms [256ms]
///   heavy    826ms [4827ms]   5246ms [482ms]
///   v13      290ms [3164ms]   1557ms [217ms]
/// The GPU delegate takes EVERY graph whole here — 608/608 nodes for v13,
/// 1078/1078 for light and heavy, one partition each, self-test 9/9 on all
/// three. Nothing like the v10 int8dyn case (12/433); fp16 is what the
/// delegate wants.
///
/// Two readings, and together they settle what the model actually costs:
///   - v13 is ~0.95x light and ~0.30x heavy, and that ratio holds on BOTH the
///     GPU (290/306/826) and the CPU (1557/1658/5246). A transfer-bound GPU
///     floor would have flattened the GPU column only; it didn't, so these are
///     real compute costs. Same ratios as iPhone CPU (112/140/360) and an
///     offline Mac CPU bench (59/68/203).
///   - the CPU column IS the silent-fallback cost, and for heavy on this phone
///     that is 5.2 SECONDS per frame — an unusable scorer, on the model this
///     device ships today (7.6 GB of RAM puts it over the 5500 MB bar, so the
///     probe calls it heavy-capable while its GPU is entry-level).
///
/// Unlike iOS, the gap here crosses a UX threshold rather than sitting under
/// the 250ms capture floor: heavy runs 1.2 analyses/s against v13's 3.4, and
/// the scoring gates are counted in FRAMES (_autoConfirmThreshold = 3,
/// _removalConfirmThreshold = 3, _phantomConfirmFrames = 5). A 3-frame
/// confirmation takes 2.5s on heavy and 0.9s on v13.
/// Delegates agree on all three: identical scores 8/8 frames (the 9th,
/// check_inference.jpg, still dies on the landscape RGBA overrun), tip
/// distance 0.1-0.2px, worst ceiling delta 0.0056.
///
/// GOTCHA, and it invalidated a whole run: ModelSelector.init()'s secure
/// storage reads took 4.6s on this cold phone, finishing LONG after the
/// bench's 2s delay had forced its model — and init() was already past its
/// `_initialized` guard, so it reassigned the model on the way out. The run
/// measured v13 on the GPU and heavy on the CPU, and labelled both v13. The
/// tell was in logcat all along ("FORCED to v13" followed by "using heavy"),
/// which is why that line is now worth grepping on every run. Fixed by
/// ModelSelector._forced; watch for it coming back if that flag is ever
/// refactored away.
/// A second tell, if the force is ever lost mid-run: the accuracy pass goes
/// to ZERO detections on every frame while the speed numbers stay plausible —
/// canvas-pixel boxes parsed as normalized land ~1000x outside the frame.
///
/// Xiaomi/HyperOS blocks `adb install` of a NEW package with
/// INSTALL_FAILED_USER_RESTRICTED (its "Install via USB" toggle needs a Mi
/// account and a SIM). Sideload the APK once from the phone's file manager;
/// after that `adb install -r` works, because the restriction only covers
/// first installs.
///
/// 2026-08-28, all three bundled models, iPhone 16,1 (15 Pro), one launch
/// each via BENCH_MODEL — median inference, load in brackets:
///           xnnpack        coreml         best      thermal
///   light   140ms [24ms]    56ms [2486ms]  coreml    2→2
///   heavy   360ms [65ms]   102ms [2940ms]  coreml    0→0
///   v13     112ms [27ms]   312ms [2611ms]  xnnpack   1→1
/// So v13's iosDelegate is pinned to 'xnnpack' (2.8x) while light and heavy
/// keep 'auto'/CoreML — the reason AiModel.iosDelegate is per-model at all.
/// Pinning the whole platform to xnnpack would be a 2.5x regression on light
/// and a 3.5x one on heavy.
///
/// Read the table as TWO comparisons, because they say opposite things:
///   - on the SAME delegate, v13 is far the cheapest graph: 112ms on CPU
///     against light's 140 and heavy's 360 (an offline CPU bench agrees:
///     59 / 68 / 203ms);
///   - on each model's BEST delegate, v13 stops winning, purely because
///     CoreML accelerates the DartsMind anchor models and REJECTS the o2o
///     head — 312ms, slower than the CPU, the signature of a delegate handing
///     most of the graph back. Not the int8 weight format this time (v13 is
///     fp16 like the others); an op in the o2o head is the remaining suspect.
///
/// What that means for shipping v13 on iOS, per device tier:
///   - capable iPhones (A14+, the ones running heavy): 112 vs 102ms — a wash
///     on latency, and the thermal states even favour heavy here (measured at
///     0 against v13's 1);
///   - weak iPhones (running light): 112 vs 56ms, i.e. 2x.
/// All three sit under the 250ms capture floor, so NONE of them changes the
/// scoring rate a player sees. The cost is heat: xnnpack is 4 CPU threads at
/// ~45% duty where CoreML is the Neural Engine (thermal audit 2026-08-10).
/// A CoreML-friendly re-export is therefore the highest-leverage iOS
/// follow-up by a distance — v13's CPU cost is already 3.2x under heavy's, so
/// a graph the ANE accepts should land well under 102ms.
///
/// Delegates agree on every model: identical scores 9/9 frames, tip distance
/// 0.0px, worst class-confidence delta 0.0071 (v13) / 0.0051 (heavy) /
/// 0.0009 (light) against a 0.01 target.
/// The LAYOUT PROBE re-confirmed v13's contract on device: dart=first +
/// canvasPixels gives p1..p8 ×1 with tip=3 on a 3-dart frame, dart=last gives
/// p1=2 with tip=1 — and both 'normalized' variants give nothing at all.
///
/// GOTCHA that cost a run: `flutter run` launches under LLDB and waits for the
/// Dart VM Service, which does not attach on this device — the app then sits
/// suspended and the bench never starts. The --dart-defines are compiled into
/// the binary, so the fix is to let flutter install the build, kill it, and
/// launch standalone:
///   xcrun devicectl device process launch --device UDID \
///     --terminate-existing com.llombardo.dartrivals
/// then pull Documents/delegate_bench_report.txt as below. Check the report's
/// first line names the model you meant — a stale report from the previous
/// run reads as a plausible result.
///
/// 2026-08-13, dartboard-v10_o2o_float16 — the float16 re-export, and the
/// answer to everything below. Pixel 8 gpu-auto 66ms (from 511ms) with
/// "Replacing 604 out of 604 node(s)" and a 1-partition GPU graph, self-test
/// 8/9 OK; cpu-forced 353ms. iPhone (thermal=1, cold) xnnpack 106ms vs coreml
/// 297ms — fp16 did NOT rescue CoreML, so iosDelegate stays 'xnnpack'; note
/// xnnpack measured 106ms at thermal=3 too, so that figure was never
/// throttle-inflated. Delegates agree 9/9 on iPhone (0.0px) but only 6/8 on
/// the Pixel, where the GPU really does run fp16 arithmetic — see the
/// _extract4CPs note in the ACCURACY section below.
/// The LAYOUT PROBE settled this export's contract, which "same as DartsMind"
/// only half-covered: anchor tensor [1, 13, 21504], but boxes in CANVAS
/// PIXELS and the dart at class 0. On a 3-dart frame dart=first yields
/// p1..p8 ×1 + tip=3, dart=last yields p1=3 + tip=1 — unambiguous.
///
/// 2026-08-13, dartboard-v10_int8dyn — the export is ACCELERATOR-HOSTILE on
/// both platforms, and the cause is the same on each: dynamic-range int8
/// weights are a format neither the CoreML nor the GPU delegate can take,
/// so both hand almost the whole graph back to the CPU.
///   iPhone de Lucas: xnnpack 106ms median (load 21ms) vs coreml 330ms
///     (load 634ms), whole run at thermal=3 so both are throttled but
///     comparable. CoreML delegated 42/433 nodes over 98 partitions — that
///     hand-off count IS the 3.1× gap. Scores identical 9/9, tips 0.1px.
///     NativeInference.iosDelegate flipped back to 'xnnpack'.
///   Pixel 8 (thermal=1 throughout): gpu-auto 511ms vs cpu-forced 461ms —
///     the GPU path is SLOWER than no GPU at all. Logcat says why:
///     "Replacing 12 out of 433 node(s) with delegate (TfLiteGpuDelegateV2)"
///     then XNNPACK picks up 388/422 of the rest, so gpu-auto is the CPU run
///     plus 3 pointless GPU round-trips. Scores identical 8/8, tips 0.1px
///     (check_inference.jpg still dies on the landscape RGBA overrun).
/// Against the shipped model this is a 2× iOS regression (light coreml 56ms
/// cool) and a 9.5× Android one (light gpu 54ms) — v10 needs a float16 (or
/// full-integer + setQuantizedModelsAllowed) re-export before it can ship,
/// then a re-bench. Nothing here says anything about v10's ACCURACY, which
/// this harness only ever compares delegate-vs-delegate.
///
/// 2026-08-10 results, dart-rival-ia-light: iPhone de Lucas
/// coreml 56ms vs xnnpack 133ms (71 vs 215 at thermal=2), 9/9 identical
/// scores; Pixel 8 gpu 54ms (self-test 9/9 OK) vs forced-cpu 426ms, 8/8
/// identical scores; Galaxy S21 Ultra (Adreno 660) gpu 57ms (self-test 9/9
/// OK) vs forced-cpu 643ms median / 1098ms max — the CPU block alone pushed
/// thermal 1→2. A silent GPU→CPU fallback costs 8-11× and is invisible
/// today: surfacing the effective delegate in telemetry is the follow-up.
///
/// Launched with:
///   flutter run --profile --dart-define=DELEGATE_BENCH=true \
///     --dart-define=BENCH_MODEL=v13
/// after UNCOMMENTING the assets/dev_bench entries in pubspec.yaml (they
/// stay commented so the ~2.3 MB never ships in a real build; the bench
/// aborts loudly when they're missing).
///
/// BENCH_MODEL ('heavy' | 'v13') forces the model for that launch;
/// omit it to bench whatever the device's own probe picks. One model per
/// launch, from a COOL phone each time — thermal state moves the numbers
/// more than the models do.
///
/// Why it exists: NativeInference.iosDelegate pinned 'xnnpack' on the
/// strength of a 2026-08-09 bench made on the (since removed) v7/YOLO26
/// graph. The delegate ranking is a property of the graph, so the current
/// model (dart-rival-ia-light) needs its own numbers (thermal audit
/// 2026-08-10 — at equal speed the Neural Engine heats far less than 4 CPU
/// threads at ~90% duty).
///
/// Two phases, all in ONE app launch (the plugin rebuilds the interpreter
/// whenever the `delegate` override changes — see NativeInferencePlugin.swift
/// loadModel):
///  A. SPEED — timed invokes on a real 720p frame; `inferenceMs` is the
///     native pure-invoke time. 2026-08-10 result: coreml ~56ms median vs
///     xnnpack ~133ms.
///  B. ACCURACY — the same REAL match frames (assets/dev_bench, dumped by
///     DebugFrameDumpService on 2026-08-09) analyzed under each delegate,
///     then parsed with the app's own pipeline; the report compares control
///     points, tip positions and dart scores between delegates. This is the
///     measured stand-in for "throw darts at a real board and look".
///
/// 'metal' is deliberately absent: its delegate build dropped the device
/// connection on the 2026-08-10 run, and it was already beaten (~980ms on
/// the old graph, slower than both candidates here).
class DelegateBench {
  DelegateBench._();

  // Dart-side prints never reach the devicectl console (only native NSLog
  // does), and flutter run's VM-service attach was flaky on this device —
  // so the report is also written to Documents/delegate_bench_report.txt
  // and pulled over USB:
  //   xcrun devicectl device copy from --device <udid> \
  //     --domain-type appDataContainer \
  //     --domain-identifier com.llombardo.dartrivals \
  //     --source Documents/delegate_bench_report.txt --destination out.txt
  static final List<String> _report = [];

  static void _log(String line) {
    debugPrint('[DelegateBench] $line');
    _report.add(line);
  }

  static Future<void> _writeReport() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/delegate_bench_report.txt');
      await file.writeAsString('${_report.join('\n')}\n', flush: true);
    } catch (e) {
      debugPrint('[DelegateBench] report write failed: $e');
    }
  }

  static const _channel = MethodChannel('com.dartrivals/native_inference');

  /// iOS: real delegate overrides of the plugin's loadModel. Android: the
  /// plugin has no delegate arg — 'gpu-auto' is the normal load (GPU with
  /// the check_inference self-test, silent CPU fallback), 'cpu-forced'
  /// rides rebuildEngine's forceCpuOnce so the next load builds CPU-only
  /// (4 threads) — measuring exactly what a silent fallback would cost.
  /// Which delegate the GPU load actually retained is only visible in
  /// logcat (tag NativeInference: self-test verdict / delegate build).
  static final List<String> _delegates = Platform.isAndroid
      ? ['gpu-auto', 'cpu-forced']
      : ['xnnpack', 'coreml'];
  static const _warmups = 3;
  static const _samples = 10;

  static const _realFrames = [
    'assets/dev_bench/f000039.jpg', // 0 darts
    'assets/dev_bench/f000091.jpg', // 0 darts
    'assets/dev_bench/f000141.jpg', // 1 dart
    'assets/dev_bench/f000147.jpg', // 1 dart
    'assets/dev_bench/f000168.jpg', // 2 darts
    'assets/dev_bench/f000213.jpg', // 2 darts
    'assets/dev_bench/f000234.jpg', // 3 darts
    'assets/dev_bench/f000283.jpg', // 3 darts
    'assets/models/check_inference.jpg', // Android self-test reference shot
  ];

  /// Which model to bench, from `--dart-define=BENCH_MODEL=<key>`
  /// ('heavy' | 'v13'). Empty = whatever the device's own probe
  /// selected, which is the historical behaviour.
  ///
  /// It exists because the interesting model is usually the one the device
  /// would NOT choose: a new model has to be measured on the low-end phone
  /// that will never be handed it by the probe, and a rollout must never be
  /// the way a bench selects its subject.
  ///
  /// ONE model per launch, on purpose. Chaining them would bench the
  /// last one on a hot phone — the thermal state moves more than the models
  /// do (light: 56ms cool vs 71ms at thermal=2).
  static const String _benchModel = String.fromEnvironment('BENCH_MODEL');

  static Future<void> run() async {
    // Let the engine/plugins finish booting; the app keeps starting normally.
    await Future.delayed(const Duration(seconds: 2));
    _report.clear();
    if (_benchModel.isNotEmpty && !ModelSelector.debugForceModel(_benchModel)) {
      // Loud, and it stops: silently benching a different model than the one
      // named is how a wrong number ends up quoted as fact for months.
      _log('ABORT: BENCH_MODEL="$_benchModel" is not a bundled model '
          '(${ModelSelector.all.map((m) => m.key).join(', ')}).');
      await _writeReport();
      return;
    }
    _log('===== START ===== '
        'model=${ModelSelector.currentModelName} '
        '(${_benchModel.isEmpty ? "device probe" : "forced"}) '
        'layout=${ModelSelector.currentLayout.id} '
        'shippedIosDelegate=${ModelSelector.currentIosDelegate} '
        'delegates=$_delegates');

    final speedSummaries = <String>[];
    final results = <String, List<ScoringResult?>>{};
    final decoded = await _decodeRealFrames();
    // Fail LOUDLY on a partial bundle instead of producing an
    // authoritative-looking verdict over 1-2 frames: the dev_bench assets
    // ship commented out in pubspec.yaml (so they never reach a real build)
    // and MUST be uncommented for a bench build.
    if (decoded.length < _realFrames.length) {
      _log('ABORT: only ${decoded.length}/${_realFrames.length} bench frames '
          'bundled — uncomment the assets/dev_bench entries in pubspec.yaml '
          'and rebuild.');
      await _writeReport();
      return;
    }

    // Speed frame: a REAL portrait frame — Android's RGBA analyze path
    // overruns on landscape inputs (index just past 1024×768×4, latent bug
    // in that near-dead path; the game rides analyzeYuv), which killed a
    // synthetic 1280×720 landscape frame on the Pixel 8 run. Timing is
    // data-independent, so a real frame measures the same thing.
    final first = decoded.first;
    final speedFrame = (rgba: first.rgba, w: first.w, h: first.h);

    for (final delegate in _delegates) {
      final line = await _benchSpeed(delegate, speedFrame);
      speedSummaries.add(line);
      // Accuracy pass rides the same load as the speed pass — the delegate
      // is still the loaded one here.
      results[delegate] = await _analyzeRealFrames(delegate, decoded);
      for (final f in decoded) {
        await _probeCeilings(delegate, f);
      }
      // Partial write after each delegate: a crash mid-bench still leaves
      // the completed blocks readable.
      await _writeReport();
      await Future.delayed(const Duration(seconds: 2));
    }

    // Rides the engine the last delegate left loaded — deliberately NOT its
    // own load, so no `load=` figure above is a "reusing" no-op.
    await _probeLayouts(decoded.first);

    _log('===== SPEED =====');
    for (final line in speedSummaries) {
      _log(line);
    }
    _log('===== ACCURACY =====');
    _compare(decoded, results[_delegates[0]]!, results[_delegates[1]]!);
    _compareCeilings();
    _log('===== DONE =====');
    await _writeReport();
  }

  // ---- Phase 0: which class order did this export use? ---------------------

  /// Parse ONE frame's raw output under EVERY [DetectionLayout] and print the
  /// class histogram of each. Nothing in a .tflite says whether the dart is
  /// class 0 or class 8 — both conventions emit 9 classes, and a mismatch
  /// raises no error anywhere, it just reads the double ring as darts and the
  /// darts as calibration points. A new export therefore has to be probed,
  /// and the answer is unmistakable: the correct layout puts ONE detection in
  /// each of p1..p8 (the wire intersections, always present) and 0-3 on
  /// 'tip'; the wrong one inverts that shape.
  ///
  /// Reads the histogram BEFORE _extract4CPs and the dart filter — those trim
  /// both layouts down to 4 control points and ≤3 tips, which would hide the
  /// very difference being measured.
  static Future<void> _probeLayouts(
      ({String name, Uint8List rgba, int w, int h}) frame) async {
    _log('===== LAYOUT PROBE (${frame.name}) =====');
    try {
      final response = await _channel.invokeMethod<Map>('analyze', {
        'rgba': frame.rgba,
        'width': frame.w,
        'height': frame.h,
        'isBgra': false,
      }).timeout(const Duration(seconds: 30));
      final aligned = Uint8List.fromList(response!['output'] as Uint8List);
      final floats = aligned.buffer.asFloat32List();
      final shape = deriveOutputShape(floats.length);
      final xScale = (response['xScale'] as num).toDouble();
      final yScale = (response['yScale'] as num).toDouble();
      _log('output ${floats.length} floats → shape $shape '
          '(${isEndToEndShape(shape) ? "end-to-end head, no NMS" : "anchor head + NMS"})');
      if (isEndToEndShape(shape)) return;

      // A 13×N float count is equally consistent with [1,13,N] (channels
      // first, what parseOutputFloats reads) and [1,N,13] (channels last,
      // what a TF SavedModel export often emits) — the count cannot tell
      // them apart, so print the per-channel MAX under both readings. The
      // true one is obvious: channels 0-3 are box geometry and 4-12 are
      // confidences in [0,1], so a correct reading shows a handful of
      // channels reaching ~1.0; the wrong one smears every channel to the
      // same range. Maxima far above 1.0 mean raw logits (no sigmoid),
      // which no threshold in the app would ever pass.
      final n = shape[2];
      String maxima(double Function(int c, int i) at) {
        final out = <String>[];
        for (int c = 0; c < 13; c++) {
          var m = double.negativeInfinity;
          for (int i = 0; i < n; i++) {
            final v = at(c, i);
            if (v > m) m = v;
          }
          out.add(m.toStringAsFixed(2));
        }
        return out.join(' ');
      }

      _log('  ch max as [1,13,$n]: ${maxima((c, i) => floats[n * c + i])}');
      _log('  ch max as [1,$n,13]: ${maxima((c, i) => floats[i * 13 + c])}');

      // Parse under every combination of the two axes the tensor keeps to
      // itself: which class is the dart, and what unit the boxes are in.
      // Exactly one should produce ~8 control points and 0-3 tips; the wrong
      // class order inverts that shape, and the wrong unit yields nothing at
      // all (every box fails the boundary check).
      for (final dart in DartClassIndex.values) {
        for (final units in BoxUnits.values) {
          final candidate = DetectionLayout(
            id: 'probe',
            dartClassIndex: dart,
            boxUnits: units,
            tipThreshold: 0.50,
            controlPointThreshold: kConfidenceThreshold,
          );
          final dets = parseModelOutput(floats, shape,
              xScale: xScale, yScale: yScale, layout: candidate);
          final hist = <String, int>{};
          for (final d in dets) {
            hist[d.className] = (hist[d.className] ?? 0) + 1;
          }
          final ordered = [
            for (final label in kDetectionLabels)
              if (hist[label] != null) '$label=${hist[label]}'
          ];
          _log('  dart=${dart.name} boxes=${units.name}: '
              '${dets.length} detections '
              '${ordered.isEmpty ? "(none)" : ordered.join(' ')}');
        }
      }
    } catch (e) {
      _log('layout probe failed ($e)');
    }
  }

  // ---- Phase 0b: per-class confidence ceilings, per delegate ---------------

  /// delegate -> frame -> the 9 per-class ceilings.
  static final Map<String, Map<String, List<double>>> _ceilings = {};

  /// The ceiling of a class is the max of its channel over every anchor — the
  /// single number `parseOutputFloats` actually thresholds. Comparing whole
  /// output tensors between delegates hides what matters here: a mean over
  /// 21504 anchors stays microscopic while the handful of anchors that fire
  /// move a lot, and it is exactly those that decide whether a calibration
  /// point clears its 0.80 floor or a dart clears its 0.50 one.
  ///
  /// Recorded while [delegate] is the loaded one, so it must be called inside
  /// the delegate loop and never after it.
  static Future<void> _probeCeilings(String delegate,
      ({String name, Uint8List rgba, int w, int h}) frame) async {
    try {
      final response = await _channel.invokeMethod<Map>('analyze', {
        'rgba': frame.rgba,
        'width': frame.w,
        'height': frame.h,
        'isBgra': false,
      }).timeout(const Duration(seconds: 30));
      final aligned = Uint8List.fromList(response!['output'] as Uint8List);
      final floats = aligned.buffer.asFloat32List();
      final shape = deriveOutputShape(floats.length);
      if (isEndToEndShape(shape)) return;
      final n = shape[2];
      final out = <double>[];
      for (var c = 4; c < shape[1]; c++) {
        var m = 0.0;
        final base = n * c;
        for (var i = 0; i < n; i++) {
          final v = floats[base + i];
          if (v > m) m = v;
        }
        out.add(m);
      }
      (_ceilings[delegate] ??= {})[frame.name] = out;
    } catch (e) {
      _log('$delegate ${frame.name}: ceiling probe failed ($e)');
    }
  }

  static void _compareCeilings() {
    final a = _ceilings[_delegates[0]] ?? const {};
    final b = _ceilings[_delegates[1]] ?? const {};
    _log('===== CEILINGS (${_delegates[0]} vs ${_delegates[1]}) =====');
    var worst = 0.0;
    var worstWhere = 'n/a';
    for (final name in a.keys) {
      final va = a[name]!;
      final vb = b[name];
      if (vb == null || vb.length != va.length) {
        _log('$name: INCOMPARABLE');
        continue;
      }
      var maxDiff = 0.0;
      var at = 0;
      for (var i = 0; i < va.length; i++) {
        final d = (va[i] - vb[i]).abs();
        if (d > maxDiff) {
          maxDiff = d;
          at = i;
        }
      }
      if (maxDiff > worst) {
        worst = maxDiff;
        worstWhere = '$name class$at';
      }
      String fmt(List<double> v) =>
          v.map((x) => x.toStringAsFixed(3)).join(' ');
      _log('$name\n'
          '  ${_delegates[0]}: ${fmt(va)}\n'
          '  ${_delegates[1]}: ${fmt(vb)}\n'
          '  maxdiff=${maxDiff.toStringAsFixed(4)} @class$at');
    }
    _log('CEILING VERDICT: max |delta| = ${worst.toStringAsFixed(4)} '
        '($worstWhere) — target <= 0.01');
  }

  // ---- Phase A: speed on a real frame --------------------------------------

  static Future<String> _benchSpeed(
      String delegate, ({Uint8List rgba, int w, int h}) frame) async {
    final thermalBefore = await _thermal();
    _log('--- $delegate (thermal=$thermalBefore) ---');

    final loadSw = Stopwatch()..start();
    try {
      final ok = await _loadDelegate(delegate);
      if (ok != true) return '$delegate: LOAD FAILED (returned $ok)';
    } catch (e) {
      return '$delegate: LOAD FAILED ($e)';
    }
    final loadMs = loadSw.elapsedMilliseconds;

    final times = <int>[];
    for (var i = 0; i < _warmups + _samples; i++) {
      try {
        final response = await _channel.invokeMethod<Map>('analyze', {
          'rgba': frame.rgba,
          'width': frame.w,
          'height': frame.h,
          'isBgra': false,
        }).timeout(const Duration(seconds: 30));
        final ms = (response?['inferenceMs'] as num?)?.toInt();
        if (ms == null) return '$delegate: analyze returned no inferenceMs';
        if (i >= _warmups) times.add(ms);
      } catch (e) {
        return '$delegate: analyze #$i FAILED ($e)';
      }
    }

    times.sort();
    final median = times[times.length ~/ 2];
    final mean = times.reduce((a, b) => a + b) / times.length;
    final thermalAfter = await _thermal();
    return '$delegate: median=${median}ms mean=${mean.toStringAsFixed(0)}ms '
        'min=${times.first}ms max=${times.last}ms load=${loadMs}ms '
        'thermal $thermalBefore→$thermalAfter';
  }

  /// Platform-specific model load for [delegate] (see [_delegates]).
  static Future<Object?> _loadDelegate(String delegate) async {
    if (!Platform.isAndroid) {
      // CoreML compiles the graph on first build — give it room.
      return _channel.invokeMethod('loadModel', {
        'modelName': ModelSelector.currentModelName,
        'delegate': delegate,
      }).timeout(const Duration(seconds: 120));
    }
    if (delegate == 'cpu-forced') {
      // forceCpuOnce: the NEXT load builds CPU-only (and drops the
      // "already loaded — reusing" shortcut).
      await _channel
          .invokeMethod('rebuildEngine')
          .timeout(const Duration(seconds: 5));
    }
    // Same extraction as NativeInference.loadModel, but ALWAYS rewritten —
    // the app's existsSync shortcut can serve a stale temp file.
    final asset = ModelSelector.currentAsset;
    final modelData = await rootBundle.load(asset);
    final tempDir = await getTemporaryDirectory();
    final modelFile = File('${tempDir.path}/${asset.split('/').last}');
    await modelFile.writeAsBytes(modelData.buffer.asUint8List(), flush: true);
    return _channel
        .invokeMethod('loadModelFile', modelFile.path)
        .timeout(const Duration(seconds: 120));
  }

  // ---- Phase B: accuracy on real match frames ------------------------------

  static Future<List<({String name, Uint8List rgba, int w, int h})>>
      _decodeRealFrames() async {
    final out = <({String name, Uint8List rgba, int w, int h})>[];
    for (final asset in _realFrames) {
      try {
        final bytes = await rootBundle.load(asset);
        final im = img.decodeJpg(bytes.buffer.asUint8List());
        if (im == null) {
          _log('$asset: decode failed, skipped');
          continue;
        }
        out.add((
          name: asset.split('/').last,
          rgba: im.getBytes(order: img.ChannelOrder.rgba),
          w: im.width,
          h: im.height,
        ));
      } catch (e) {
        _log('$asset: $e — skipped');
      }
    }
    _log('decoded ${out.length}/${_realFrames.length} real frames');
    return out;
  }

  static Future<List<ScoringResult?>> _analyzeRealFrames(
    String delegate,
    List<({String name, Uint8List rgba, int w, int h})> frames,
  ) async {
    // Fresh parser per delegate: its last-good-calibration cache must not
    // leak one delegate's calibration into the other's scoring.
    final parser = DartDetectionService(useNativeDecode: false);
    final out = <ScoringResult?>[];
    for (final f in frames) {
      try {
        final response = await _channel.invokeMethod<Map>('analyze', {
          'rgba': f.rgba,
          'width': f.w,
          'height': f.h,
          'isBgra': false,
        }).timeout(const Duration(seconds: 30));
        final outputBytes = response!['output'] as Uint8List;
        final aligned = Uint8List.fromList(outputBytes);
        out.add(parser.parseRawOutput(
          aligned.buffer.asFloat32List(),
          (response['xScale'] as num).toDouble(),
          (response['yScale'] as num).toDouble(),
          response['imageWidth'] as int,
          response['imageHeight'] as int,
        ));
      } catch (e) {
        _log('$delegate ${f.name}: analyze failed ($e)');
        out.add(null);
      }
    }
    parser.dispose();
    return out;
  }

  static void _compare(
    List<({String name, Uint8List rgba, int w, int h})> frames,
    List<ScoringResult?> a,
    List<ScoringResult?> b,
  ) {
    var identicalScores = 0;
    var comparable = 0;
    final tipDistances = <double>[];
    for (var i = 0; i < frames.length; i++) {
      final ra = a[i];
      final rb = b[i];
      final name = frames[i].name;
      if (ra == null || rb == null) {
        _log('$name: INCOMPARABLE (analyze failed)');
        continue;
      }
      comparable++;
      final calA = _classes(ra.calibrationPoints);
      final calB = _classes(rb.calibrationPoints);
      final calDist = _meanDistancePx(
          ra.calibrationPoints, rb.calibrationPoints, frames[i].w, frames[i].h);
      final tipDist = _meanDistancePx(
          ra.dartTips, rb.dartTips, frames[i].w, frames[i].h);
      if (tipDist != null) tipDistances.add(tipDist);
      final scoresA = ra.scores.map((s) => s.formatted).join(',');
      final scoresB = rb.scores.map((s) => s.formatted).join(',');
      // Compare the score MULTISET, not the list order: the two delegates
      // emit the same darts in a different row order often enough (4/9
      // frames on 2026-08-13) that an order-sensitive check reported DIFF
      // on visits both delegates scored identically. Nothing downstream
      // cares about the order within one frame — the visit total does.
      String sorted(ScoringResult r) =>
          (r.scores.map((s) => s.formatted).toList()..sort()).join(',');
      final sameScores = sorted(ra) == sorted(rb) &&
          ra.dartTips.length == rb.dartTips.length &&
          ra.totalScore == rb.totalScore;
      if (sameScores) identicalScores++;
      _log('$name: '
          '${sameScores ? (scoresA == scoresB ? "MATCH" : "MATCH(reordered)") : "DIFF"} | '
          'cal ${_delegates[0]}=$calA ${_delegates[1]}=$calB '
          'dist=${calDist?.toStringAsFixed(1) ?? "n/a"}px | '
          'tips ${ra.dartTips.length}vs${rb.dartTips.length} '
          'dist=${tipDist?.toStringAsFixed(1) ?? "n/a"}px | '
          'scores [$scoresA] vs [$scoresB] '
          '(total ${ra.totalScore} vs ${rb.totalScore})');
    }
    final meanTipDist = tipDistances.isEmpty
        ? 'n/a'
        : (tipDistances.reduce((x, y) => x + y) / tipDistances.length)
            .toStringAsFixed(1);
    _log('VERDICT: identical scores on '
        '$identicalScores/$comparable frames, mean tip distance '
        '${meanTipDist}px');
  }

  static String _classes(List<Detection> dets) {
    final names = dets.map((d) => d.className).toList()..sort();
    return names.join('+');
  }

  /// Mean distance (px) between same-class detections of the two results;
  /// null when nothing matches. Tips (all same class) pair greedily by
  /// nearest neighbour.
  static double? _meanDistancePx(
      List<Detection> a, List<Detection> b, int w, int h) {
    if (a.isEmpty || b.isEmpty) return null;
    final remaining = List<Detection>.of(b);
    final dists = <double>[];
    for (final da in a) {
      Detection? best;
      var bestDist = double.infinity;
      for (final db in remaining) {
        if (db.className != da.className) continue;
        final dx = (da.x - db.x) * w;
        final dy = (da.y - db.y) * h;
        final d = sqrt(dx * dx + dy * dy);
        if (d < bestDist) {
          bestDist = d;
          best = db;
        }
      }
      if (best != null) {
        remaining.remove(best);
        dists.add(bestDist);
      }
    }
    if (dists.isEmpty) return null;
    return dists.reduce((x, y) => x + y) / dists.length;
  }

  /// Raw ProcessInfo.thermalState (0 nominal … 3 critical); -1 on failure.
  static Future<int> _thermal() async {
    try {
      final raw = await _channel
          .invokeMethod<int>('thermalStatus')
          .timeout(const Duration(seconds: 2));
      return raw ?? -1;
    } catch (_) {
      return -1;
    }
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'model_selector.dart';

/// What the phone measured while one model was scoring, so two models can be
/// compared on real matches instead of on a bench.
///
/// The scorer runs entirely on the device: the backend never sees a frame, and
/// the only things that separate a good model from a bad one — how long a
/// frame takes, whether the board was found at all, how often the player had
/// to fix a dart — exist nowhere else. This is the channel that carries them.
///
/// Three rules shape it:
///
/// - **Never get in the way.** Counting is a handful of integer increments per
///   frame; the flush is fire-and-forget, off the hot path, and swallows every
///   error. A model comparison must not be able to cost a match.
/// - **Report what RAN**, not what was configured. The model key comes from
///   [ModelSelector.current] at flush time, so an install that ignored the
///   rollout (a key it doesn't carry, a bucket it missed) lands in the right
///   column instead of poisoning the other one.
/// - **Rows are additive.** A long match flushes several; every aggregate on
///   the admin side is a SUM. That is why latency travels as sum+count and not
///   as an average.
class AiModelTelemetry {
  AiModelTelemetry();

  /// Flush once a session has this many frames behind it. At ~5fps that is a
  /// couple of visits — often enough that a killed app loses little, rare
  /// enough that it is a handful of calls per match.
  static const int _flushEveryFrames = 600;

  /// Latency samples kept for the percentiles. A session flushes long before
  /// this, and the cap only matters if one somehow doesn't: it bounds the
  /// memory a runaway session can hold.
  static const int _maxSamples = 4000;

  /// Set false in tests, or to stop reporting entirely.
  static bool enabled = true;

  final List<int> _inferMs = [];
  int _frames = 0;
  int _inferMsSum = 0;
  int _engineFailures = 0;
  int _calibOkFrames = 0;
  int _dartsAutoScored = 0;
  int _dartsCorrected = 0;
  int _dartsRemoved = 0;
  int _dartsManual = 0;
  int _autoConfirms = 0;

  /// Where the AI is running, and in which leg. A session with neither still
  /// reports (it is real AI usage), it just cannot be joined to the server's
  /// own record of the same darts.
  String? _context;
  String? _matchId;

  /// Point the counters at a (mode, leg) pair.
  ///
  /// A BO3 series keeps ONE scorer alive across several legs, so this is
  /// called again whenever the leg changes — and the previous leg's counters
  /// are flushed first, because a row that straddles two legs joins to
  /// neither. [flush] builds its payload synchronously before its first
  /// await, so the fields can be reassigned on the next line.
  void bind({String? context, String? matchId}) {
    if (context == _context && matchId == _matchId) return;
    unawaited(flush());
    _context = context;
    _matchId = matchId;
  }

  /// Engine failures alone are worth a row: a model whose delegate wedges on
  /// every call analyzes zero frames, and that is exactly the finding that
  /// would disqualify it. Everything else follows a frame.
  bool get _hasData => _frames > 0 || _engineFailures > 0;

  /// One analyzed frame. [inferMs] is the native invoke time (null when the
  /// engine failed), [calibrationPoints] how many control points came back —
  /// 4 is what a score needs.
  void recordFrame({
    required int? inferMs,
    required int calibrationPoints,
    required bool engineFailed,
  }) {
    if (!enabled) return;
    if (engineFailed) {
      _engineFailures++;
      return; // A failed call measured nothing: it is not a frame.
    }
    _frames++;
    if (inferMs != null && inferMs >= 0) {
      _inferMsSum += inferMs;
      if (_inferMs.length < _maxSamples) _inferMs.add(inferMs);
    }
    if (calibrationPoints >= 4) _calibOkFrames++;
    if (_frames >= _flushEveryFrames) unawaited(flush());
  }

  /// The model put a dart in a slot by itself.
  void recordAutoScored() {
    if (enabled) _dartsAutoScored++;
  }

  /// The player edited a slot. [wasAiProposed] separates the two failure
  /// shapes that look identical from the outside: fixing what the model said
  /// (wrong value) versus typing a dart into an empty slot (never saw it).
  void recordEdit({required bool wasAiProposed}) {
    if (!enabled) return;
    if (wasAiProposed) {
      _dartsCorrected++;
    } else {
      _dartsManual++;
    }
  }

  /// The player deleted a dart the model had proposed — a false positive.
  void recordRemoval({required bool wasAiProposed}) {
    if (enabled && wasAiProposed) _dartsRemoved++;
  }

  /// The model closed a visit on its own (board seen empty).
  void recordAutoConfirm() {
    if (enabled) _autoConfirms++;
  }

  /// Send what has accumulated and start clean.
  ///
  /// The counters are reset BEFORE the request so a slow or failing POST
  /// cannot double-count into the next flush; a lost row is the accepted cost.
  Future<void> flush() async {
    if (!enabled || !_hasData) return;
    final payload = <String, dynamic>{
      'model': ModelSelector.currentModelKey,
      if (_context != null) 'context': _context,
      if (_matchId != null) 'matchId': _matchId,
      'framesAnalyzed': _frames,
      'inferMsSum': _inferMsSum,
      if (_inferMs.isNotEmpty) 'inferMsP50': _percentile(0.50),
      if (_inferMs.isNotEmpty) 'inferMsP95': _percentile(0.95),
      if (_inferMs.isNotEmpty) 'inferMsMax': _inferMs.reduce((a, b) => a > b ? a : b),
      'engineFailures': _engineFailures,
      'calibOkFrames': _calibOkFrames,
      'dartsAutoScored': _dartsAutoScored,
      'dartsCorrected': _dartsCorrected,
      'dartsRemoved': _dartsRemoved,
      'dartsManual': _dartsManual,
      'autoConfirms': _autoConfirms,
    };
    _reset();

    // Nothing here is worth a retry, so a failed send is dropped with a line
    // in the log.
    try {
      await ApiService.post('/ai-models/session', payload);
    } catch (e) {
      debugPrint('[AiModelTelemetry] flush failed: $e');
    }
  }

  int _percentile(double p) {
    final sorted = [..._inferMs]..sort();
    final index = ((sorted.length - 1) * p).round().clamp(0, sorted.length - 1);
    return sorted[index];
  }

  void _reset() {
    _inferMs.clear();
    _frames = 0;
    _inferMsSum = 0;
    _engineFailures = 0;
    _calibOkFrames = 0;
    _dartsAutoScored = 0;
    _dartsCorrected = 0;
    _dartsRemoved = 0;
    _dartsManual = 0;
    _autoConfirms = 0;
  }

  @visibleForTesting
  Map<String, dynamic> debugSnapshot() => {
        'frames': _frames,
        'inferMsSum': _inferMsSum,
        'engineFailures': _engineFailures,
        'calibOkFrames': _calibOkFrames,
        'dartsAutoScored': _dartsAutoScored,
        'dartsCorrected': _dartsCorrected,
        'dartsRemoved': _dartsRemoved,
        'dartsManual': _dartsManual,
        'autoConfirms': _autoConfirms,
        'p50': _inferMs.isEmpty ? null : _percentile(0.50),
        'p95': _inferMs.isEmpty ? null : _percentile(0.95),
      };
}

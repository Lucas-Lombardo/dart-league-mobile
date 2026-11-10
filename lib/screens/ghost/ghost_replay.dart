import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../../widgets/virtual_dartboard.dart';
import 'ghost_models.dart';

/// Replaying the ghost: its real darts, at their real place, at their real
/// rhythm (regles.md §5). Pure logic, kept out of the widgets so the timing
/// and the geometry are unit tested (test/ghost_replay_test.dart).

/// How long a finished ghost visit stays on screen before the next step.
const Duration kGhostVisitHold = Duration(milliseconds: 1600);

/// One step of a replay: after [at], [dartsShown] darts of [visit] are on
/// the board ([dartsShown] == darts.length + 1 marks the end of its hold).
class GhostReplayStep {
  final Duration at;
  final int visitIndex;
  final int dartsShown;
  const GhostReplayStep(this.at, this.visitIndex, this.dartsShown);
}

/// The full timeline of [visits]: each dart lands after its own `delayMs`
/// (counted from the previous dart, the first one from the previous visit's
/// hold), then the visit is held for [hold].
List<GhostReplayStep> ghostReplaySchedule(
  List<GhostVisit> visits, {
  Duration hold = kGhostVisitHold,
}) {
  final steps = <GhostReplayStep>[];
  var t = Duration.zero;
  for (var v = 0; v < visits.length; v++) {
    final darts = visits[v].darts;
    for (var d = 0; d < darts.length; d++) {
      t += Duration(milliseconds: math.max(0, darts[d].delayMs));
      steps.add(GhostReplayStep(t, v, d + 1));
    }
    t += hold;
    steps.add(GhostReplayStep(t, v, darts.length + 1));
  }
  return steps;
}

/// Plays a list of ghost visits with timers. [onDart] fires each time a dart
/// lands (visit index, darts now shown), [onVisitDone] when a visit's hold
/// is over, [onFinished] once after the last one. [cancel] stops everything
/// (screen disposed, player left).
class GhostReplayController {
  final List<GhostVisit> visits;
  final void Function(int visitIndex, int dartsShown) onDart;
  final void Function(int visitIndex) onVisitDone;
  final void Function() onFinished;
  final Duration hold;

  Timer? _timer;
  bool _cancelled = false;
  int _step = 0;
  late final List<GhostReplayStep> _steps = ghostReplaySchedule(visits, hold: hold);

  GhostReplayController({
    required this.visits,
    required this.onDart,
    required this.onVisitDone,
    required this.onFinished,
    this.hold = kGhostVisitHold,
  });

  bool get isRunning => _timer != null && !_cancelled;

  void start() {
    if (visits.isEmpty) {
      onFinished();
      return;
    }
    _scheduleNext(Duration.zero);
  }

  void _scheduleNext(Duration now) {
    if (_cancelled) return;
    if (_step >= _steps.length) {
      _timer = null;
      onFinished();
      return;
    }
    final step = _steps[_step];
    _timer = Timer(step.at - now, () {
      if (_cancelled) return;
      _step++;
      final visit = visits[step.visitIndex];
      if (step.dartsShown <= visit.darts.length) {
        onDart(step.visitIndex, step.dartsShown);
      } else {
        onVisitDone(step.visitIndex);
      }
      _scheduleNext(step.at);
    });
  }

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
    _timer = null;
  }
}

// ------------------------------------------------------------- geometry

/// Ring boundaries of a real board, normalized to the double ring's outer
/// edge (170 mm = 1), as the mobile scorer measures them (DartsMind dvBoard),
/// up to the board's edge (~225 mm).
const List<double> _realRings = [0, 0.0406, 0.0991, 0.5700, 0.6288, 0.9412, 1.0, 1.32];

/// The same boundaries on the virtual board, as fractions of its radius
/// (SpectatorDartboardPainter: bullseye, bull, triples, doubles, rim).
const List<double> _boardRings = [
  0,
  SpectatorDartboardPainter.bullseye,
  SpectatorDartboardPainter.bull,
  SpectatorDartboardPainter.tripleIn,
  SpectatorDartboardPainter.tripleOut,
  SpectatorDartboardPainter.doubleIn,
  SpectatorDartboardPainter.doubleOut,
  0.98,
];

/// Maps a real normalized radius onto the virtual board ring by ring, so a
/// dart read in the treble lands in the drawn treble even though the drawn
/// rings are not to scale.
double ghostBoardRadius(double realRadius) {
  if (realRadius <= 0) return 0;
  for (var i = 1; i < _realRings.length; i++) {
    if (realRadius <= _realRings[i]) {
      final t = (realRadius - _realRings[i - 1]) / (_realRings[i] - _realRings[i - 1]);
      return _boardRings[i - 1] + t * (_boardRings[i] - _boardRings[i - 1]);
    }
  }
  return _boardRings.last;
}

/// Where a ghost dart lands on the virtual board, as an offset from the
/// centre in fractions of the board radius (x right, y down) — or null when
/// it has no recorded position (the board then puts it at the centre of its
/// bed, like an old dart) or never reached the board.
Offset? ghostImpactUnit(GhostDart dart) {
  if (dart.skipped) return null;
  final r = dart.radius;
  final a = dart.angle;
  if (r == null || a == null || !r.isFinite || !a.isFinite) return null;
  final br = ghostBoardRadius(r);
  return Offset(math.cos(a) * br, math.sin(a) * br);
}

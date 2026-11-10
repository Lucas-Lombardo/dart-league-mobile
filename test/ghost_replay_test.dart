import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/ghost/ghost_models.dart';
import 'package:mobile/screens/ghost/ghost_replay.dart';
import 'package:mobile/widgets/virtual_dartboard.dart';

GhostVisit _visit(List<int> delays, {int leg = 0, int index = 0}) => GhostVisit(
      leg: leg,
      index: index,
      score: 60,
      remaining: 441,
      darts: [for (final d in delays) GhostDart(notation: 'S20', delayMs: d)],
    );

void main() {
  group('ghost replay timing (real rhythm)', () {
    test('each dart lands after its own delay, then the visit is held', () {
      final steps = ghostReplaySchedule(
        [_visit([1500, 2600, 400]), _visit([900, 1000, 1100])],
        hold: const Duration(milliseconds: 1600),
      );
      expect(
        steps.map((s) => (s.at.inMilliseconds, s.visitIndex, s.dartsShown)).toList(),
        [
          (1500, 0, 1),
          (4100, 0, 2),
          (4500, 0, 3),
          (6100, 0, 4), // end of hold
          (7000, 1, 1),
          (8000, 1, 2),
          (9100, 1, 3),
          (10700, 1, 4),
        ],
      );
    });

    test('the controller reveals the darts at the scheduled moments, not before', () {
      fakeAsync((async) {
        final events = <String>[];
        var finished = false;
        GhostReplayController(
          visits: [_visit([1500, 2600, 400]), _visit([800])],
          hold: const Duration(milliseconds: 1000),
          onDart: (v, n) => events.add('d$v.$n'),
          onVisitDone: (v) => events.add('done$v'),
          onFinished: () => finished = true,
        ).start();

        async.elapse(const Duration(milliseconds: 1499));
        expect(events, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(events, ['d0.1']);
        async.elapse(const Duration(milliseconds: 2599));
        expect(events, ['d0.1']);
        async.elapse(const Duration(milliseconds: 1));
        expect(events, ['d0.1', 'd0.2']);
        async.elapse(const Duration(milliseconds: 400));
        expect(events.last, 'd0.3');
        async.elapse(const Duration(milliseconds: 1000));
        expect(events.last, 'done0');
        expect(finished, isFalse);
        async.elapse(const Duration(milliseconds: 800));
        expect(events.last, 'd1.1');
        async.elapse(const Duration(milliseconds: 1000));
        expect(events.last, 'done1');
        expect(finished, isTrue);
      });
    });

    test('cancel stops the replay where it is', () {
      fakeAsync((async) {
        final events = <String>[];
        final c = GhostReplayController(
          visits: [_visit([500, 500, 500])],
          onDart: (v, n) => events.add('d$n'),
          onVisitDone: (_) => events.add('done'),
          onFinished: () => events.add('finished'),
        )..start();
        async.elapse(const Duration(milliseconds: 700));
        c.cancel();
        async.elapse(const Duration(seconds: 10));
        expect(events, ['d1']);
        expect(c.isRunning, isFalse);
      });
    });

    test('an empty replay finishes at once', () {
      var finished = false;
      GhostReplayController(
        visits: const [],
        onDart: (_, _) {},
        onVisitDone: (_) {},
        onFinished: () => finished = true,
      ).start();
      expect(finished, isTrue);
    });
  });

  group('ghost dart position (real place)', () {
    test('maps each real ring onto the drawn ring', () {
      // Middle of the real treble → inside the drawn treble.
      final treble = ghostBoardRadius(0.60);
      expect(treble, greaterThan(SpectatorDartboardPainter.tripleIn));
      expect(treble, lessThan(SpectatorDartboardPainter.tripleOut));
      // Middle of the real double → inside the drawn double.
      final dbl = ghostBoardRadius(0.97);
      expect(dbl, greaterThan(SpectatorDartboardPainter.doubleIn));
      expect(dbl, lessThan(SpectatorDartboardPainter.doubleOut));
      // An outer single near the double stays in the single bed.
      final outer = ghostBoardRadius(0.92);
      expect(outer, greaterThan(SpectatorDartboardPainter.tripleOut));
      expect(outer, lessThan(SpectatorDartboardPainter.doubleIn));
      // Bullseye stays in the drawn bullseye; far misses are clamped to the rim.
      expect(ghostBoardRadius(0.02), lessThan(SpectatorDartboardPainter.bullseye));
      expect(ghostBoardRadius(3), 0.98);
      expect(ghostBoardRadius(0), 0);
    });

    test('keeps the angle (atan2, y down): 20 is straight up', () {
      final up = ghostImpactUnit(const GhostDart(notation: 'T20', radius: 0.6, angle: 3 * math.pi / 2))!;
      expect(up.dx, closeTo(0, 1e-9));
      expect(up.dy, lessThan(0));
      final right = ghostImpactUnit(const GhostDart(notation: 'T6', radius: 0.6, angle: 0))!;
      expect(right.dy, closeTo(0, 1e-9));
      expect(right.dx, greaterThan(0));
    });

    test('an old dart without position, or a bounce-out, has no impact (bed centre / nothing)', () {
      expect(ghostImpactUnit(const GhostDart(notation: 'T20')), isNull);
      expect(ghostImpactUnit(const GhostDart(notation: 'S0', radius: 0.5, angle: 1, skipped: true)), isNull);
      expect(ghostImpactUnit(const GhostDart(notation: 'T20', radius: double.nan, angle: 1)), isNull);
      expect(ghostImpactUnit(const GhostDart(notation: 'S5', radius: 0.3, angle: 4.4)), isA<Offset>());
    });
  });
}

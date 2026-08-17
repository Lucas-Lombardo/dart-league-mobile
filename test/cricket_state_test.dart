import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/cricket.dart';
import 'package:mobile/providers/game_provider.dart'
    show ScoreMultiplier;

void main() {
  group('marksForDart', () {
    test('S/D/T on cricket numbers', () {
      expect(CricketState.marksForDart(20, ScoreMultiplier.single), 1);
      expect(CricketState.marksForDart(20, ScoreMultiplier.double), 2);
      expect(CricketState.marksForDart(20, ScoreMultiplier.triple), 3);
      expect(CricketState.marksForDart(15, ScoreMultiplier.triple), 3);
    });

    test('bull: 25=1 mark, 50=2 marks, no triple bull', () {
      expect(CricketState.marksForDart(25, ScoreMultiplier.single), 1);
      expect(CricketState.marksForDart(25, ScoreMultiplier.double), 2);
      expect(CricketState.marksForDart(25, ScoreMultiplier.triple), 0);
    });

    test('non-cricket numbers score nothing', () {
      expect(CricketState.marksForDart(14, ScoreMultiplier.triple), 0);
      expect(CricketState.marksForDart(1, ScoreMultiplier.single), 0);
      expect(CricketState.marksForDart(0, ScoreMultiplier.single), 0);
    });
  });

  group('closing and scoring (score mode)', () {
    test('T20 closes in one dart', () {
      final s = CricketState();
      final e = s.applyDart(20, ScoreMultiplier.triple, mine: true);
      expect(e.marksApplied, 3);
      expect(e.closedTarget, isTrue);
      expect(s.isClosedByMe(20), isTrue);
      expect(s.myPoints, 0);
    });

    test('overflow marks on a closing dart score points', () {
      final s = CricketState();
      s.applyDart(20, ScoreMultiplier.double, mine: true);
      final e = s.applyDart(20, ScoreMultiplier.triple, mine: true);
      // 2 marks then 3: one closes, two overflow → 2 × 20 points.
      expect(e.pointsScored, 40);
      expect(s.myPoints, 40);
    });

    test('hits on a closed number score its value per mark', () {
      final s = CricketState();
      s.applyDart(20, ScoreMultiplier.triple, mine: true);
      final e = s.applyDart(20, ScoreMultiplier.triple, mine: true);
      expect(e.pointsScored, 60);
      expect(s.myPoints, 60);
    });

    test('no points once the opponent closed the number', () {
      final s = CricketState();
      s.applyDart(20, ScoreMultiplier.triple, mine: true);
      s.applyDart(20, ScoreMultiplier.triple, mine: false);
      final e = s.applyDart(20, ScoreMultiplier.triple, mine: true);
      expect(e.pointsScored, 0);
      expect(s.isDead(20), isTrue);
    });

    test('gold state: closed by me, open for opponent', () {
      final s = CricketState();
      s.applyDart(19, ScoreMultiplier.triple, mine: true);
      expect(s.isScoringForMe(19), isTrue);
      s.applyDart(19, ScoreMultiplier.triple, mine: false);
      expect(s.isScoringForMe(19), isFalse);
    });

    test('bull scores 25 per overflow mark', () {
      final s = CricketState();
      s.applyDart(25, ScoreMultiplier.double, mine: true);
      s.applyDart(25, ScoreMultiplier.double, mine: true);
      // 2 marks then 2: one closes, one overflows → 25 points.
      expect(s.myPoints, 25);
      expect(s.isClosedByMe(25), isTrue);
    });
  });

  group('win conditions', () {
    CricketState closedBoard({required bool mine, CricketScoreMode mode = CricketScoreMode.score}) {
      final s = CricketState(scoreMode: mode);
      for (final t in kCricketTargets) {
        s.applyDart(t, ScoreMultiplier.triple, mine: mine);
        if (t == 25) {
          s.applyDart(t, ScoreMultiplier.double, mine: mine);
          s.applyDart(t, ScoreMultiplier.single, mine: mine);
        }
      }
      return s;
    }

    test('score mode: all closed but behind on points is not a win', () {
      final s = closedBoard(mine: true);
      // Opponent closed nothing but has more points than us (0)? Give them
      // points via our open… impossible; instead close ours after they score.
      final t = CricketState();
      t.applyDart(20, ScoreMultiplier.triple, mine: false);
      t.applyDart(20, ScoreMultiplier.triple, mine: false); // opp: 60 pts
      for (final target in kCricketTargets) {
        t.applyDart(target, ScoreMultiplier.triple, mine: true);
        if (target == 25) {
          t.applyDart(target, ScoreMultiplier.double, mine: true);
          t.applyDart(target, ScoreMultiplier.single, mine: true);
        }
      }
      expect(t.myClosedCount, kCricketTargets.length);
      expect(t.iWon, isFalse); // 0 points vs 60
      expect(s.iWon, isTrue); // control: equal points → win
    });

    test('noScore mode: closing everything wins regardless of points', () {
      final s = closedBoard(mine: true, mode: CricketScoreMode.noScore);
      expect(s.iWon, isTrue);
    });

    test('opponent side win is symmetric', () {
      final s = closedBoard(mine: false, mode: CricketScoreMode.noScore);
      expect(s.oppWon, isTrue);
      expect(s.iWon, isFalse);
    });
  });

  test('clone is independent from the original', () {
    final s = CricketState();
    s.applyDart(20, ScoreMultiplier.triple, mine: true);
    final copy = s.clone();
    copy.applyDart(19, ScoreMultiplier.triple, mine: true);
    expect(s.myMarks(19), 0);
    expect(copy.myMarks(19), 3);
    expect(copy.myMarks(20), 3);
  });

  test('marksToWire round-trips the board shape', () {
    final s = CricketState();
    s.applyDart(20, ScoreMultiplier.double, mine: true);
    s.applyDart(25, ScoreMultiplier.single, mine: false);
    expect(s.marksToWire(mine: true)['20'], 2);
    expect(s.marksToWire(mine: true)['25'], 0);
    expect(s.marksToWire(mine: false)['25'], 1);
  });

  test('myMarksTotal counts closing marks and scoring overflow', () {
    final s = CricketState();
    s.applyDart(20, ScoreMultiplier.triple, mine: true);
    s.applyDart(20, ScoreMultiplier.triple, mine: true);
    expect(s.myMarksTotal, 6);
  });

  test('a dart on a dead target is worth 0 marks and 0 points', () {
    final s = CricketState();
    s.applyDart(20, ScoreMultiplier.triple, mine: true);
    s.applyDart(20, ScoreMultiplier.triple, mine: false);
    final e = s.applyDart(20, ScoreMultiplier.triple, mine: true);
    expect(e.marksApplied, 0);
    expect(e.pointsScored, 0);
    expect(s.myMarksTotal, 3);
  });

  test('wasted overflow in noScore mode does not count as marks', () {
    final s = CricketState(scoreMode: CricketScoreMode.noScore);
    s.applyDart(20, ScoreMultiplier.double, mine: true);
    final e = s.applyDart(20, ScoreMultiplier.triple, mine: true);
    // 2 marks then 3: one closes, two are wasted (no points in noScore).
    expect(e.marksApplied, 1);
    expect(e.closedTarget, isTrue);
    expect(s.myMarksTotal, 3);
  });
}

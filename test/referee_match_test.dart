import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/local_match_config.dart';
import 'package:mobile/models/referee_match.dart';

RefereeMatch game({bool doubleOut = true, int bestOf = 3, int first = 0}) =>
    RefereeMatch(
      config: LocalMatchConfig(
        player1Name: 'Lucas',
        player2Name: 'Thomas',
        doubleOut: doubleOut,
        bestOf: bestOf,
      ),
      firstPlayer: first,
    );

void visit(RefereeMatch match, int points) {
  match.setTotal(points);
  match.validateVisit();
}

// Bring player 0 to a useful finish without mutating private state.
void leave(RefereeMatch match, int remaining) {
  for (final points in [180, 180, 141 - remaining]) {
    visit(match, points);
    visit(match, 0);
  }
}

void main() {
  test('total preview is provisional; validation updates only one player', () {
    final match = game(first: 1);
    match.setTotal(60);
    expect(match.preview.remaining, 441);
    expect(match.scores, [501, 501]);
    expect(match.averageOf(1), isNull);
    final visit = match.validateVisit();
    expect(match.scores, [501, 441]);
    expect(match.activePlayer, 0);
    expect(match.averageOf(1), 60);
    expect(visit.darts, isNull);
    expect(match.preview.kind, RefereeVisitKind.empty);
  });

  test(
    '131 minus triple 15 immediately announces 86, then validates directly',
    () {
      final match = game();
      leave(match, 131);
      match.useDarts();
      expect(match.enterDart(RefereeDart(15, 3)), isTrue);
      expect(match.preview.remaining, 86);
      expect(match.scores.first, 131);
      match.validateVisit();
      expect(match.scores.first, 86);
      expect(match.activePlayer, 1);
      expect(match.inputMode, RefereeInputMode.darts);
      expect(match.draftDarts, isEmpty);
      expect(match.history.last.darts!.single.notation, 'T15');
    },
  );

  test(
    'three slots allow replacement and deletion shifts the following darts',
    () {
      final match = game()..useDarts();
      for (final n in [20, 19, 18]) {
        match.enterDart(RefereeDart(n));
      }
      expect(match.enterDart(RefereeDart(17)), isFalse);
      match.selectDart(1);
      match.enterDart(RefereeDart(15, 3));
      expect(match.preview.points, 83);
      match.selectDart(2);
      match.removeDart(0);
      expect(match.editingDart, isNull);
      expect(match.draftDarts.map((d) => d.notation), ['T15', 'S18']);
      match.enterDart(RefereeDart(0));
      expect(match.draftDarts.length, 3);
    },
  );

  test(
    'total switching copies the subtotal exactly once and preserves details',
    () {
      final match = game()..useDarts();
      match.enterDart(RefereeDart(15, 3));
      match.useTotal();
      expect(match.totalInput, '45');
      expect(match.useDarts(), isTrue);
      expect(match.preview.points, 45);
      match.useTotal();
      final result = match.validateVisit();
      expect(result.points, 45);
      expect(result.darts!.single.notation, 'T15');
    },
  );

  test(
    'editing a copied total replaces it and no longer fabricates dart details',
    () {
      final match = game()..useDarts();
      match.enterDart(RefereeDart(15, 3));
      match.useTotal();
      match.enterDigit(6);
      match.enterDigit(0);
      expect(match.totalInput, '60');
      expect(match.validateVisit().darts, isNull);
    },
  );

  test('switching an arbitrary total requires explicit discard', () {
    final match = game()..setTotal(60);
    expect(match.useDarts(), isFalse);
    expect(match.totalInput, '60');
    expect(match.useDarts(discardTotal: true), isTrue);
    expect(match.draftDarts, isEmpty);
    expect(match.preview.kind, RefereeVisitKind.empty);
  });

  test(
    'zero is a valid visit; empty and impossible totals cannot be submitted',
    () {
      final match = game();
      expect(() => match.validateVisit(), throwsStateError);
      for (final n in [-1, 163, 166, 169, 172, 175, 178, 179, 181, 999]) {
        match.setTotal(n);
        expect(match.preview.kind, RefereeVisitKind.invalid, reason: '$n');
        expect(() => match.validateVisit(), throwsStateError);
      }
      for (final n in [0, 162, 164, 165, 167, 168, 170, 171, 174, 177, 180]) {
        match.setTotal(n);
        expect(match.preview.canValidate, isTrue, reason: '$n');
      }
      match.setTotal(0);
      match.validateVisit();
      expect(match.activePlayer, 1);
      expect(match.averageOf(0), 0);
    },
  );

  test('presets replace existing input and backspace clears one digit', () {
    final match = game()..setTotal(100);
    match.enterDigit(4);
    match.enterDigit(5);
    expect(match.totalInput, '45');
    match.backspace();
    expect(match.totalInput, '4');
    match.backspace();
    expect(match.preview.kind, RefereeVisitKind.empty);
    match.enterDigit(0);
    match.enterDigit(1);
    expect(match.totalInput, '1');
  });

  for (final total in [40, 42]) {
    test(
      'double out bust on $total from 41 restores score and credits zero',
      () {
        final match = game();
        leave(match, 41);
        match.setTotal(total);
        expect(match.preview.kind, RefereeVisitKind.bust);
        match.validateVisit();
        expect(match.scores.first, 41);
        expect(match.history.last.bust, isTrue);
        expect(match.averageOf(0), 460 / 4);
        match.undo();
        expect(match.activePlayer, 0);
        expect(match.averageOf(0), 460 / 3);
      },
    );
  }

  test('explicit bust works without requiring individual darts or a total', () {
    final match = game();
    match.validateVisit(bust: true);
    expect(match.scores, [501, 501]);
    expect(match.history.single.points, 0);
    expect(match.activePlayer, 1);
  });

  test('a single reaching zero is a bust, also after switching to total', () {
    final match = game();
    leave(match, 20);
    match.useDarts();
    match.enterDart(RefereeDart(20));
    expect(match.preview.kind, RefereeVisitKind.bust);
    match.useTotal();
    expect(match.preview.kind, RefereeVisitKind.bust);
    match.validateVisit();
    expect(match.scores.first, 20);
  });

  test(
    'detailed double checkout retains exact dart count through both tabs',
    () {
      final match = game();
      leave(match, 40);
      match.useDarts();
      match.enterDart(RefereeDart(0));
      match.enterDart(RefereeDart(20, 2));
      expect(match.preview.finishDartCounts, [2]);
      match.useTotal();
      expect(match.preview.finishDartCounts, [2]);
      expect(() => match.validateVisit(checkoutDarts: 1), throwsStateError);
      expect(match.history.length, 6);
      match.validateVisit(checkoutDarts: 2);
      expect(match.legs, [1, 0]);
      expect(match.history.last.checkoutDarts, 2);
    },
  );

  test('total checkout only offers physically achievable dart counts', () {
    expect(RefereeMatch.possibleFinishCounts(170, doubleOut: true), [3]);
    expect(RefereeMatch.possibleFinishCounts(169, doubleOut: true), isEmpty);
    expect(RefereeMatch.possibleFinishCounts(99, doubleOut: true), [3]);
    expect(RefereeMatch.possibleFinishCounts(100, doubleOut: true), [2, 3]);
    expect(RefereeMatch.possibleFinishCounts(50, doubleOut: true), [1, 2, 3]);
    final match = game();
    leave(match, 40);
    match.setTotal(40);
    expect(() => match.validateVisit(), throwsStateError);
    match.validateVisit(checkoutDarts: 1);
    expect(match.history.last.darts, isNull);
  });

  test(
    'a terminal dart cannot be followed, and editing an earlier dart invalidates its tail',
    () {
      final match = game();
      leave(match, 40);
      match.useDarts();
      for (final n in [1, 2, 3]) {
        match.enterDart(RefereeDart(n));
      }
      match.selectDart(0);
      match.enterDart(RefereeDart(20, 2));
      expect(match.preview.error, RefereeInputError.dartsAfterEnd);
      expect(() => match.validateVisit(), throwsStateError);
      match.removeDart(2);
      match.removeDart(1);
      expect(match.preview.kind, RefereeVisitKind.finish);
      expect(match.enterDart(RefereeDart(1)), isFalse);
    },
  );

  test('straight out permits remaining 1 and a single to finish', () {
    final match = game(doubleOut: false);
    leave(match, 20);
    visit(match, 19);
    visit(match, 0);
    match.useDarts();
    match.enterDart(RefereeDart(1));
    expect(match.preview.kind, RefereeVisitKind.finish);
    match.validateVisit(checkoutDarts: 1);
    expect(match.legs.first, 1);
  });

  test('bull 50 finishes on a double; bull 25 is not a double', () {
    final match = game();
    leave(match, 50);
    match.useDarts();
    match.enterDart(RefereeDart(25, 2));
    expect(match.preview.kind, RefereeVisitKind.finish);
    match.clearDraft();
    match.enterDart(RefereeDart(25));
    match.enterDart(RefereeDart(25));
    expect(match.preview.kind, RefereeVisitKind.bust);
  });

  test('next leg alternates the starter and undo crosses a leg boundary', () {
    final match = game();
    leave(match, 40);
    match.setTotal(40);
    match.validateVisit(checkoutDarts: 1);
    expect(match.canEnter, isFalse);
    match.startNextLeg();
    expect(match.scores, [501, 501]);
    expect(match.activePlayer, 1);
    expect(match.legNumber, 2);
    visit(match, 60);
    match.undo();
    expect(match.activePlayer, 1);
    expect(match.legs, [1, 0]);
    match.undo();
    expect(match.scores, [40, 501]);
    expect(match.legs, [0, 0]);
    expect(match.legNumber, 1);
    expect(match.activePlayer, 0);
    expect(match.canEnter, isTrue);
  });

  test('winning visit is undoable and rematch resets all match data', () {
    final match = game(bestOf: 1);
    leave(match, 40);
    match.setTotal(40);
    match.validateVisit(checkoutDarts: 1);
    expect(match.winner, 0);
    match.startNextLeg();
    expect(match.winner, 0);
    match.undo();
    expect(match.winner, isNull);
    expect(match.scores.first, 40);
    match.useDarts();
    match.restart();
    expect(match.scores, [501, 501]);
    expect(match.legs, [0, 0]);
    expect(match.history, isEmpty);
    expect(match.canUndo, isFalse);
    expect(match.inputMode, RefereeInputMode.total);
  });

  test('invalid darts and unsupported configurations are rejected', () {
    for (final pair in [
      [25, 3],
      [0, 2],
      [21, 1],
      [-1, 1],
      [20, 0],
    ]) {
      expect(() => RefereeDart(pair[0], pair[1]), throwsArgumentError);
    }
    expect(
      () => RefereeMatch(
        config: const LocalMatchConfig(
          startingScore: 301,
          player1Name: 'A',
          player2Name: 'B',
        ),
      ),
      throwsArgumentError,
    );
  });
}

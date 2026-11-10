import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/app_localizations_fr.dart';
import 'package:mobile/providers/game_provider.dart' show ScoreMultiplier;
import 'package:mobile/screens/challenge/challenge_models.dart';
import 'package:mobile/screens/challenge/logic/challenge_engine.dart';
import 'package:mobile/screens/challenge/logic/challenge_strategy.dart';
import 'package:mobile/screens/training/logic/training_strategy.dart';

/// The app's challenge engine must give exactly the server's results:
/// test/fixtures/challenge_vectors.json is a copy of
/// backend/src/challenge/engine/challenge-vectors.json.
void main() {
  final file = File('test/fixtures/challenge_vectors.json');
  final cases = (jsonDecode(file.readAsStringSync()) as Map)['cases'] as List;

  group('shared vectors', () {
    for (final raw in cases) {
      final c = Map<String, dynamic>.from(raw as Map);
      test(c['name'], () {
        final visits = [
          for (final v in c['visits'] as List) [for (final n in v as List) parseChallengeDart(n as String)!],
        ];
        final r = runChallengeEngine(
          c['mode'] as String,
          Map<String, dynamic>.from(c['params'] as Map),
          Map<String, dynamic>.from(c['day'] as Map),
          visits,
        )!;
        final e = Map<String, dynamic>.from(c['expect'] as Map);
        expect(
          {'score': r.score, 'tiebreak': r.tiebreak, 'darts': r.darts, 'finished': r.finished},
          {'score': e['score'], 'tiebreak': e['tiebreak'], 'darts': e['darts'], 'finished': e['finished']},
        );
      });
    }

    test('every mode the app knows has a vector', () {
      final modes = cases.map((c) => (c as Map)['mode']).toSet();
      expect(modes, containsAll(kChallengeModes));
    });
  });

  test('parses and prints the notations the server expects', () {
    expect(parseChallengeDart('T20')!.notation, 'T20');
    expect(parseChallengeDart('B')!.notation, 'SB');
    expect(parseChallengeDart('50')!.notation, 'DB');
    expect(parseChallengeDart('S0')!.notation, 'M');
    expect(parseChallengeDart('T25'), isNull);
    expect(runChallengeEngine('darts_golf', const {}, const {}, const []), isNull);
  });

  group('live display through the training view', () {
    final l10n = AppLocalizationsFr();
    ChallengeFormat fmt(String mode, Map<String, dynamic> params, {Map<String, dynamic> day = const {}}) =>
        ChallengeFormat.fromJson({
          'id': 'f',
          'mode': mode,
          'name': {'fr': 'F', 'en': 'F'},
          'rule': {'fr': 'r', 'en': 'r'},
          'params': params,
          'dayParams': day,
          'score': {'order': 'desc'},
          'tiebreak': {'order': 'desc'},
        })!;
    const t20 = TrainingDart(20, ScoreMultiplier.triple);
    const d1 = TrainingDart(1, ScoreMultiplier.double);

    test('score max: running total per dart, ends after the last visit', () {
      final s = ChallengeStrategy(fmt('high_score', {'visits': 2}));
      expect(s.primaryValue(l10n, const [t20]), '60');
      expect(s.submitVisit(const [t20, t20, t20]).finished, isFalse);
      expect(s.secondaryValue(l10n, const []), '2 / 2');
      expect(s.submitVisit(const [t20, t20, t20]).finished, isTrue);
      expect(s.result.score, 360);
    });

    test('doubles clock: the target moves with each dart', () {
      final s = ChallengeStrategy(fmt('atc', {'ring': 'double', 'targets': [1, 2, 3], 'cap': 99}));
      expect(s.primaryLabel(l10n), 'Cible');
      expect(s.primaryValue(l10n, const []), 'D1');
      expect(s.primaryValue(l10n, const [d1]), 'D2');
    });

    test("bob's 27: the round's double stays until the visit is confirmed", () {
      final s = ChallengeStrategy(fmt('bobs_27', {'start': 27}));
      expect(s.primaryValue(l10n, const [d1]), 'D1');
      s.submitVisit(const [d1, TrainingDart(0, ScoreMultiplier.single), TrainingDart(0, ScoreMultiplier.single)]);
      expect(s.primaryValue(l10n, const []), 'D2');
      expect(s.result.score, 29);
    });

    test('checkout set: shows what is left, then the next finish', () {
      final s = ChallengeStrategy(fmt('checkout_set', {'darts': 9, 'scoring': 'sum'}, day: {'finishes': [100, 121]}));
      expect(s.primaryLabel(l10n), 'Reste');
      expect(s.primaryValue(l10n, const [t20]), '40');
      s.submitVisit(const [t20, TrainingDart(20, ScoreMultiplier.double), TrainingDart(0, ScoreMultiplier.single)]);
      expect(s.primaryValue(l10n, const []), '121');
      expect(s.progressCaption(l10n, const []), 'Finition 2 sur 2 · 0/9 fléchettes');
    });
  });
}

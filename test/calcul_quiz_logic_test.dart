import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/providers/game_provider.dart' show ScoreMultiplier;
import 'package:mobile/screens/training/logic/checkout_routes.dart';
import 'package:mobile/screens/training/logic/quick_count_questions.dart';
import 'package:mobile/screens/training/logic/training_strategy.dart';
import 'package:mobile/utils/dart_caller_service.dart';

void main() {
  group('table des checkouts du livre', () {
    test('couvre tous les scores finissables de 2 à 170, et rien d\'autre',
        () {
      for (var score = 2; score <= 170; score++) {
        final finishable = DartCallerService.isCheckout(score);
        expect(
          kBookCheckouts.containsKey(score),
          finishable,
          reason: 'score $score (finissable: $finishable)',
        );
      }
      expect(kBookCheckouts.length, 162);
    });

    test('chaque route somme au score, finit sur un double, en 3 max', () {
      kBookCheckouts.forEach((score, notations) {
        expect(notations.length, lessThanOrEqualTo(3), reason: 'score $score');
        final darts = notations.map(dartFromNotation).toList();
        expect(darts, everyElement(isNotNull), reason: 'score $score');
        final route = darts.whereType<TrainingDart>().toList();
        final total = route.fold(0, (a, d) => a + d.points);
        expect(total, score, reason: 'score $score : $notations');
        expect(route.last.isDouble, isTrue, reason: 'score $score');
        final v = validateCheckoutRoute(score, route);
        expect(v.success, isTrue, reason: 'score $score : $notations');
      });
    });
  });

  group('validateCheckoutRoute', () {
    TrainingDart d(String n) => dartFromNotation(n)!;

    test('71 en T13 puis D16 sort', () {
      final v = validateCheckoutRoute(71, [d('T13'), d('D16')]);
      expect(v.success, isTrue);
    });

    test('71 en T17 puis D10 sort aussi (plusieurs routes valides)', () {
      final v = validateCheckoutRoute(71, [d('T17'), d('D10')]);
      expect(v.success, isTrue);
    });

    test('finir à zéro sans double est refusé', () {
      final v = validateCheckoutRoute(71, [d('T17'), d('S20')]);
      expect(v.success, isFalse);
      expect(v.failReason, 'not_double_finish');
    });

    test('passer sous zéro est un bust', () {
      final v = validateCheckoutRoute(41, [d('T20')]);
      expect(v.success, isFalse);
      expect(v.failReason, 'below_zero');
    });

    test('laisser 1 est un bust', () {
      final v = validateCheckoutRoute(41, [d('S20'), d('S20')]);
      expect(v.success, isFalse);
      expect(v.failReason, 'left_one');
    });

    test('ne pas atteindre zéro donne short', () {
      final v = validateCheckoutRoute(71, [d('S20'), d('S20')]);
      expect(v.success, isFalse);
      expect(v.failReason, 'short');
      expect(v.remaining, 31);
    });

    test('le double bull finit un 50', () {
      final v = validateCheckoutRoute(50, [d('DB')]);
      expect(v.success, isTrue);
    });
  });

  group('validCheckoutRoutes', () {
    String key(List<TrainingDart> r) =>
        r.map((d) => d.notation).join(' ');

    test('71 en 2 fléchettes contient T13 D16 et T17 D10', () {
      final routes = validCheckoutRoutes(71, 2).map(key).toList();
      expect(routes, contains('T13 D16'));
      expect(routes, contains('T17 D10'));
    });

    test('toutes les routes retournées sont réellement valides', () {
      for (final target in [71, 32, 50, 110, 141, 167]) {
        for (final route in validCheckoutRoutes(target, 3)) {
          final v = validateCheckoutRoute(target, route);
          expect(v.success, isTrue, reason: '$target : ${key(route)}');
        }
      }
    });

    test('159 (bogey) n\'a aucune route en 2 fléchettes', () {
      expect(validCheckoutRoutes(159, 2), isEmpty);
    });
  });

  group('recommendedCheckoutRoutes', () {
    String key(List<TrainingDart> r) => r.map((d) => d.notation).join(' ');
    List<String> reco(int target, int darts) =>
        recommendedCheckoutRoutes(target, darts).map(key).toList();

    test('55 : seulement 15 D20 et 19 D18', () {
      expect(reco(55, 2), ['S15 D20', 'S19 D18']);
    });

    test('71 : T13 D16 et T17 D10, rien en D2 ou D5', () {
      final routes = reco(71, 2);
      expect(routes.first, 'T13 D16');
      expect(routes, contains('T17 D10'));
      expect(routes.any((r) => r.endsWith('D2') || r.endsWith('D5')), isFalse);
    });

    test('100 : T20 D20 uniquement', () {
      expect(reco(100, 2), ['T20 D20']);
    });

    test('50 : bull d\'abord, puis les sorties en deux fléchettes', () {
      expect(reco(50, 2).first, 'DB');
      expect(reco(50, 2), contains('S10 D20'));
    });

    test('95 : T19 D19 seulement, pas de bull tiré par les cheveux', () {
      expect(reco(95, 2), ['T19 D19']);
    });

    test('111 : après le livre, les tableaux (T19 14 D20, T17 20 D20)', () {
      final routes = reco(111, 3);
      expect(routes.take(4), ['T20 S11 D20', 'T19 S14 D20', 'T18 S17 D20', 'T17 S20 D20']);
    });

    test('161 : deux gros triples puis bull, les deux variantes', () {
      expect(reco(161, 3), ['T20 T17 DB', 'T19 T18 DB']);
    });

    test('141 : les combinaisons de deux triples des tableaux', () {
      final routes = reco(141, 3);
      expect(routes.first, 'T20 T19 D12');
      expect(routes, contains('T20 T15 D18'));
      expect(routes, contains('T19 T16 D18'));
    });

    test('la route du livre est toujours en tête et toutes sont valides', () {
      kBookCheckouts.forEach((score, notations) {
        final routes = recommendedCheckoutRoutes(score, 3);
        expect(key(routes.first), notations.join(' '), reason: 'score $score');
        for (final r in routes) {
          expect(validateCheckoutRoute(score, r).success, isTrue,
              reason: 'score $score : ${key(r)}');
        }
      });
    });
  });

  group('minDartsToCheckout', () {
    test('valeurs de référence', () {
      expect(minDartsToCheckout(40), 1);
      expect(minDartsToCheckout(50), 1);
      expect(minDartsToCheckout(41), 2);
      expect(minDartsToCheckout(110), 2);
      expect(minDartsToCheckout(109), 3);
      expect(minDartsToCheckout(170), 3);
      expect(minDartsToCheckout(169), 0);
      expect(minDartsToCheckout(1), 0);
    });
  });

  group('pickCheckoutQuestion', () {
    test('propose toujours un score finissable dans le budget', () {
      final rng = Random(42);
      for (var i = 0; i < 300; i++) {
        final q = pickCheckoutQuestion(rng);
        final min = minDartsToCheckout(q.target);
        expect(min, greaterThan(0), reason: 'cible ${q.target}');
        expect(min, lessThanOrEqualTo(q.dartsAllowed),
            reason: 'cible ${q.target} en ${q.dartsAllowed}');
      }
    });
  });

  group('generateQuickCountQuestion', () {
    test('ne génère jamais de bust et la réponse est la soustraction', () {
      final rng = Random(7);
      for (var i = 0; i < 500; i++) {
        final q = generateQuickCountQuestion(rng);
        expect(q.visit.length, 3);
        expect(q.answer, greaterThanOrEqualTo(2));
        expect(q.answer, q.startScore - q.visitTotal);
        expect(q.startScore, inInclusiveRange(40, 501));
      }
    });

    test('la valeur des fléchettes suit les règles du jeu', () {
      const bull = TrainingDart(25, ScoreMultiplier.single);
      const dBull = TrainingDart(25, ScoreMultiplier.double);
      expect(bull.points, 25);
      expect(dBull.points, 50);
      expect(dBull.isDouble, isTrue);
    });
  });
}

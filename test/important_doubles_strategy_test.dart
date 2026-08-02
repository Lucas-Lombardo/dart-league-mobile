import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations_fr.dart';
import 'package:mobile/providers/game_provider.dart' show ScoreMultiplier;
import 'package:mobile/screens/training/logic/important_doubles_strategy.dart';
import 'package:mobile/screens/training/logic/training_strategy.dart';

/// Le panneau du drill : ce que le joueur lit depuis l'oche pendant les
/// 60 fléchettes — combien de doubles mis, sur combien de lancées, à quel taux.
const _d20 = TrainingDart(20, ScoreMultiplier.double);
const _d1 = TrainingDart(1, ScoreMultiplier.double);
const _miss = TrainingDart(20, ScoreMultiplier.single);

void main() {
  final l10n = AppLocalizationsFr();

  test('la réussite compte les fléchettes lancées, pas les 60 prévues', () {
    final s = ImportantDoublesStrategy(targets: const [20]);

    expect(s.secondaryValue(l10n, const []), '—');
    expect(s.progressCaption(l10n, const []), '0/60 fléchettes');

    // Les fléchettes détectées comptent avant même la validation de la volée.
    expect(s.secondaryValue(l10n, const [_d20, _miss]), '1/2 · 50%');
    expect(s.progressCaption(l10n, const [_d20, _miss]), '2/60 fléchettes');

    s.submitVisit(const [_d20, _miss, _miss]);
    expect(s.secondaryValue(l10n, const []), '1/3 · 33%');
    expect(s.progressCaption(l10n, const []), '3/60 fléchettes');
    expect(s.progress(const []), closeTo(3 / 60, 1e-9));
  });

  test('une volée qui déborde de la fin du bloc ne compte pas en trop', () {
    final s = ImportantDoublesStrategy(targets: const [20]);
    for (var i = 0; i < 29; i++) {
      s.submitVisit(const [_d20, _miss]); // 58 fléchettes, 29 réussies
    }

    expect(s.progressCaption(l10n, const []), '58/60 fléchettes');
    expect(
      s.progressCaption(l10n, const [_d20, _d20, _d20]),
      '60/60 fléchettes',
    );
    expect(s.secondaryValue(l10n, const [_d20, _d20, _d20]), '31/60 · 52%');
  });

  test('sur deux doubles, le second bloc repart de zéro', () {
    final s = ImportantDoublesStrategy(targets: const [20, 1]);
    for (var i = 0; i < 20; i++) {
      s.submitVisit(const [_d20, _miss, _miss]);
    }

    expect(s.primaryValue(l10n, const []), 'D1');
    expect(s.secondaryValue(l10n, const []), '—');
    expect(s.progressCaption(l10n, const []), 'Double 2 sur 2 · 0/60');
    expect(s.progress(const []), closeTo(0.5, 1e-9));

    s.submitVisit(const [_d1, _d1, _miss]);
    expect(s.secondaryValue(l10n, const []), '2/3 · 67%');
    expect(s.progressCaption(l10n, const []), 'Double 2 sur 2 · 3/60');
  });

  test('en fin de session, la réussite passe au total des deux blocs', () {
    final s = ImportantDoublesStrategy(targets: const [20, 1]);
    for (var i = 0; i < 20; i++) {
      s.submitVisit(const [_d20, _miss, _miss]);
    }
    for (var i = 0; i < 20; i++) {
      s.submitVisit(const [_d1, _d1, _d1]);
    }

    expect(s.secondaryValue(l10n, const []), '80/120 · 67%');
    expect(s.progressCaption(l10n, const []), isNull);
    expect(s.progress(const []), 1.0);
    expect(s.buildResult(l10n).score, 67);
  });
}

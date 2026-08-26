import 'dart:math';

import '../../../providers/game_provider.dart' show ScoreMultiplier;
import '../../../utils/dart_caller_service.dart';
import 'training_strategy.dart';

/// One "Vision checkout" quiz question: finish [target] within [dartsAllowed]
/// darts, last dart on a double (D-Bull included).
class CheckoutQuestion {
  final int target;
  final int dartsAllowed;

  const CheckoutQuestion(this.target, this.dartsAllowed);
}

/// Outcome of validating a composed route against a target. [failReason]
/// reuses the bust vocabulary of the checkout strategies ('below_zero',
/// 'not_double_finish', 'left_one') plus 'short' when the darts ran out with
/// points still on the board.
class CheckoutValidation {
  final bool success;
  final String? failReason;

  /// Points left after the played darts (0 on success).
  final int remaining;

  const CheckoutValidation({
    required this.success,
    this.failReason,
    required this.remaining,
  });
}

/// Standard X01 double-out rules, dart by dart. Success can happen before all
/// darts are used; extra darts after a finish are never reached because the
/// screen validates after each one.
CheckoutValidation validateCheckoutRoute(int target, List<TrainingDart> darts) {
  var remaining = target;
  for (final d in darts) {
    final next = remaining - d.points;
    if (next < 0) {
      return CheckoutValidation(
        success: false,
        failReason: 'below_zero',
        remaining: remaining,
      );
    }
    if (next == 0) {
      if (d.isDouble) {
        return const CheckoutValidation(success: true, remaining: 0);
      }
      return CheckoutValidation(
        success: false,
        failReason: 'not_double_finish',
        remaining: remaining,
      );
    }
    if (next == 1) {
      return CheckoutValidation(
        success: false,
        failReason: 'left_one',
        remaining: remaining,
      );
    }
    remaining = next;
  }
  return CheckoutValidation(
    success: false,
    failReason: 'short',
    remaining: remaining,
  );
}

/// Parses a notation from the [TrainingDart.notation] dialect ('M', 'B',
/// 'DB', 'S20', 'D20', 'T20'). Returns null on anything else.
TrainingDart? dartFromNotation(String notation) {
  switch (notation) {
    case 'M':
      return const TrainingDart(0, ScoreMultiplier.single);
    case 'B':
      return const TrainingDart(25, ScoreMultiplier.single);
    case 'DB':
      return const TrainingDart(25, ScoreMultiplier.double);
  }
  if (notation.length < 2) return null;
  final base = int.tryParse(notation.substring(1));
  if (base == null || base < 1 || base > 20) return null;
  switch (notation[0]) {
    case 'S':
      return TrainingDart(base, ScoreMultiplier.single);
    case 'D':
      return TrainingDart(base, ScoreMultiplier.double);
    case 'T':
      return TrainingDart(base, ScoreMultiplier.triple);
  }
  return null;
}

/// The "book" checkout for every finishable score 2-170 (bogey numbers 169,
/// 168, 166, 165, 163, 162 and 159 have no entry). One conventional
/// recommendation per score, in [TrainingDart.notation] dialect.
const Map<int, List<String>> kBookCheckouts = {
  170: ['T20', 'T20', 'DB'],
  167: ['T20', 'T19', 'DB'],
  164: ['T20', 'T18', 'DB'],
  161: ['T20', 'T17', 'DB'],
  160: ['T20', 'T20', 'D20'],
  158: ['T20', 'T20', 'D19'],
  157: ['T20', 'T19', 'D20'],
  156: ['T20', 'T20', 'D18'],
  155: ['T20', 'T19', 'D19'],
  154: ['T20', 'T18', 'D20'],
  153: ['T20', 'T19', 'D18'],
  152: ['T20', 'T20', 'D16'],
  151: ['T20', 'T17', 'D20'],
  150: ['T20', 'T18', 'D18'],
  149: ['T20', 'T19', 'D16'],
  148: ['T20', 'T16', 'D20'],
  147: ['T20', 'T17', 'D18'],
  146: ['T20', 'T18', 'D16'],
  145: ['T20', 'T15', 'D20'],
  144: ['T20', 'T20', 'D12'],
  143: ['T20', 'T17', 'D16'],
  142: ['T20', 'T14', 'D20'],
  141: ['T20', 'T19', 'D12'],
  140: ['T20', 'T20', 'D10'],
  139: ['T20', 'T13', 'D20'],
  138: ['T20', 'T18', 'D12'],
  137: ['T20', 'T19', 'D10'],
  136: ['T20', 'T20', 'D8'],
  135: ['T20', 'T17', 'D12'],
  134: ['T20', 'T14', 'D16'],
  133: ['T20', 'T19', 'D8'],
  132: ['T20', 'T16', 'D12'],
  131: ['T20', 'T13', 'D16'],
  130: ['T20', 'T18', 'D8'],
  129: ['T19', 'T16', 'D12'],
  128: ['T20', 'T20', 'D4'],
  127: ['T20', 'T17', 'D8'],
  126: ['T19', 'T19', 'D6'],
  125: ['T20', 'T19', 'D4'],
  124: ['T20', 'T16', 'D8'],
  123: ['T20', 'T13', 'D12'],
  122: ['T18', 'T18', 'D7'],
  121: ['T20', 'T15', 'D8'],
  120: ['T20', 'S20', 'D20'],
  119: ['T20', 'T13', 'D10'],
  118: ['T20', 'S18', 'D20'],
  117: ['T20', 'S17', 'D20'],
  116: ['T20', 'S16', 'D20'],
  115: ['T20', 'S15', 'D20'],
  114: ['T20', 'S14', 'D20'],
  113: ['T20', 'S13', 'D20'],
  112: ['T20', 'S12', 'D20'],
  111: ['T20', 'S11', 'D20'],
  110: ['T20', 'DB'],
  109: ['T20', 'S9', 'D20'],
  108: ['T20', 'S16', 'D16'],
  107: ['T19', 'S10', 'D20'],
  106: ['T20', 'S6', 'D20'],
  105: ['T20', 'S5', 'D20'],
  104: ['T18', 'S18', 'D16'],
  103: ['T19', 'S6', 'D20'],
  102: ['T20', 'S10', 'D16'],
  101: ['T20', 'S9', 'D16'],
  100: ['T20', 'D20'],
  99: ['T19', 'S10', 'D16'],
  98: ['T20', 'D19'],
  97: ['T19', 'D20'],
  96: ['T20', 'D18'],
  95: ['T19', 'D19'],
  94: ['T18', 'D20'],
  93: ['T19', 'D18'],
  92: ['T20', 'D16'],
  91: ['T17', 'D20'],
  90: ['T18', 'D18'],
  89: ['T19', 'D16'],
  88: ['T16', 'D20'],
  87: ['T17', 'D18'],
  86: ['T18', 'D16'],
  85: ['T15', 'D20'],
  84: ['T20', 'D12'],
  83: ['T17', 'D16'],
  82: ['T14', 'D20'],
  81: ['T19', 'D12'],
  80: ['T20', 'D10'],
  79: ['T13', 'D20'],
  78: ['T18', 'D12'],
  77: ['T19', 'D10'],
  76: ['T20', 'D8'],
  75: ['T17', 'D12'],
  74: ['T14', 'D16'],
  73: ['T19', 'D8'],
  72: ['T16', 'D12'],
  71: ['T13', 'D16'],
  70: ['T18', 'D8'],
  69: ['T19', 'D6'],
  68: ['T20', 'D4'],
  67: ['T17', 'D8'],
  66: ['T10', 'D18'],
  65: ['T19', 'D4'],
  64: ['T16', 'D8'],
  63: ['T13', 'D12'],
  62: ['T10', 'D16'],
  61: ['T15', 'D8'],
  60: ['S20', 'D20'],
  59: ['S19', 'D20'],
  58: ['S18', 'D20'],
  57: ['S17', 'D20'],
  56: ['S16', 'D20'],
  55: ['S15', 'D20'],
  54: ['S14', 'D20'],
  53: ['S13', 'D20'],
  52: ['S12', 'D20'],
  51: ['S11', 'D20'],
  50: ['DB'],
  49: ['S9', 'D20'],
  48: ['S16', 'D16'],
  47: ['S15', 'D16'],
  46: ['S6', 'D20'],
  45: ['S13', 'D16'],
  44: ['S12', 'D16'],
  43: ['S11', 'D16'],
  42: ['S10', 'D16'],
  41: ['S9', 'D16'],
  40: ['D20'],
  39: ['S7', 'D16'],
  38: ['D19'],
  37: ['S5', 'D16'],
  36: ['D18'],
  35: ['S3', 'D16'],
  34: ['D17'],
  33: ['S1', 'D16'],
  32: ['D16'],
  31: ['S15', 'D8'],
  30: ['D15'],
  29: ['S13', 'D8'],
  28: ['D14'],
  27: ['S11', 'D8'],
  26: ['D13'],
  25: ['S9', 'D8'],
  24: ['D12'],
  23: ['S7', 'D8'],
  22: ['D11'],
  21: ['S5', 'D8'],
  20: ['D10'],
  19: ['S3', 'D8'],
  18: ['D9'],
  17: ['S1', 'D8'],
  16: ['D8'],
  15: ['S7', 'D4'],
  14: ['D7'],
  13: ['S5', 'D4'],
  12: ['D6'],
  11: ['S3', 'D4'],
  10: ['D5'],
  9: ['S1', 'D4'],
  8: ['D4'],
  7: ['S3', 'D2'],
  6: ['D3'],
  5: ['S1', 'D2'],
  4: ['D2'],
  3: ['S1', 'D1'],
  2: ['D1'],
};

/// The book route for [target], or null when the score is not finishable.
List<TrainingDart>? bookCheckoutFor(int target) {
  final notations = kBookCheckouts[target];
  if (notations == null) return null;
  return notations.map((n) => dartFromNotation(n)!).toList();
}

/// Every scoring segment on the board (no miss): S1-S20, D1-D20, T1-T20,
/// Bull 25 and D-Bull 50.
final List<TrainingDart> kAllScoringDarts = _buildScoringDarts();

List<TrainingDart> _buildScoringDarts() {
  return [
    for (var n = 1; n <= 20; n++) TrainingDart(n, ScoreMultiplier.single),
    for (var n = 1; n <= 20; n++) TrainingDart(n, ScoreMultiplier.double),
    for (var n = 1; n <= 20; n++) TrainingDart(n, ScoreMultiplier.triple),
    const TrainingDart(25, ScoreMultiplier.single),
    const TrainingDart(25, ScoreMultiplier.double),
  ];
}

final List<TrainingDart> _finishingDoubles = [
  for (var n = 1; n <= 20; n++) TrainingDart(n, ScoreMultiplier.double),
  const TrainingDart(25, ScoreMultiplier.double),
];

/// All distinct valid finishes for [target] within [dartsAllowed] darts,
/// deduplicated by dart multiset (one representative each, non-final darts
/// biggest-first). Sorted: fewer darts first, then bull-free routes, then
/// higher first dart.
List<List<TrainingDart>> validCheckoutRoutes(int target, int dartsAllowed) {
  final routes = <String, List<TrainingDart>>{};

  void addRoute(List<TrainingDart> route) {
    final key = (route.map((d) => d.notation).toList()..sort()).join(',');
    routes.putIfAbsent(key, () => route);
  }

  for (final d in _finishingDoubles) {
    if (d.points == target) addRoute([d]);
  }
  if (dartsAllowed >= 2) {
    for (final a in kAllScoringDarts) {
      final r = target - a.points;
      if (r < 2) continue;
      for (final d in _finishingDoubles) {
        if (d.points == r) addRoute([a, d]);
      }
    }
  }
  if (dartsAllowed >= 3) {
    for (final a in kAllScoringDarts) {
      final r1 = target - a.points;
      if (r1 < 4) continue;
      for (final b in kAllScoringDarts) {
        final r2 = r1 - b.points;
        if (r2 < 2) continue;
        for (final d in _finishingDoubles) {
          if (d.points == r2) {
            // Canonical representative: bigger non-final dart first.
            addRoute(a.points >= b.points ? [a, b, d] : [b, a, d]);
          }
        }
      }
    }
  }

  final result = routes.values.toList();
  bool hasBull(List<TrainingDart> r) => r.any((d) => d.baseScore == 25);
  result.sort((a, b) {
    if (a.length != b.length) return a.length - b.length;
    final bullDiff = (hasBull(a) ? 1 : 0) - (hasBull(b) ? 1 : 0);
    if (bullDiff != 0) return bullDiff;
    return b.first.points - a.first.points;
  });
  return result;
}

/// Minimum darts needed to finish [score] (1-3), or 0 when impossible.
int minDartsToCheckout(int score) {
  if (score == 50 || (score >= 2 && score <= 40 && score.isEven)) return 1;
  for (final a in kAllScoringDarts) {
    final r = score - a.points;
    if (r >= 2 && (r == 50 || (r <= 40 && r.isEven))) return 2;
  }
  return DartCallerService.isCheckout(score) ? 3 : 0;
}

final List<int> _twoDartTargets = [
  for (var s = 41; s <= 110; s++)
    if (minDartsToCheckout(s) > 0 && minDartsToCheckout(s) <= 2) s,
];

final List<int> _threeDartTargets = [
  for (var s = 111; s <= 170; s++)
    if (DartCallerService.isCheckout(s)) s,
];

/// Draws a question: mostly 2-dart finishes (41-110), sometimes a big 3-dart
/// one (111-170).
CheckoutQuestion pickCheckoutQuestion(Random rng) {
  if (rng.nextDouble() < 0.7) {
    return CheckoutQuestion(
      _twoDartTargets[rng.nextInt(_twoDartTargets.length)],
      2,
    );
  }
  return CheckoutQuestion(
    _threeDartTargets[rng.nextInt(_threeDartTargets.length)],
    3,
  );
}

/// Finishing doubles a checkout chart actually sends you to, best first.
const List<String> _chartDoubles = ['D20', 'D16', 'D18', 'D12', 'D8', 'D10'];

int _doubleRank(TrainingDart d) {
  final i = _chartDoubles.indexOf(d.notation);
  return i >= 0 ? i : _chartDoubles.length;
}

bool _isChartDouble(TrainingDart d) => _chartDoubles.contains(d.notation);

bool _isSingle(TrainingDart d) =>
    d.multiplier == ScoreMultiplier.single && d.baseScore >= 1 && d.baseScore <= 20;

bool _isTriple(TrainingDart d, int minBase) =>
    d.multiplier == ScoreMultiplier.triple && d.baseScore >= minBase;

bool _isBull(TrainingDart d) =>
    d.baseScore == 25 && d.multiplier == ScoreMultiplier.single;

bool _isDoubleBull(TrainingDart d) =>
    d.baseScore == 25 && d.multiplier == ScoreMultiplier.double;

bool _isPlainDouble(TrainingDart d) =>
    d.multiplier == ScoreMultiplier.double && d.baseScore <= 20;

/// Keeps the routes finishing on a chart double when at least one exists —
/// nobody recommends D7 when D16 does the same job.
List<List<TrainingDart>> _preferChartDoubles(List<List<TrainingDart>> routes) {
  final preferred = routes.where((r) => _isChartDouble(r.last)).toList();
  return preferred.isNotEmpty ? preferred : routes;
}

/// The routes a checkout chart would print for [target] within
/// [dartsAllowed] darts — the book route first, then the sensible
/// alternatives. "Sensible" means what charts do: singles 1-20, a chart
/// double (D20/D16/D18/D12/D8/D10) whenever one reaches, a single before a
/// triple when a single is enough, triples from T10 on two darts, a big
/// triple (T17+) leading on three, and the bull only where nothing else
/// finishes (T17+ then bull, two big triples then bull from 161, T19+ 20
/// bull). A direct
/// double-out is never padded with a two-dart alternative — except the bull,
/// which charts always back up with 10 D20 / 18 D16. Every route returned is
/// valid; a played route counts as "book" when it is in this list.
List<List<TrainingDart>> recommendedCheckoutRoutes(
  int target,
  int dartsAllowed,
) {
  final result = <List<TrainingDart>>[];
  final seen = <String>{};
  String key(List<TrainingDart> r) =>
      (r.map((d) => d.notation).toList()..sort()).join(',');
  void add(List<TrainingDart> r) {
    if (seen.add(key(r))) result.add(r);
  }

  final book = bookCheckoutFor(target);
  if (book != null && book.length <= dartsAllowed) add(book);

  final all = validCheckoutRoutes(target, dartsAllowed);
  final two = all.where((r) => r.length == 2).toList();
  final singles = _preferChartDoubles(
    two.where((r) => _isSingle(r[0]) && _isPlainDouble(r[1])).toList(),
  )..sort((a, b) => _doubleRank(a[1]) - _doubleRank(b[1]));

  final oneDart = all.where((r) => r.length == 1).toList();
  if (oneDart.isNotEmpty) {
    oneDart.forEach(add);
    if (target == 50) singles.forEach(add);
    return result;
  }

  final triples = _preferChartDoubles(
    two.where((r) => _isTriple(r[0], 10) && _isPlainDouble(r[1])).toList(),
  )..sort((a, b) {
      final t = b[0].baseScore - a[0].baseScore;
      return t != 0 ? t : _doubleRank(a[1]) - _doubleRank(b[1]);
    });
  final bullOpener = _preferChartDoubles(
    two.where((r) => _isBull(r[0]) && _isPlainDouble(r[1])).toList(),
  );
  if (singles.isNotEmpty) {
    singles.forEach(add);
  } else if (triples.isNotEmpty) {
    triples.forEach(add);
  } else {
    bullOpener.forEach(add);
    two
        .where((r) => _isTriple(r[0], 17) && _isDoubleBull(r[1]))
        .forEach(add);
  }

  final three = all.where((r) => r.length == 3).toList();
  final tripleSingle = three
      .where(
        (r) => _isTriple(r[0], 13) && _isSingle(r[1]) && _isPlainDouble(r[2]),
      )
      .toList();
  final twoTriples = three
      .where(
        (r) => _isTriple(r[0], 17) && _isTriple(r[1], 13) && _isPlainDouble(r[2]),
      )
      .toList();
  final chartThree = _preferChartDoubles([...tripleSingle, ...twoTriples]);
  final keptTripleSingle = chartThree.where((r) => _isSingle(r[1])).toList()
    ..sort((a, b) {
      final d = _doubleRank(a[2]) - _doubleRank(b[2]);
      return d != 0 ? d : b[0].baseScore - a[0].baseScore;
    });
  final keptTwoTriples = chartThree.where((r) => _isTriple(r[1], 13)).toList()
    ..sort((a, b) {
      final t = b[0].baseScore - a[0].baseScore;
      if (t != 0) return t;
      final u = b[1].baseScore - a[1].baseScore;
      return u != 0 ? u : _doubleRank(a[2]) - _doubleRank(b[2]);
    });
  keptTripleSingle.forEach(add);
  keptTwoTriples.forEach(add);
  if (chartThree.isEmpty) {
    three
        .where(
          (r) =>
              _isTriple(r[0], 17) && _isTriple(r[1], 17) && _isDoubleBull(r[2]),
        )
        .forEach(add);
  }
  three
      .where(
        (r) =>
            _isTriple(r[0], 19) &&
            _isSingle(r[1]) &&
            r[1].baseScore == 20 &&
            _isDoubleBull(r[2]),
      )
      .forEach(add);
  return result;
}

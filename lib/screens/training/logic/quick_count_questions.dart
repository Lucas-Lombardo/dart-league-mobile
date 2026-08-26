import 'dart:math';

import '../../../providers/game_provider.dart' show ScoreMultiplier;
import 'training_strategy.dart';

/// One "Compte rapide" question: you are on [startScore], the visit [visit]
/// lands — announce what is left.
class QuickCountQuestion {
  final int startScore;
  final List<TrainingDart> visit;

  QuickCountQuestion(this.startScore, this.visit);

  int get visitTotal => visit.fold(0, (a, d) => a + d.points);

  int get answer => startScore - visitTotal;
}

// Empirical weights sampled from production on 2026-08-24: 113 176 real
// three-dart visits of 501 legs (ranked, friendly and tournament matches).
// The 120 most frequent scores before a visit cover 36 % of all visits — 501
// alone is 9.4 % — the rest is spread thin between 100 and 500. Dart
// notations use the backend dialect ('S0' = miss, 'S25'/'D25' = bull).

const Map<int, int> _commonScoresBefore = {
  501: 10658,
  40: 865,
  441: 863,
  460: 722,
  456: 677,
  401: 528,
  475: 482,
  416: 425,
  420: 412,
  461: 374,
  479: 365,
  458: 335,
  360: 321,
  375: 318,
  421: 316,
  471: 314,
  415: 314,
  396: 313,
  361: 310,
  400: 308,
  60: 307,
  381: 286,
  330: 285,
  376: 281,
  80: 275,
  435: 275,
  419: 274,
  301: 274,
  341: 269,
  320: 268,
  300: 265,
  379: 263,
  281: 262,
  434: 261,
  390: 261,
  356: 260,
  280: 258,
  411: 257,
  315: 256,
  261: 256,
  355: 253,
  331: 252,
  443: 252,
  380: 252,
  371: 252,
  323: 250,
  335: 249,
  446: 247,
  321: 247,
  334: 247,
  430: 246,
  417: 246,
  279: 245,
  295: 244,
  217: 244,
  50: 242,
  351: 242,
  275: 242,
  319: 241,
  286: 240,
  268: 240,
  306: 240,
  398: 240,
  449: 240,
  357: 239,
  476: 239,
  230: 239,
  90: 238,
  385: 238,
  354: 238,
  353: 237,
  431: 237,
  358: 237,
  436: 236,
  291: 236,
  282: 235,
  336: 235,
  316: 235,
  293: 234,
  70: 234,
  238: 234,
  290: 234,
  311: 233,
  346: 233,
  206: 233,
  389: 233,
  304: 233,
  296: 232,
  242: 232,
  298: 231,
  374: 231,
  337: 231,
  307: 231,
  403: 231,
  239: 230,
  276: 230,
  386: 229,
  241: 229,
  273: 228,
  287: 228,
  339: 228,
  250: 228,
  324: 227,
  477: 227,
  289: 227,
  235: 227,
  234: 227,
  270: 226,
  216: 226,
  328: 226,
};

const Map<String, int> _scoringDarts = {
  'S20': 65589,
  'S1': 28442,
  'S5': 27451,
  'T20': 11309,
  'S19': 11227,
  'S0': 7047,
  'S7': 6674,
  'S18': 6312,
  'S3': 6104,
  'S12': 6007,
  'T1': 5547,
  'T5': 5165,
  'S4': 3431,
  'S6': 3226,
  'S9': 3205,
  'S8': 2871,
  'S10': 2810,
  'S2': 2763,
  'S11': 2243,
  'S16': 2131,
  'S13': 2113,
  'T19': 2005,
  'S14': 1946,
  'T3': 1938,
  'S17': 1899,
  'D5': 1772,
  'D1': 1701,
  'D20': 1698,
  'T7': 1680,
  'S15': 1638,
  'D3': 1569,
  'D4': 1352,
  'D6': 1198,
  'D2': 1027,
  'S25': 977,
  'D12': 903,
  'D7': 856,
  'D11': 848,
  'T18': 705,
  'T4': 693,
  'T2': 692,
  'T12': 638,
  'D9': 620,
  'D8': 617,
  'D10': 495,
  'T9': 494,
  'D13': 458,
  'D15': 437,
  'D14': 434,
  'T8': 376,
  'D19': 349,
  'T6': 269,
  'T10': 256,
  'D16': 239,
  'D18': 237,
  'T11': 212,
  'D17': 190,
  'D25': 132,
  'T16': 132,
  'T17': 126,
  'T13': 125,
  'T14': 72,
  'T15': 58,
};

const Map<String, int> _finishingDarts = {
  'S0': 19327,
  'S20': 13663,
  'S1': 7439,
  'S5': 6063,
  'S19': 4097,
  'S3': 2987,
  'S18': 2774,
  'S7': 2755,
  'T20': 2099,
  'S16': 2089,
  'S4': 1859,
  'S2': 1849,
  'S8': 1813,
  'S12': 1748,
  'S10': 1693,
  'S15': 1547,
  'S17': 1525,
  'S6': 1290,
  'S9': 1248,
  'T1': 1187,
  'S14': 1087,
  'S11': 1072,
  'S13': 987,
  'T5': 978,
  'D1': 648,
  'D20': 633,
  'T19': 599,
  'T3': 525,
  'D5': 477,
  'T7': 466,
  'S25': 429,
  'D3': 406,
  'D4': 384,
  'D6': 374,
  'D8': 331,
  'D2': 331,
  'D16': 330,
  'T18': 319,
  'D7': 314,
  'D10': 304,
  'D11': 276,
  'D12': 268,
  'D15': 233,
  'D9': 224,
  'T4': 221,
  'T2': 212,
  'D19': 195,
  'D18': 191,
  'T8': 178,
  'D13': 174,
  'T17': 167,
  'D14': 158,
  'T10': 158,
  'T9': 135,
  'D17': 133,
  'T12': 132,
  'T16': 129,
  'T6': 117,
  'D25': 115,
  'T15': 106,
  'T11': 81,
  'T14': 80,
  'T13': 69,
};

/// Share of questions whose starting score is drawn from
/// [_commonScoresBefore]; the others are uniform over 100-500.
const double _commonScoreShare = 0.36;

T _weightedPick<T>(Map<T, int> weights, Random rng) {
  var total = 0;
  for (final w in weights.values) {
    total += w;
  }
  var roll = rng.nextInt(total);
  for (final entry in weights.entries) {
    roll -= entry.value;
    if (roll < 0) return entry.key;
  }
  return weights.keys.last;
}

/// Parses a backend notation ('S0', 'S20', 'D25', 'T19').
TrainingDart _dartFromProdNotation(String notation) {
  final base = int.parse(notation.substring(1));
  switch (notation[0]) {
    case 'D':
      return TrainingDart(base, ScoreMultiplier.double);
    case 'T':
      return TrainingDart(base, ScoreMultiplier.triple);
    default:
      return TrainingDart(base, ScoreMultiplier.single);
  }
}

/// Generates a question that looks like a real 501 visit: the starting score
/// follows the production distribution, the darts follow what players
/// actually hit at that stage (scoring above 170, finishing below). The
/// visit never busts and always scores, so the answer is plain subtraction.
QuickCountQuestion generateQuickCountQuestion(Random rng) {
  while (true) {
    final start = rng.nextDouble() < _commonScoreShare
        ? _weightedPick(_commonScoresBefore, rng)
        : 100 + rng.nextInt(401);
    final table = start > 170 ? _scoringDarts : _finishingDarts;
    final visit = [
      for (var i = 0; i < 3; i++)
        _dartFromProdNotation(_weightedPick(table, rng)),
    ];
    final total = visit.fold(0, (a, d) => a + d.points);
    if (total > 0 && start - total >= 2) {
      return QuickCountQuestion(start, visit);
    }
  }
}

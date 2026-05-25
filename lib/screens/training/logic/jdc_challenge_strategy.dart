import '../../../l10n/app_localizations.dart';
import '../../../models/training.dart';
import '../../../providers/game_provider.dart' show ScoreMultiplier;
import 'training_strategy.dart';

/// JDC Challenge — the Junior Darts Corporation grading routine.
///
/// 19 visits (57 darts) split across three parts:
///   * Part 1 — Shanghai 10–15: 6 visits, 3 darts each at the current target.
///     A dart only scores when it hits the target number, with the points
///     equal to its face × multiplier. Hitting Single + Double + Triple of
///     the target in the same visit awards a +100 Shanghai bonus.
///   * Part 2 — Doubles 1–20 + Bull: 7 visits, each visit covers 3 sequential
///     targets (D1·D2·D3, D4·D5·D6, …, D19·D20·BULL). Each successful double
///     = 50 points. The final dart of Part 2 is at the bull; only a Double
///     Bull counts and scores 100 points.
///   * Part 3 — Shanghai 15–20: same as Part 1 but for 15-20.
class JdcChallengeStrategy extends TrainingStrategy {
  static const List<int> _part1Targets = [10, 11, 12, 13, 14, 15];
  static const List<int> _part3Targets = [15, 16, 17, 18, 19, 20];

  /// 21 sequential targets for Part 2. Doubles 1-20 then BULL (25 = bull).
  static const List<int> _part2Targets = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    25,
  ];

  static const int _totalVisits =
      _part1VisitCount + _part2VisitCount + _part3VisitCount;
  static const int _part1VisitCount = 6;
  static const int _part2VisitCount = 7; // 21 targets / 3 darts per visit
  static const int _part3VisitCount = 6;

  int _visitIndex = 0;
  int _totalScore = 0;
  int _totalDarts = 0;
  final List<Map<String, Object>> _visits = [];

  // ---- Phase helpers --------------------------------------------------------

  int get _part1Start => 0;
  int get _part2Start => _part1VisitCount;
  int get _part3Start => _part1VisitCount + _part2VisitCount;

  /// 1, 2 or 3.
  int _partFor(int visit) {
    if (visit < _part2Start) return 1;
    if (visit < _part3Start) return 2;
    return 3;
  }

  /// The 1–3 sequential targets that the given visit aims at, in dart order.
  /// Targets are encoded with the dartboard convention: 1-20 = that number,
  /// 25 = bull. Multiplier requirements depend on the part — see [_dartScore].
  List<int> _targetsForVisit(int visit) {
    final part = _partFor(visit);
    if (part == 1) {
      final t = _part1Targets[visit - _part1Start];
      return [t, t, t];
    }
    if (part == 3) {
      final t = _part3Targets[visit - _part3Start];
      return [t, t, t];
    }
    // Part 2: 3 sequential entries from _part2Targets.
    final start = (visit - _part2Start) * 3;
    return [
      _part2Targets[start],
      _part2Targets[start + 1],
      _part2Targets[start + 2],
    ];
  }

  /// Score earned by [dart] aimed at [target] in [part]. Misses score 0.
  int _dartScore(TrainingDart dart, int target, int part) {
    if (part == 1 || part == 3) {
      // Shanghai: any segment of the target number counts at face × multiplier.
      if (dart.baseScore != target) return 0;
      return dart.points;
    }
    // Part 2.
    if (target == 25) {
      // Final dart of Part 2: only a Double Bull counts, scoring 100.
      final isDoubleBull =
          dart.baseScore == 25 && dart.multiplier == ScoreMultiplier.double;
      return isDoubleBull ? 100 : 0;
    }
    // Doubles 1-20: flat 50 on hit, 0 otherwise.
    final isHitDouble =
        dart.baseScore == target && dart.multiplier == ScoreMultiplier.double;
    return isHitDouble ? 50 : 0;
  }

  /// Returns the Shanghai bonus (100 or 0) earned by the 3 darts of a
  /// Shanghai visit. Bonus is awarded only when at least one Single, one
  /// Double and one Triple of the target are hit in the same visit.
  int _shanghaiBonus(List<TrainingDart> darts, int target) {
    bool hitSingle = false;
    bool hitDouble = false;
    bool hitTriple = false;
    for (final d in darts) {
      if (d.baseScore != target) continue;
      switch (d.multiplier) {
        case ScoreMultiplier.single:
          hitSingle = true;
          break;
        case ScoreMultiplier.double:
          hitDouble = true;
          break;
        case ScoreMultiplier.triple:
          hitTriple = true;
          break;
      }
    }
    return (hitSingle && hitDouble && hitTriple) ? 100 : 0;
  }

  int _visitScore(List<TrainingDart> darts, int visit) {
    final part = _partFor(visit);
    final targets = _targetsForVisit(visit);
    int score = 0;
    for (int i = 0; i < darts.length && i < 3; i++) {
      score += _dartScore(darts[i], targets[i], part);
    }
    if (part == 1 || part == 3) {
      score += _shanghaiBonus(darts, targets[0]);
    }
    return score;
  }

  // ---- Display --------------------------------------------------------------

  String _labelForTarget(int target) {
    if (target == 25) return 'D-BULL';
    return 'D$target';
  }

  String _primaryLabelText(int visit) {
    final part = _partFor(visit);
    if (part == 1 || part == 3) return '$_currentSinglePart1or3Target';
    final targets = _targetsForVisit(visit);
    return targets.map(_labelForTarget).join(' · ');
  }

  int get _currentSinglePart1or3Target {
    final visit = _visitIndex.clamp(0, _totalVisits - 1);
    final part = _partFor(visit);
    if (part == 1) return _part1Targets[visit - _part1Start];
    return _part3Targets[visit - _part3Start];
  }

  String _partCaption(AppLocalizations l10n, int visit) {
    switch (_partFor(visit)) {
      case 1:
        return l10n.trainingJdcPart1Caption;
      case 2:
        return l10n.trainingJdcPart2Caption;
      default:
        return l10n.trainingJdcPart3Caption;
    }
  }

  // ---- TrainingStrategy implementation --------------------------------------

  @override
  TrainingType get trainingType => TrainingType.jdcChallenge;

  @override
  String primaryLabel(AppLocalizations l10n) => l10n.trainingNextTarget;

  @override
  String primaryValue(AppLocalizations l10n, List<TrainingDart> pending) {
    if (_visitIndex >= _totalVisits) return '—';
    return _primaryLabelText(_visitIndex);
  }

  @override
  String? secondaryLabel(AppLocalizations l10n) => l10n.trainingScore;

  @override
  String? secondaryValue(AppLocalizations l10n, List<TrainingDart> pending) {
    if (_visitIndex >= _totalVisits) return '$_totalScore';
    final preview = _visitScore(pending, _visitIndex);
    if (pending.isEmpty || preview == 0) return '$_totalScore';
    return '$_totalScore (+$preview)';
  }

  @override
  double progress(List<TrainingDart> pending) =>
      (_visitIndex / _totalVisits).clamp(0.0, 1.0);

  @override
  String? progressCaption(AppLocalizations l10n, List<TrainingDart> pending) {
    if (_visitIndex >= _totalVisits) {
      return l10n.trainingJdcPart3Caption;
    }
    return _partCaption(l10n, _visitIndex);
  }

  @override
  VisitOutcome submitVisit(List<TrainingDart> darts) {
    if (_visitIndex >= _totalVisits) {
      return VisitOutcome(finished: true);
    }
    final visit = _visitIndex;
    final part = _partFor(visit);
    final targets = _targetsForVisit(visit);

    int dartScoreSum = 0;
    final dartsLog = <Map<String, Object>>[];
    for (int i = 0; i < 3; i++) {
      final d = i < darts.length
          ? darts[i]
          : const TrainingDart(0, ScoreMultiplier.single);
      final s = _dartScore(d, targets[i], part);
      dartScoreSum += s;
      dartsLog.add({
        'notation': d.notation,
        'target': targets[i] == 25 ? 'BULL' : 'D${targets[i]}',
        'score': s,
      });
      _totalDarts++;
    }

    final shanghai =
        (part == 1 || part == 3) ? _shanghaiBonus(darts, targets[0]) : 0;
    final visitTotal = dartScoreSum + shanghai;
    _totalScore += visitTotal;
    _visits.add({
      'part': part,
      'targets': targets.map((t) => t == 25 ? 'BULL' : t).toList(),
      'darts': dartsLog,
      'shanghaiBonus': shanghai,
      'visitTotal': visitTotal,
      'scoreAfter': _totalScore,
    });
    _visitIndex++;

    final finished = _visitIndex >= _totalVisits;
    return VisitOutcome(finished: finished, completedSuccessfully: finished);
  }

  @override
  TrainingResult buildResult(AppLocalizations l10n) {
    return TrainingResult(
      score: _totalScore,
      dartsThrown: _totalDarts,
      completed: _visitIndex >= _totalVisits,
      scoreLabel: l10n.trainingFinalScore,
      details: {'visits': _visits},
    );
  }

  @override
  void reset() {
    _visitIndex = 0;
    _totalScore = 0;
    _totalDarts = 0;
    _visits.clear();
  }
}

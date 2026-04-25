import '../../../l10n/app_localizations.dart';
import '../../../models/training.dart';
import 'training_strategy.dart';

class HighScoreStrategy extends TrainingStrategy {
  static const int _roundCount = 3;

  int _roundIndex = 0;
  int _totalScore = 0;
  int _highestRound = 0;
  int _count180s = 0;
  final List<List<Map<String, Object>>> _rounds = [];

  int _pendingPoints(List<TrainingDart> pending) =>
      pending.fold<int>(0, (s, d) => s + d.points);

  int _liveTotal(List<TrainingDart> pending) =>
      _totalScore + _pendingPoints(pending);

  @override
  TrainingType get trainingType => TrainingType.highScore;

  @override
  String primaryLabel(AppLocalizations l10n) => l10n.trainingTotalScore;

  @override
  String primaryValue(AppLocalizations l10n, List<TrainingDart> pending) =>
      '${_liveTotal(pending)}';

  @override
  String? secondaryLabel(AppLocalizations l10n) => l10n.trainingRoundLabel;

  @override
  String? secondaryValue(AppLocalizations l10n, List<TrainingDart> pending) {
    final displayedRound = _roundIndex + (_roundIndex >= _roundCount ? 0 : 1);
    final pts = _pendingPoints(pending);
    if (pending.isEmpty || pts == 0) {
      return '$displayedRound / $_roundCount';
    }
    return '$displayedRound / $_roundCount  (+$pts)';
  }

  @override
  double progress(List<TrainingDart> pending) => _roundIndex / _roundCount;

  @override
  String? progressCaption(AppLocalizations l10n, List<TrainingDart> pending) =>
      l10n.trainingRoundProgress(
        _roundIndex + (_roundIndex >= _roundCount ? 0 : 1),
        _roundCount,
      );

  @override
  VisitOutcome submitVisit(List<TrainingDart> darts) {
    final roundThrows = darts
        .map((d) => {
              'notation': d.notation,
              'points': d.points,
            })
        .toList();
    final roundTotal = _pendingPoints(darts);
    _rounds.add(roundThrows);
    _totalScore += roundTotal;
    if (roundTotal > _highestRound) _highestRound = roundTotal;
    if (roundTotal == 180) _count180s++;
    _roundIndex++;
    final finished = _roundIndex >= _roundCount;
    return VisitOutcome(finished: finished, completedSuccessfully: finished);
  }

  @override
  TrainingResult buildResult(AppLocalizations l10n) {
    return TrainingResult(
      score: _totalScore,
      dartsThrown: _roundCount * 3,
      completed: _roundIndex >= _roundCount,
      scoreLabel: l10n.trainingTotalScore,
      subtitle: l10n.trainingHighestRound(_highestRound),
      details: {
        'rounds': _rounds,
        'highestRound': _highestRound,
        'count180s': _count180s,
      },
    );
  }

  @override
  void reset() {
    _roundIndex = 0;
    _totalScore = 0;
    _highestRound = 0;
    _count180s = 0;
    _rounds.clear();
  }
}

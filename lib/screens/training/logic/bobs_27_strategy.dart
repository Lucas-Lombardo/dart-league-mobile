import '../../../l10n/app_localizations.dart';
import '../../../models/training.dart';
import '../../../providers/game_provider.dart' show ScoreMultiplier;
import 'training_strategy.dart';

class Bobs27Strategy extends TrainingStrategy {
  static const List<int> _targets = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    25,
  ];

  int _score = 27;
  int _roundIndex = 0;
  int _totalDarts = 0;
  final List<Map<String, Object>> _rounds = [];

  int get _currentTarget => _targets[_roundIndex];
  bool get _isBullRound => _currentTarget == 25;
  int get _currentDoubleValue => _isBullRound ? 50 : _currentTarget * 2;

  bool _dartIsHit(TrainingDart d) {
    if (_isBullRound) {
      return d.baseScore == 25 && d.multiplier == ScoreMultiplier.double;
    }
    return d.baseScore == _currentTarget &&
        d.multiplier == ScoreMultiplier.double;
  }

  int _liveHits(List<TrainingDart> pending) {
    int hits = 0;
    for (final d in pending) {
      if (_dartIsHit(d)) hits++;
    }
    return hits;
  }

  /// What the running score would be if [pending] were committed now (i.e.
  /// treating the current round as finished after these darts).
  int _liveScorePreview(List<TrainingDart> pending) {
    if (pending.isEmpty) return _score;
    final hits = _liveHits(pending);
    final delta = hits > 0 ? _currentDoubleValue * hits : -_currentDoubleValue;
    return _score + delta;
  }

  @override
  TrainingType get trainingType => TrainingType.bobs27;

  @override
  ScoreMultiplier? get lockedMultiplier => ScoreMultiplier.double;

  @override
  String primaryLabel(AppLocalizations l10n) => l10n.trainingNextTarget;

  @override
  String primaryValue(AppLocalizations l10n, List<TrainingDart> pending) =>
      _isBullRound ? 'D-BULL' : 'D$_currentTarget';

  @override
  String? secondaryLabel(AppLocalizations l10n) => l10n.trainingScore;

  @override
  String? secondaryValue(AppLocalizations l10n, List<TrainingDart> pending) {
    final preview = _liveScorePreview(pending);
    final delta = preview - _score;
    if (pending.isEmpty || delta == 0) return '$_score';
    final sign = delta > 0 ? '+' : '';
    return '$_score ($sign$delta)';
  }

  @override
  double progress(List<TrainingDart> pending) =>
      _roundIndex / _targets.length;

  @override
  String? progressCaption(AppLocalizations l10n, List<TrainingDart> pending) =>
      l10n.trainingRoundProgress(_roundIndex + 1, _targets.length);

  @override
  VisitOutcome submitVisit(List<TrainingDart> darts) {
    int hits = 0;
    for (final d in darts) {
      _totalDarts++;
      if (_dartIsHit(d)) hits++;
    }
    final delta = hits > 0 ? _currentDoubleValue * hits : -_currentDoubleValue;
    _score += delta;
    _rounds.add({
      'target': _currentTarget,
      'hits': hits,
      'delta': delta,
      'scoreAfter': _score,
    });
    _roundIndex++;

    final bustOut = _score <= 0;
    final completed = _roundIndex >= _targets.length;
    if (bustOut || completed) {
      return VisitOutcome(
        finished: true,
        completedSuccessfully: completed && !bustOut,
      );
    }
    return VisitOutcome(finished: false);
  }

  @override
  TrainingResult buildResult(AppLocalizations l10n) {
    final completed = _score > 0 && _roundIndex >= _targets.length;
    return TrainingResult(
      score: _score,
      dartsThrown: _totalDarts,
      completed: completed,
      scoreLabel: l10n.trainingFinalScore,
      subtitle: completed ? null : l10n.trainingBustedOut,
      details: {'rounds': _rounds, 'bustOut': !completed},
    );
  }

  @override
  void reset() {
    _score = 27;
    _roundIndex = 0;
    _totalDarts = 0;
    _rounds.clear();
  }
}

import '../../../l10n/app_localizations.dart';
import '../../../models/training.dart';
import '../../../providers/game_provider.dart' show ScoreMultiplier;
import 'training_strategy.dart';

/// Checkout 50 — doubles-only finishing practice over 10 attempts.
class Checkout50Strategy extends TrainingStrategy {
  static const int _attemptsTotal = 10;
  static const int _startScore = 50;

  int _attemptIndex = 0;
  int _successes = 0;
  int _totalDarts = 0;
  final List<Map<String, Object>> _history = [];

  /// Remaining score within the current attempt after processing [pending].
  int _liveRemaining(List<TrainingDart> pending) {
    int remaining = _startScore;
    for (final d in pending) {
      if (!d.isDouble) continue;
      final v = d.points;
      if (v > remaining) continue;
      remaining -= v;
      if (remaining == 0) break;
    }
    return remaining;
  }

  @override
  TrainingType get trainingType => TrainingType.checkout50;

  @override
  ScoreMultiplier? get lockedMultiplier => ScoreMultiplier.double;

  @override
  String primaryLabel(AppLocalizations l10n) => l10n.trainingRemaining;

  @override
  String primaryValue(AppLocalizations l10n, List<TrainingDart> pending) =>
      '${_liveRemaining(pending)}';

  @override
  String? secondaryLabel(AppLocalizations l10n) => l10n.trainingCheckouts;

  @override
  String? secondaryValue(AppLocalizations l10n, List<TrainingDart> pending) =>
      '$_successes / $_attemptsTotal';

  @override
  double progress(List<TrainingDart> pending) =>
      _attemptIndex / _attemptsTotal;

  @override
  String? progressCaption(AppLocalizations l10n, List<TrainingDart> pending) =>
      l10n.trainingAttemptProgress(_attemptIndex + 1, _attemptsTotal);

  @override
  VisitOutcome submitVisit(List<TrainingDart> darts) {
    int remaining = _startScore;
    int dartsUsed = 0;
    bool success = false;
    for (final d in darts) {
      _totalDarts++;
      dartsUsed++;
      if (!d.isDouble) continue;
      final v = d.points;
      if (v > remaining) continue;
      remaining -= v;
      if (remaining == 0) {
        success = true;
        break;
      }
    }
    if (success) _successes++;
    _history.add({'darts': dartsUsed, 'success': success});
    _attemptIndex++;
    final finished = _attemptIndex >= _attemptsTotal;
    return VisitOutcome(finished: finished, completedSuccessfully: finished);
  }

  @override
  TrainingResult buildResult(AppLocalizations l10n) {
    return TrainingResult(
      score: _successes,
      dartsThrown: _totalDarts,
      completed: _attemptIndex >= _attemptsTotal,
      scoreLabel: l10n.trainingCheckouts,
      subtitle:
          l10n.trainingCheckoutsOutOf(_successes, _attemptsTotal),
      details: {
        'startScore': _startScore,
        'attempts': _attemptsTotal,
        'successes': _successes,
        'history': _history,
      },
    );
  }

  @override
  void reset() {
    _attemptIndex = 0;
    _successes = 0;
    _totalDarts = 0;
    _history.clear();
  }
}

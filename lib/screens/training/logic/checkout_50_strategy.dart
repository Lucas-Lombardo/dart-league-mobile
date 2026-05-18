import '../../../l10n/app_localizations.dart';
import '../../../models/training.dart';
import 'training_strategy.dart';

/// Checkout 50 — 10 attempts, 3 darts each. Standard X01 checkout rules:
/// any combination of darts is allowed, but the final dart that brings the
/// score to 0 must be a double (or double bull). 1 point per successful
/// checkout.
class Checkout50Strategy extends TrainingStrategy {
  static const int _attemptsTotal = 10;
  static const int _startScore = 50;

  int _attemptIndex = 0;
  int _successes = 0;
  int _totalDarts = 0;
  final List<Map<String, Object>> _history = [];

  /// Live remaining score within the current attempt after applying [pending]
  /// under standard X01 rules. Returns 50 if pending busts so the displayed
  /// "remaining" doesn't lie about progress.
  int _liveRemaining(List<TrainingDart> pending) {
    int remaining = _startScore;
    for (final d in pending) {
      final v = d.points;
      final next = remaining - v;
      if (next < 0) return _startScore; // bust
      if (next == 0 && !d.isDouble) return _startScore; // bust: not on double
      if (next == 1) return _startScore; // bust: cannot finish from 1
      remaining = next;
      if (remaining == 0) break;
    }
    return remaining;
  }

  @override
  TrainingType get trainingType => TrainingType.checkout50;

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
    String? bustReason;
    final notations = <String>[];

    for (final d in darts) {
      // Stop processing further darts once the attempt is decided (either
      // checkout or bust). The remaining "padded miss" darts in the visit
      // array don't count toward darts thrown.
      if (success || bustReason != null) break;
      dartsUsed++;
      notations.add(d.notation);
      final v = d.points;
      final next = remaining - v;
      if (next < 0) {
        bustReason = 'below_zero';
      } else if (next == 0 && !d.isDouble) {
        bustReason = 'not_double_finish';
      } else if (next == 1) {
        bustReason = 'left_one';
      } else {
        remaining = next;
        if (remaining == 0 && d.isDouble) success = true;
      }
    }

    _totalDarts += dartsUsed;
    if (success) _successes++;
    _history.add({
      'darts': dartsUsed,
      'success': success,
      'bustReason': bustReason ?? '',
      'throws': notations,
    });
    _attemptIndex++;

    final finished = _attemptIndex >= _attemptsTotal;
    return VisitOutcome(
      finished: finished,
      // Only completed if all attempts ran their course.
      completedSuccessfully: finished,
      bustReason: bustReason,
    );
  }

  @override
  TrainingResult buildResult(AppLocalizations l10n) {
    return TrainingResult(
      score: _successes,
      dartsThrown: _totalDarts,
      completed: _attemptIndex >= _attemptsTotal,
      scoreLabel: l10n.trainingCheckouts,
      subtitle: l10n.trainingCheckoutsOutOf(_successes, _attemptsTotal),
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

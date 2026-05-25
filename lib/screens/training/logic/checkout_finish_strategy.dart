import '../../../l10n/app_localizations.dart';
import '../../../models/training.dart';
import 'training_strategy.dart';

/// Progressive 81 / 121 checkout. Each attempt gives the player up to
/// [_visitsPerAttempt] 3-dart visits (i.e. 9 darts) to check out from the
/// current target under standard X01 rules (last dart must be a double).
/// Within an attempt: a busted visit is spent but the remaining reverts to
/// what it was at the start of that visit; a clean visit advances the
/// remaining. A successful checkout advances the target by +1 for the next
/// attempt; running out of visits without a finish resets the target to
/// [startScore]. The session lasts a fixed number of attempts and the score
/// is the highest target the player reached.
class CheckoutFinishStrategy extends TrainingStrategy {
  static const int _attemptsTotal = 10;
  static const int _visitsPerAttempt = 3;

  final int startScore;
  late int _target = startScore;
  late int _remaining = startScore;
  int _visitsUsedInAttempt = 0;
  int _attemptDartsUsed = 0;
  final List<String> _attemptThrows = [];
  int _attemptIndex = 0;
  int _successes = 0;
  int _highestReached = 0;
  int _totalDarts = 0;
  final List<Map<String, Object>> _history = [];

  CheckoutFinishStrategy({required this.startScore})
      : assert(startScore == 81 || startScore == 121);

  /// Live remaining score within the current visit after applying [pending]
  /// under standard X01 rules. Returns the pre-visit remaining if pending
  /// busts so the displayed "remaining" doesn't lie about progress.
  int _liveRemaining(List<TrainingDart> pending) {
    int remaining = _remaining;
    for (final d in pending) {
      final v = d.points;
      final next = remaining - v;
      if (next < 0) return _remaining;
      if (next == 0 && !d.isDouble) return _remaining;
      if (next == 1) return _remaining;
      remaining = next;
      if (remaining == 0) break;
    }
    return remaining;
  }

  @override
  TrainingType get trainingType =>
      startScore == 81 ? TrainingType.checkout81 : TrainingType.checkout121;

  @override
  String primaryLabel(AppLocalizations l10n) => l10n.trainingRemaining;

  @override
  String primaryValue(AppLocalizations l10n, List<TrainingDart> pending) =>
      '${_liveRemaining(pending)}';

  @override
  String? secondaryLabel(AppLocalizations l10n) => l10n.trainingHighestReached;

  @override
  String? secondaryValue(AppLocalizations l10n, List<TrainingDart> pending) =>
      '$_highestReached';

  @override
  double progress(List<TrainingDart> pending) =>
      _attemptIndex / _attemptsTotal;

  @override
  String? progressCaption(AppLocalizations l10n, List<TrainingDart> pending) {
    final attempt =
        l10n.trainingAttemptProgress(_attemptIndex + 1, _attemptsTotal);
    final visit = l10n.trainingVisitProgress(
        _visitsUsedInAttempt + 1, _visitsPerAttempt);
    return '$attempt · $visit';
  }

  @override
  VisitOutcome submitVisit(List<TrainingDart> darts) {
    int remaining = _remaining;
    int dartsUsed = 0;
    bool success = false;
    String? bustReason;
    final notations = <String>[];

    for (final d in darts) {
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
    _attemptDartsUsed += dartsUsed;
    _attemptThrows.addAll(notations);
    _visitsUsedInAttempt++;

    if (bustReason == null) {
      _remaining = remaining;
    }
    // Bust: _remaining stays unchanged — score reverts to pre-visit value.

    final attemptComplete =
        success || _visitsUsedInAttempt >= _visitsPerAttempt;

    if (attemptComplete) {
      final attemptTarget = _target;
      if (attemptTarget > _highestReached) _highestReached = attemptTarget;
      if (success) {
        _successes++;
        _target = attemptTarget + 1;
      } else {
        _target = startScore;
      }
      _history.add({
        'target': attemptTarget,
        'darts': _attemptDartsUsed,
        'visits': _visitsUsedInAttempt,
        'success': success,
        'bustReason': bustReason ?? (success ? '' : 'out_of_darts'),
        'throws': List<String>.from(_attemptThrows),
      });
      _attemptIndex++;
      _remaining = _target;
      _visitsUsedInAttempt = 0;
      _attemptDartsUsed = 0;
      _attemptThrows.clear();
    }

    final finished = _attemptIndex >= _attemptsTotal;
    return VisitOutcome(
      finished: finished,
      completedSuccessfully: finished,
      bustReason: bustReason,
    );
  }

  @override
  TrainingResult buildResult(AppLocalizations l10n) {
    return TrainingResult(
      score: _highestReached,
      dartsThrown: _totalDarts,
      completed: _attemptIndex >= _attemptsTotal,
      scoreLabel: l10n.trainingHighestReached,
      subtitle: l10n.trainingCheckoutsOutOf(_successes, _attemptsTotal),
      details: {
        'startScore': startScore,
        'attempts': _attemptsTotal,
        'visitsPerAttempt': _visitsPerAttempt,
        'successes': _successes,
        'highestReached': _highestReached,
        'history': _history,
      },
    );
  }

  @override
  void reset() {
    _target = startScore;
    _remaining = startScore;
    _visitsUsedInAttempt = 0;
    _attemptDartsUsed = 0;
    _attemptThrows.clear();
    _attemptIndex = 0;
    _successes = 0;
    _highestReached = 0;
    _totalDarts = 0;
    _history.clear();
  }
}

import '../../../l10n/app_localizations.dart';
import '../../../models/training.dart';
import 'training_strategy.dart';

/// 81 / 121 checkout: up to 9 darts (3 visits) to finish exactly, last dart
/// must be a double. X01 bust rules apply.
class CheckoutFinishStrategy extends TrainingStrategy {
  static const int _dartsAllowed = 9;

  final int startScore;
  late int _score = startScore;
  int _dartsThrown = 0;
  bool _success = false;
  String? _bustReason;
  final List<String> _notations = [];

  CheckoutFinishStrategy({required this.startScore})
      : assert(startScore == 81 || startScore == 121);

  /// Project the current remaining score forward with [pending] darts applied
  /// (without mutating committed state). Bust rules halt the projection.
  int _liveRemaining(List<TrainingDart> pending) {
    if (_success || _bustReason != null) return _score;
    int remaining = _score;
    for (final d in pending) {
      final v = d.points;
      final next = remaining - v;
      if (next < 0) break; // bust preview
      if (next == 0 && !d.isDouble) break;
      if (next == 1) break;
      remaining = next;
      if (next == 0 && d.isDouble) break;
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
  String? secondaryLabel(AppLocalizations l10n) => l10n.trainingDartsThrown;

  @override
  String? secondaryValue(AppLocalizations l10n, List<TrainingDart> pending) =>
      '${_dartsThrown + pending.length} / $_dartsAllowed';

  @override
  double progress(List<TrainingDart> pending) =>
      (_dartsThrown + pending.length) / _dartsAllowed;

  @override
  String? progressCaption(AppLocalizations l10n, List<TrainingDart> pending) =>
      l10n.trainingCheckoutFromN(startScore);

  @override
  VisitOutcome submitVisit(List<TrainingDart> darts) {
    for (final d in darts) {
      if (_success || _bustReason != null) break;
      _dartsThrown++;
      _notations.add(d.notation);
      final v = d.points;
      final newScore = _score - v;
      if (newScore < 0) {
        _bustReason = 'below_zero';
      } else if (newScore == 0 && !d.isDouble) {
        _bustReason = 'not_double_finish';
      } else if (newScore == 1) {
        _bustReason = 'left_one';
      } else {
        _score = newScore;
        if (newScore == 0 && d.isDouble) {
          _success = true;
        }
      }
    }
    if (_success) {
      return VisitOutcome(finished: true, completedSuccessfully: true);
    }
    if (_bustReason != null) {
      return VisitOutcome(finished: true, completedSuccessfully: false);
    }
    if (_dartsThrown >= _dartsAllowed) {
      _bustReason = 'out_of_darts';
      return VisitOutcome(finished: true, completedSuccessfully: false);
    }
    return VisitOutcome(finished: false);
  }

  String _bustLabel(AppLocalizations l10n) {
    switch (_bustReason) {
      case 'below_zero':
        return l10n.trainingBustBelowZero;
      case 'not_double_finish':
        return l10n.trainingBustNotDouble;
      case 'left_one':
        return l10n.trainingBustLeftOne;
      case 'out_of_darts':
        return l10n.trainingBustOutOfDarts;
    }
    return l10n.trainingBustedOut;
  }

  @override
  TrainingResult buildResult(AppLocalizations l10n) {
    return TrainingResult(
      score: _success ? _dartsThrown : 0,
      dartsThrown: _dartsThrown,
      completed: _success,
      scoreLabel: _success
          ? l10n.trainingDartsToFinish
          : l10n.trainingBusted,
      subtitle: _success ? null : _bustLabel(l10n),
      details: {
        'startScore': startScore,
        'success': _success,
        'bustReason': _bustReason,
        'throws': _notations,
        'finalRemaining': _score,
      },
    );
  }

  @override
  void reset() {
    _score = startScore;
    _dartsThrown = 0;
    _success = false;
    _bustReason = null;
    _notations.clear();
  }
}

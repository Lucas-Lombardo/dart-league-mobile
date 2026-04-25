import '../../../l10n/app_localizations.dart';
import '../../../models/training.dart';
import '../../../providers/game_provider.dart' show ScoreMultiplier;
import 'atc_mode.dart';
import 'training_strategy.dart';

class AtcStrategy extends TrainingStrategy {
  static const List<int> _sequence = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
    11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
    25,
  ];

  final AtcMode mode;
  int _targetIndex = 0;
  int _dartsThrown = 0;
  final List<int> _missesPerTarget = List.filled(_sequence.length, 0);

  AtcStrategy({this.mode = AtcMode.single});

  /// A dart counts as a hit against [target] if its sector matches AND its
  /// ring matches the current mode.
  ///
  /// **Single mode counts the whole sector**: single, double or triple — any
  /// ring on the target number counts. Bull round accepts single or double
  /// bull.
  ///
  /// **Double mode** requires the double ring (or the double bull on the
  /// bull round).
  ///
  /// **Triple mode** requires the triple ring. Since there's no triple bull,
  /// the bull round accepts the double bull.
  bool _dartHitsTarget(TrainingDart d, int target) {
    if (d.baseScore != target) return false;
    if (target == 25) {
      if (mode == AtcMode.single) return true; // any bull
      return d.multiplier == ScoreMultiplier.double; // D-Bull
    }
    switch (mode) {
      case AtcMode.single:
        // Any hit on the sector — single/double/triple all count.
        return true;
      case AtcMode.double:
        return d.multiplier == ScoreMultiplier.double;
      case AtcMode.triple:
        return d.multiplier == ScoreMultiplier.triple;
    }
  }

  /// Live target index taking [pending] into account (no mutation).
  int _liveTargetIndex(List<TrainingDart> pending) {
    int idx = _targetIndex;
    for (final d in pending) {
      if (idx >= _sequence.length) break;
      if (_dartHitsTarget(d, _sequence[idx])) idx++;
    }
    return idx;
  }

  int _liveDartsThrown(List<TrainingDart> pending) =>
      _dartsThrown + pending.length;

  String _labelForTarget(int t, AppLocalizations l10n) {
    if (t == 25) {
      return mode == AtcMode.single
          ? l10n.trainingBullLabel
          : 'D-${l10n.trainingBullLabel}';
    }
    switch (mode) {
      case AtcMode.single:
        return '$t';
      case AtcMode.double:
        return 'D$t';
      case AtcMode.triple:
        return 'T$t';
    }
  }

  @override
  TrainingType get trainingType {
    switch (mode) {
      case AtcMode.single:
        return TrainingType.aroundTheClock;
      case AtcMode.double:
        return TrainingType.aroundTheClockDouble;
      case AtcMode.triple:
        return TrainingType.aroundTheClockTriple;
    }
  }

  @override
  String primaryLabel(AppLocalizations l10n) => l10n.trainingNextTarget;

  @override
  String primaryValue(AppLocalizations l10n, List<TrainingDart> pending) {
    final idx = _liveTargetIndex(pending);
    if (idx >= _sequence.length) {
      return mode == AtcMode.single
          ? l10n.trainingBullLabel
          : 'D-${l10n.trainingBullLabel}';
    }
    return _labelForTarget(_sequence[idx], l10n);
  }

  @override
  String? secondaryLabel(AppLocalizations l10n) => l10n.trainingDartsThrown;

  @override
  String? secondaryValue(AppLocalizations l10n, List<TrainingDart> pending) =>
      '${_liveDartsThrown(pending)}';

  @override
  double progress(List<TrainingDart> pending) =>
      _liveTargetIndex(pending) / _sequence.length;

  @override
  String? progressCaption(AppLocalizations l10n, List<TrainingDart> pending) =>
      '${_liveTargetIndex(pending)} / ${_sequence.length}';

  @override
  VisitOutcome submitVisit(List<TrainingDart> darts) {
    for (final d in darts) {
      _dartsThrown++;
      if (_targetIndex >= _sequence.length) break;
      if (_dartHitsTarget(d, _sequence[_targetIndex])) {
        _targetIndex++;
      } else {
        _missesPerTarget[_targetIndex]++;
      }
    }
    if (_targetIndex >= _sequence.length) {
      return VisitOutcome(finished: true, completedSuccessfully: true);
    }
    return VisitOutcome(finished: false);
  }

  @override
  TrainingResult buildResult(AppLocalizations l10n) {
    return TrainingResult(
      score: _dartsThrown,
      dartsThrown: _dartsThrown,
      completed: _targetIndex >= _sequence.length,
      scoreLabel: l10n.trainingDartsToFinish,
      details: {
        'mode': mode.name,
        'missesPerTarget': {
          for (int i = 0; i < _sequence.length; i++)
            _sequence[i].toString(): _missesPerTarget[i],
        },
      },
    );
  }

  @override
  void reset() {
    _targetIndex = 0;
    _dartsThrown = 0;
    for (int i = 0; i < _missesPerTarget.length; i++) {
      _missesPerTarget[i] = 0;
    }
  }
}

import '../../../l10n/app_localizations.dart';
import '../../../models/training.dart';
import '../../../providers/game_provider.dart' show ScoreMultiplier;
import 'training_strategy.dart';

/// Important Doubles — a repetition drill on the doubles that actually close
/// legs. The player picks one or two targets from [keyDoubles] and throws
/// [dartsPerDouble] darts at each, one block after the other (60, then 60).
///
/// [keyDoubles] are the eight doubles that finished 79% of the 1 225 ranked
/// legs played on Dart Rivals between 14 May and 30 July 2026, listed in that
/// frequency order — the remaining thirteen split the other 20%.
///
/// A dart counts only when it lands in the double ring of the current target;
/// everything else (single, triple, wrong number, miss) is a miss. The session
/// score is the hit rate in percent, which stays comparable whether the player
/// trained one double or two.
class ImportantDoublesStrategy extends TrainingStrategy {
  static const List<int> keyDoubles = [1, 20, 10, 2, 8, 16, 4, 5];
  static const int dartsPerDouble = 60;

  /// One or two doubles, played as consecutive blocks in this order.
  final List<int> targets;

  ImportantDoublesStrategy({required this.targets})
    : assert(targets.isNotEmpty && targets.length <= 2);

  // Current block.
  int _blockIndex = 0;
  int _dartsInBlock = 0;
  int _hitsInBlock = 0;
  final List<int> _visitHits = [];

  // Finished blocks + running totals.
  final List<Map<String, Object>> _blocks = [];
  int _totalDarts = 0;
  int _totalHits = 0;

  bool get _allBlocksDone => _blockIndex >= targets.length;
  int get _currentTarget => targets[_blockIndex.clamp(0, targets.length - 1)];
  int get _plannedDarts => targets.length * dartsPerDouble;

  bool _isHit(TrainingDart d) =>
      d.baseScore == _currentTarget && d.multiplier == ScoreMultiplier.double;

  /// Darts of [pending] that still fit in the current block — the screen may
  /// hand over three darts when the block has fewer left.
  int _liveDarts(List<TrainingDart> pending) =>
      pending.length.clamp(0, dartsPerDouble - _dartsInBlock);

  int _liveHits(List<TrainingDart> pending) {
    int hits = 0;
    for (final d in pending.take(_liveDarts(pending))) {
      if (_isHit(d)) hits++;
    }
    return hits;
  }

  @override
  TrainingType get trainingType => TrainingType.importantDoubles;

  @override
  ScoreMultiplier? get lockedMultiplier => ScoreMultiplier.double;

  @override
  String primaryLabel(AppLocalizations l10n) => l10n.trainingTargetLabel;

  @override
  String primaryValue(AppLocalizations l10n, List<TrainingDart> pending) =>
      _allBlocksDone ? '—' : 'D$_currentTarget';

  @override
  String? secondaryLabel(AppLocalizations l10n) => l10n.trainingHitRate;

  /// Hits over the darts actually thrown, plus the rate they add up to — the
  /// two numbers the drill is about. Counting against [dartsPerDouble] instead
  /// would read as "0/60" on the first dart, as if 60 had already been missed.
  @override
  String? secondaryValue(AppLocalizations l10n, List<TrainingDart> pending) {
    final hits = _allBlocksDone
        ? _totalHits
        : _hitsInBlock + _liveHits(pending);
    final darts = _allBlocksDone
        ? _totalDarts
        : _dartsInBlock + _liveDarts(pending);
    if (darts == 0) return '—';
    return '$hits/$darts · ${hitRatePercent(hits, darts)}%';
  }

  @override
  double progress(List<TrainingDart> pending) =>
      ((_totalDarts + _liveDarts(pending)) / _plannedDarts).clamp(0.0, 1.0);

  @override
  String? progressCaption(AppLocalizations l10n, List<TrainingDart> pending) {
    if (_allBlocksDone) return null;
    final thrown = _dartsInBlock + _liveDarts(pending);
    if (targets.length == 1) {
      return l10n.trainingDartsProgress(thrown, dartsPerDouble);
    }
    return '${l10n.trainingBlockProgress(_blockIndex + 1, targets.length)}'
        ' · $thrown/$dartsPerDouble';
  }

  @override
  VisitOutcome submitVisit(List<TrainingDart> darts) {
    if (_allBlocksDone) return VisitOutcome(finished: true);

    // The screen always hands over three darts, padding a visit the player
    // ended early with misses — so a block is exactly 20 visits. Capping on
    // the darts the block has left keeps the count honest either way.
    final remaining = dartsPerDouble - _dartsInBlock;
    final thrown = darts.take(remaining).toList();

    int hits = 0;
    for (final d in thrown) {
      if (_isHit(d)) hits++;
    }
    _visitHits.add(hits);
    _hitsInBlock += hits;
    _dartsInBlock += thrown.length;
    _totalHits += hits;
    _totalDarts += thrown.length;

    if (_dartsInBlock >= dartsPerDouble) {
      _blocks.add({
        'target': _currentTarget,
        'hits': _hitsInBlock,
        'darts': _dartsInBlock,
        // Hits per visit — drives the in-session curve and the regularity
        // read on the progress screen.
        'visits': List<int>.from(_visitHits),
      });
      _blockIndex++;
      _dartsInBlock = 0;
      _hitsInBlock = 0;
      _visitHits.clear();
    }

    final done = _allBlocksDone;
    return VisitOutcome(finished: done, completedSuccessfully: done);
  }

  @override
  TrainingResult buildResult(AppLocalizations l10n) {
    final hitRate = hitRatePercent(_totalHits, _totalDarts);
    final recap = _blocks
        .map((b) => 'D${b['target']} ${b['hits']}/${b['darts']}')
        .join(' · ');
    return TrainingResult(
      score: hitRate,
      dartsThrown: _totalDarts,
      completed: _allBlocksDone,
      scoreLabel: l10n.trainingHitRatePercent,
      subtitle: recap.isEmpty ? null : recap,
      details: {'doubles': _blocks, 'hits': _totalHits, 'hitRate': hitRate},
    );
  }

  @override
  void reset() {
    _blockIndex = 0;
    _dartsInBlock = 0;
    _hitsInBlock = 0;
    _visitHits.clear();
    _blocks.clear();
    _totalDarts = 0;
    _totalHits = 0;
  }
}

/// Hit rate as a rounded percentage, shared by the drill and the progress
/// screen so a session always reads the same number in both places.
int hitRatePercent(int hits, int darts) =>
    darts == 0 ? 0 : (hits * 100 / darts).round();

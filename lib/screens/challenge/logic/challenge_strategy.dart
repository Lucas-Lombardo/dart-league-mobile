import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/training.dart';
import '../../../providers/game_provider.dart' show ScoreMultiplier;
import '../../training/logic/training_strategy.dart';
import '../challenge_models.dart';
import 'challenge_engine.dart';

/// Converts a dart of the AI pipeline to the challenge engine's.
ChallengeDart challengeDartOf(TrainingDart d) {
  if (d.baseScore == 0) return ChallengeDart.miss;
  if (d.baseScore == 25) {
    return d.multiplier == ScoreMultiplier.double
        ? const ChallengeDart(25, 2, 50)
        : const ChallengeDart(25, 1, 25);
  }
  final mult = switch (d.multiplier) {
    ScoreMultiplier.single => 1,
    ScoreMultiplier.double => 2,
    ScoreMultiplier.triple => 3,
  };
  return ChallengeDart(d.baseScore, mult, d.baseScore * mult);
}

TrainingType? _trainingTypeOf(String? api) {
  if (api == null) return null;
  try {
    return TrainingTypeX.fromApi(api);
  } catch (_) {
    return null;
  }
}

/// A daily-challenge format played through the shared AI training view
/// (TrainingGameView): the engine is replayed over the committed visits plus
/// the darts of the visit in progress, so the focal value reacts per dart.
class ChallengeStrategy extends TrainingStrategy {
  final ChallengeFormat format;
  final List<List<ChallengeDart>> _visits = [];

  ChallengeStrategy(this.format);

  List<List<ChallengeDart>> get visits => List.unmodifiable(_visits);

  ChallengeEngineResult _run({List<TrainingDart> pending = const []}) {
    final all = [
      ..._visits,
      if (pending.isNotEmpty) pending.map(challengeDartOf).toList(),
    ];
    return runChallengeEngine(
          format.mode,
          format.params,
          format.dayParams,
          all,
          partialLast: pending.isNotEmpty,
        ) ??
        const ChallengeEngineResult(score: 0, tiebreak: 0, darts: 0, visits: 0, finished: true, perVisit: []);
  }

  /// The result of the committed visits.
  ChallengeEngineResult get result => _run();

  @override
  TrainingType get trainingType => _trainingTypeOf(format.trainingType) ?? TrainingType.highScore;

  @override
  ScoreMultiplier? get lockedMultiplier => null;

  bool get _targetMode => const {'bobs_27', 'doubles_block', 'atc', 'shanghai', 'halve_it', 'jdc'}.contains(format.mode);
  bool get _remainingMode => format.mode == 'x01' || format.mode == 'checkout_set';

  @override
  String primaryLabel(AppLocalizations l10n) {
    if (_targetMode) return l10n.challengePlayTarget;
    if (_remainingMode) return l10n.challengePlayRemaining;
    if (format.mode == 'cricket_marks') return l10n.challengePlayMarks;
    return l10n.challengePlayTotal;
  }

  String _targetLabel(AppLocalizations l10n, Map<String, Object?> cursor) {
    final halve = cursor['halveTarget'];
    if (halve is Map) {
      if (halve['ring'] == 'double') return l10n.challengeAnyDouble;
      if (halve['ring'] == 'triple') return l10n.challengeAnyTriple;
      final n = halve['n'];
      return n == 25 ? l10n.trainingBullLabel : '$n';
    }
    final targets = cursor['targets'];
    final ring = cursor['ring'];
    String one(int t) {
      if (t == 25) return ring == 'any' ? l10n.trainingBullLabel : 'D-${l10n.trainingBullLabel}';
      return switch (ring) {
        'double' => 'D$t',
        'triple' => 'T$t',
        _ => '$t',
      };
    }

    if (targets is List && targets.isNotEmpty) {
      return targets.whereType<int>().map(one).join(' · ');
    }
    final target = cursor['target'];
    return target is int ? one(target) : '—';
  }

  @override
  String primaryValue(AppLocalizations l10n, List<TrainingDart> pending) {
    if (_targetMode) {
      // Round-based modes keep the round's target until the visit is done;
      // dart-based ones (clock, doubles block) move with each dart.
      final perDart = format.mode == 'atc' || format.mode == 'doubles_block';
      final r = perDart ? _run(pending: pending) : _run();
      return _targetLabel(l10n, r.cursor);
    }
    final r = _run(pending: pending);
    if (_remainingMode) return '${r.cursor['remaining'] ?? 0}';
    return '${r.score}';
  }

  @override
  String? secondaryLabel(AppLocalizations l10n) => switch (format.mode) {
        'high_score' => l10n.challengePlayVisit,
        'target_points' || 'cricket_marks' || 'atc' || 'x01' => l10n.challengePlayDarts,
        'doubles_block' => l10n.challengePlayHits,
        'checkout_set' => l10n.challengePlayScore,
        _ => l10n.challengePlayPoints,
      };

  @override
  String? secondaryValue(AppLocalizations l10n, List<TrainingDart> pending) {
    final r = _run(pending: pending);
    final c = r.cursor;
    return switch (format.mode) {
      'high_score' => '${_visits.length + (r.finished ? 0 : 1)} / ${c['visitCount']}',
      'target_points' || 'cricket_marks' => '${r.darts} / ${c['dartCount']}',
      'atc' || 'x01' => '${r.darts}',
      _ => '${r.score}',
    };
  }

  @override
  double progress(List<TrainingDart> pending) {
    final r = _run(pending: pending);
    final c = r.cursor;
    double ratio(Object? a, Object? b) => (a is num && b is num && b > 0) ? (a / b).clamp(0, 1).toDouble() : 0;
    return switch (format.mode) {
      'high_score' => ratio(r.visits, c['visitCount']),
      'target_points' || 'cricket_marks' || 'doubles_block' => ratio(r.darts, c['dartCount']),
      'checkout_set' => ratio(c['finishIndex'], c['finishCount']),
      'x01' => 1 - ratio(c['remaining'], format.params['start'] ?? 501),
      _ => ratio(c['targetIndex'], c['targetCount']),
    };
  }

  @override
  String? progressCaption(AppLocalizations l10n, List<TrainingDart> pending) {
    final r = _run(pending: pending);
    final c = r.cursor;
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    switch (format.mode) {
      case 'high_score':
        final n = asInt(c['visitCount']);
        return l10n.challengeVisitProgress((_visits.length + 1).clamp(1, n), n);
      case 'target_points':
      case 'cricket_marks':
      case 'doubles_block':
        final n = asInt(c['dartCount']);
        return l10n.challengeDartProgress(r.darts.clamp(0, n), n);
      case 'checkout_set':
        final committed = _run().cursor;
        final n = asInt(committed['finishCount']);
        return l10n.challengeCheckoutProgress(
          (asInt(committed['finishIndex']) + 1).clamp(1, n == 0 ? 1 : n),
          n,
          asInt(committed['budgetUsed']),
          asInt(committed['budget']),
        );
      case 'x01':
        return l10n.challengeDartProgress(r.darts, asInt(c['cap']));
      default:
        final n = asInt(c['targetCount']);
        return l10n.challengeTargetProgress((asInt(c['targetIndex']) + 1).clamp(1, n == 0 ? 1 : n), n);
    }
  }

  @override
  VisitOutcome submitVisit(List<TrainingDart> darts) {
    _visits.add(darts.map(challengeDartOf).toList());
    final r = _run();
    return VisitOutcome(finished: r.finished, completedSuccessfully: r.finished);
  }

  @override
  TrainingResult buildResult(AppLocalizations l10n) {
    final r = _run();
    return TrainingResult(
      score: r.score,
      dartsThrown: r.darts,
      completed: r.finished,
      scoreLabel: l10n.challengePlayScore,
      details: {
        'visits': [for (final v in _visits) v.map((d) => d.notation).toList()],
      },
    );
  }

  @override
  void reset() => _visits.clear();
}

/// The score as shown in lists: "587", or "—" for an unfinished
/// fewest-darts session (it ranks after every finisher).
String challengeScoreText(ChallengeFormat? format, int score, {bool finished = true, String unfinished = '—'}) {
  final cap = format?.cap;
  if (cap != null && score > cap) return unfinished;
  return '$score';
}

/// "points", "darts"… in the current language.
String challengeUnit(BuildContext context, ChallengeFormat? format) =>
    format?.unit?.resolve(context) ?? '';

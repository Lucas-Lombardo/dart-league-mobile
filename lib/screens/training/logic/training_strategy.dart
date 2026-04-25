import '../../../l10n/app_localizations.dart';
import '../../../models/training.dart';
import '../../../providers/game_provider.dart' show ScoreMultiplier;

/// Outcome of submitting a single 3-dart visit to a training strategy.
class VisitOutcome {
  /// True when the training session is over (either completed successfully
  /// or busted out). The caller should stop capture and show the end screen.
  final bool finished;

  /// True only when the session ended *successfully*. Busted-out sessions
  /// set [finished] = true but [completedSuccessfully] = false.
  final bool completedSuccessfully;

  VisitOutcome({
    required this.finished,
    this.completedSuccessfully = true,
  });
}

/// Data returned when a strategy is ready to build the end-of-session payload.
class TrainingResult {
  final int score;
  final int dartsThrown;
  final bool completed;
  final String scoreLabel;
  final String? subtitle;
  final Map<String, dynamic>? details;

  TrainingResult({
    required this.score,
    required this.dartsThrown,
    required this.completed,
    required this.scoreLabel,
    this.subtitle,
    this.details,
  });
}

/// One throw as resolved by the AI (or manually edited by the user).
class TrainingDart {
  final int baseScore;
  final ScoreMultiplier multiplier;

  const TrainingDart(this.baseScore, this.multiplier);

  int get points {
    if (baseScore == 0) return 0;
    if (baseScore == 25) {
      return multiplier == ScoreMultiplier.double ? 50 : 25;
    }
    switch (multiplier) {
      case ScoreMultiplier.single:
        return baseScore;
      case ScoreMultiplier.double:
        return baseScore * 2;
      case ScoreMultiplier.triple:
        return baseScore * 3;
    }
  }

  bool get isDouble =>
      multiplier == ScoreMultiplier.double ||
      (baseScore == 25 && multiplier == ScoreMultiplier.double);

  String get notation {
    if (baseScore == 0) return 'M';
    if (baseScore == 25) {
      return multiplier == ScoreMultiplier.double ? 'DB' : 'B';
    }
    switch (multiplier) {
      case ScoreMultiplier.single:
        return 'S$baseScore';
      case ScoreMultiplier.double:
        return 'D$baseScore';
      case ScoreMultiplier.triple:
        return 'T$baseScore';
    }
  }
}

/// Strategy interface. Each training type provides one implementation so the
/// AI game screen can stay generic.
///
/// All display getters take a `pending` list — the darts the AI has detected
/// (or the user has manually entered) this visit but which have NOT been
/// committed yet. Strategies compute the *would-be* state after processing
/// those darts on top of their committed state, without mutating. This makes
/// the UI react live: the focal value (e.g. "next target") updates the moment
/// a dart is detected, not just at the end of the visit.
abstract class TrainingStrategy {
  TrainingType get trainingType;

  /// Label shown next to the focal value (e.g. "NEXT TARGET", "REMAINING").
  String primaryLabel(AppLocalizations l10n);

  /// Primary (focal) value after processing [pending] on top of committed state.
  String primaryValue(AppLocalizations l10n, List<TrainingDart> pending);

  /// Optional secondary label (e.g. "DARTS", "CHECKOUTS").
  String? secondaryLabel(AppLocalizations l10n);

  /// Optional secondary value (e.g. "3", "2/10").
  String? secondaryValue(AppLocalizations l10n, List<TrainingDart> pending);

  /// 0-1 progress shown in the progress bar.
  double progress(List<TrainingDart> pending);

  /// Short caption below the progress bar (e.g. "Round 4 of 21").
  String? progressCaption(AppLocalizations l10n, List<TrainingDart> pending);

  /// Whether the AI input should be locked to a specific multiplier
  /// (e.g. doubles-only for Bob's 27 or Checkout 50). Null = any.
  ScoreMultiplier? get lockedMultiplier => null;

  /// Process one submitted 3-dart visit. Strategy mutates internal state and
  /// returns a [VisitOutcome] telling the screen whether to finish or continue.
  VisitOutcome submitVisit(List<TrainingDart> darts);

  /// Build the payload sent to the backend (and shown on the end screen).
  TrainingResult buildResult(AppLocalizations l10n);

  /// Reset to a fresh run for "Play again".
  void reset();
}

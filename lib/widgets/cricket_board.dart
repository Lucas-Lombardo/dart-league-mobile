import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/cricket.dart';
import '../utils/app_theme.dart';
import 'game_turn_ui.dart';

/// The cricket marks grid: 7 horizontal columns (20 → 15, Bull), the player's
/// marks on top (blue), the opponent's below (pink). A column the player has
/// closed while the opponent is open glows gold (every hit scores); a column
/// closed on both sides is dimmed and struck through (dead). Sits where the
/// X01 layout has nothing — between the visit chips and the score bar — via
/// AutoScoreGameView.scorePanel.
class CricketBoardStrip extends StatelessWidget {
  final CricketState state;
  final bool showLegend;

  const CricketBoardStrip({
    super.key,
    required this.state,
    this.showLegend = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 7),
      decoration: BoxDecoration(
        color: AppTheme.gamePanelEmpty,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              for (final target in kCricketTargets)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: target == kCricketTargets.first ? 0 : 5,
                    ),
                    child: _column(target),
                  ),
                ),
            ],
          ),
          if (showLegend) ...[
            const SizedBox(height: 7),
            Text(
              state.scoreMode == CricketScoreMode.score
                  ? l10n.cricketScoreHint
                  : l10n.cricketNoScoreHint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.75),
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _column(int target) {
    final gold = state.isScoringForMe(target);
    final dead = state.isDead(target);
    return Opacity(
      opacity: dead ? 0.38 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: gold ? AppTheme.accent.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: gold
                ? AppTheme.accent.withValues(alpha: 0.6)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            _MarkBox(marks: state.myMarks(target), mine: true),
            const SizedBox(height: 5),
            Text(
              target == 25 ? 'B' : '$target',
              style: TextStyle(
                color: gold ? AppTheme.accent : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                decoration: dead ? TextDecoration.lineThrough : null,
                decorationColor: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 5),
            _MarkBox(marks: state.oppMarks(target), mine: false),
          ],
        ),
      ),
    );
  }
}

/// One side's marks on one target: empty box → ／ → ⊘ → filled ✕.
class _MarkBox extends StatelessWidget {
  final int marks;
  final bool mine;

  const _MarkBox({required this.marks, required this.mine});

  @override
  Widget build(BuildContext context) {
    final color = mine ? AppTheme.playerBlue : AppTheme.opponentPink;
    final closed = marks >= 3;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: closed ? color : null,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: marks > 0
              ? color
              : AppTheme.surfaceLight.withValues(alpha: 0.7),
          width: 1.5,
        ),
      ),
      child: marks == 0
          ? null
          : Text(
              closed
                  ? '✕'
                  : marks == 2
                  ? '⊘'
                  : '／',
              style: TextStyle(
                color: closed ? AppTheme.gameBackground : color,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
    );
  }
}

/// Cricket replacement for the X01 UserScoreBar: same three-column layout and
/// series center, but the big numbers are points (score mode) or "closed n/7"
/// with a 7-segment gauge (no-score).
class CricketScoreBar extends StatelessWidget {
  final String myName;
  final String opponentName;
  final CricketState state;
  final String? seriesTitle;
  final int myLegs;
  final int opponentLegs;

  const CricketScoreBar({
    super.key,
    required this.myName,
    required this.opponentName,
    required this.state,
    this.seriesTitle,
    this.myLegs = 0,
    this.opponentLegs = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const scoreStyle = TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w800,
      height: 1.05,
      letterSpacing: -1,
    );
    final noScore = state.scoreMode == CricketScoreMode.noScore;
    final total = kCricketTargets.length;

    Widget segments({required int closed, required bool mine}) {
      final color = mine ? AppTheme.playerBlue : AppTheme.opponentPink;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < total; i++)
            Container(
              width: 13,
              height: 5,
              margin: EdgeInsets.only(left: i == 0 ? 0 : 3),
              decoration: BoxDecoration(
                color: i < closed
                    ? color
                    : AppTheme.surfaceLight.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      );
    }

    Widget bigNumber({required bool mine}) {
      final closed = mine ? state.myClosedCount : state.oppClosedCount;
      final points = mine ? state.myPoints : state.oppPoints;
      final color = mine
          ? AppTheme.playerBlueBright
          : AppTheme.opponentPinkBright.withValues(alpha: 0.65);
      if (noScore) {
        return Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text.rich(
                TextSpan(
                  text: '$closed',
                  style: scoreStyle.copyWith(color: color),
                  children: [
                    TextSpan(
                      text: '/$total',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            segments(closed: closed, mine: mine),
          ],
        );
      }
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text('$points', style: scoreStyle.copyWith(color: color)),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.gamePanelEmpty,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    GameChip(text: l10n.you, color: AppTheme.playerBlue),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        myName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                bigNumber(mine: true),
              ],
            ),
          ),
          seriesTitle != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      seriesTitle!.toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SeriesLegsScore(
                      myLegs: myLegs,
                      opponentLegs: opponentLegs,
                      fontSize: 24,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      l10n.legsShort.toUpperCase(),
                      style: TextStyle(
                        color: AppTheme.textSecondary.withValues(alpha: 0.7),
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                )
              : Text(
                  l10n.vsLabel,
                  style: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.6),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  opponentName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.opponentPinkBright,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                bigNumber(mine: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

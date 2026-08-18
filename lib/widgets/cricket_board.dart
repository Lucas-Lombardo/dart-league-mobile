import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/cricket.dart';
import '../utils/app_theme.dart';
import 'game_turn_ui.dart';

/// The cricket marks grid: 7 horizontal columns (20 → 15, Bull), the player's
/// marks on top (blue), the opponent's below (pink). A column the player has
/// closed while the opponent is open glows gold (every hit scores); a column
/// closed on both sides is dimmed and struck through (dead). Full-size
/// variant, shown below the camera on the opponent's turn; my own turn shows
/// the dense [CricketCameraHud] on the feed instead.
class CricketBoardStrip extends StatelessWidget {
  final CricketState state;

  const CricketBoardStrip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 7),
      decoration: BoxDecoration(
        color: AppTheme.gamePanelEmpty,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final target in kCricketTargets)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: target == kCricketTargets.first ? 0 : 5,
                ),
                child: _TargetColumn(state: state, target: target),
              ),
            ),
        ],
      ),
    );
  }
}

/// One target's column (my mark box / number / opponent mark box), shared by
/// the full-size [CricketBoardStrip] and the dense [CricketCameraHud].
class _TargetColumn extends StatelessWidget {
  final CricketState state;
  final int target;
  final bool dense;

  const _TargetColumn({
    required this.state,
    required this.target,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final gold = state.isScoringForMe(target);
    final dead = state.isDead(target);
    return Opacity(
      opacity: dead ? 0.38 : 1,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: dense ? 5 : 7),
        decoration: BoxDecoration(
          color: gold ? AppTheme.accent.withValues(alpha: 0.10) : null,
          borderRadius: BorderRadius.circular(dense ? 9 : 11),
          border: Border.all(
            color: gold
                ? AppTheme.accent.withValues(alpha: 0.6)
                : Colors.transparent,
            width: dense ? 1 : 1.5,
          ),
        ),
        child: Column(
          children: [
            _MarkBox(
              marks: state.myMarks(target),
              mine: true,
              size: dense ? 18 : 22,
            ),
            SizedBox(height: dense ? 4 : 5),
            Text(
              target == 25 ? 'B' : '$target',
              style: TextStyle(
                color: gold ? AppTheme.accent : Colors.white,
                fontSize: dense ? 12.5 : 14,
                fontWeight: FontWeight.w800,
                decoration: dead ? TextDecoration.lineThrough : null,
                decorationColor: AppTheme.textSecondary,
              ),
            ),
            SizedBox(height: dense ? 4 : 5),
            _MarkBox(
              marks: state.oppMarks(target),
              mine: false,
              size: dense ? 18 : 22,
            ),
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
  final double size;

  const _MarkBox({required this.marks, required this.mine, this.size = 22});

  @override
  Widget build(BuildContext context) {
    final color = mine ? AppTheme.playerBlue : AppTheme.opponentPink;
    final closed = marks >= 3;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: closed ? color : null,
        borderRadius: BorderRadius.circular(size < 22 ? 6 : 7),
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
                fontSize: size < 22 ? 10 : 12,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
    );
  }
}

/// Dense cricket HUD overlaid on the bottom of MY camera panel: the 7 marks
/// columns flanked by both scores (mine blue left, opponent pink right), so
/// the whole board state is readable next to the live feed without scrolling
/// (2026-08-18 no-scroll redesign). Docked via GameCameraPanel.bottomOverlay.
class CricketCameraHud extends StatelessWidget {
  final CricketState state;
  final String myName;
  final String opponentName;

  const CricketCameraHud({
    super.key,
    required this.state,
    required this.myName,
    required this.opponentName,
  });

  Widget _scoreFlank({required bool mine}) {
    final noScore = state.scoreMode == CricketScoreMode.noScore;
    final closed = mine ? state.myClosedCount : state.oppClosedCount;
    final points = mine ? state.myPoints : state.oppPoints;
    final value = noScore ? '$closed/${kCricketTargets.length}' : '$points';
    return SizedBox(
      width: 40,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: mine
                    ? AppTheme.playerBlueBright
                    : AppTheme.opponentPinkBright,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            (mine ? myName : opponentName).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mine ? AppTheme.playerBlue : AppTheme.opponentPink,
              fontSize: 7,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 6),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.surfaceLight.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          _scoreFlank(mine: true),
          for (final target in kCricketTargets)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: _TargetColumn(state: state, target: target, dense: true),
              ),
            ),
          const SizedBox(width: 4),
          _scoreFlank(mine: false),
        ],
      ),
    );
  }
}

/// Cricket score bar (opponent's turn, below the board strip): three-column
/// layout with the series center, big numbers being points (score mode) or
/// "closed n/7" with a 7-segment gauge (no-score).
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

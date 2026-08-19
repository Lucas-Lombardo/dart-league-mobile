import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/cricket.dart';
import '../utils/app_theme.dart';
import 'game_turn_ui.dart';

/// The cricket marks grid: 7 horizontal columns (20 → 15, Bull), the player's
/// marks on top (blue), the opponent's below (pink). A column the player has
/// closed while the opponent is open glows gold (every hit scores); a column
/// closed on both sides is dimmed and struck through (dead). Only the bot
/// screen's bot-turn view still uses it — the match screens moved to the
/// [CricketScoreTable] (2026-08-19 "tableau" direction).
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

/// One target's column (my mark box / number / opponent mark box) of the
/// full-size [CricketBoardStrip].
class _TargetColumn extends StatelessWidget {
  final CricketState state;
  final int target;

  const _TargetColumn({required this.state, required this.target});

  @override
  Widget build(BuildContext context) {
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

/// Full-width cricket score table (2026-08-19 "tableau" direction): score
/// header (names + big numbers + BO3 center), optional MPR bar, then one row
/// per target — my mark on the left (blue), the opponent's on the right
/// (pink). Replaces the camera HUD + board strip + score bar trio of the
/// 2026-08-18 layout on both match turns.
class CricketScoreTable extends StatelessWidget {
  final CricketState state;
  final String myName;
  final String opponentName;
  final String? seriesTitle;
  final int myLegs;
  final int opponentLegs;

  /// Which side carries the "playing" dot in the header.
  final bool myTurn;

  /// Marks-per-round averages. The bar is hidden when both are null: online
  /// matches don't ship marks totals over the wire, only the bot mode tracks
  /// them locally.
  final double? myMpr;
  final double? oppMpr;

  /// 22 fits the your-turn portrait column next to the visit chips; the
  /// roomier opponent turn uses the default.
  final double rowHeight;

  const CricketScoreTable({
    super.key,
    required this.state,
    required this.myName,
    required this.opponentName,
    this.seriesTitle,
    this.myLegs = 0,
    this.opponentLegs = 0,
    this.myTurn = false,
    this.myMpr,
    this.oppMpr,
    this.rowHeight = 27,
  });

  // Maquette-derived shades between gamePanelEmpty and gameBackground.
  static const Color _rowAlt = Color(0xFF0E1524);
  static const Color _mprBarBg = Color(0xFF0B1220);

  Widget _headerSide({required bool mine}) {
    final noScore = state.scoreMode == CricketScoreMode.noScore;
    final closed = mine ? state.myClosedCount : state.oppClosedCount;
    final points = mine ? state.myPoints : state.oppPoints;
    final value = noScore ? '$closed/${kCricketTargets.length}' : '$points';
    final nameRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (myTurn == mine) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: mine ? AppTheme.playerBlue : AppTheme.opponentPink,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            (mine ? myName : opponentName).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: mine ? AppTheme.playerBlue : AppTheme.opponentPink,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        nameRow,
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              color: mine
                  ? AppTheme.playerBlueBright
                  : AppTheme.opponentPinkBright,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _mprBar(AppLocalizations l10n) {
    Widget side(double? mpr, {required bool mine}) => Text(
          mpr == null ? '' : l10n.mprShort(mpr.toStringAsFixed(1)),
          style: TextStyle(
            color: mine ? AppTheme.playerBlue : AppTheme.opponentPink,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        );
    return Container(
      height: 16,
      color: _mprBarBg,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          side(myMpr, mine: true),
          const Spacer(),
          Text(
            l10n.cricketMprCaption,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          side(oppMpr, mine: false),
        ],
      ),
    );
  }

  Widget _targetRow(int index, int target) {
    final gold = state.isScoringForMe(target);
    final dead = state.isDead(target);
    final markSize = rowHeight < 24 ? 18.0 : 20.0;
    return Opacity(
      opacity: dead ? 0.38 : 1,
      child: Container(
        height: rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: gold
              ? AppTheme.accent.withValues(alpha: 0.08)
              : (index.isOdd ? _rowAlt : AppTheme.gamePanelEmpty),
        ),
        // Foreground so the gold inset never shifts the row's content.
        foregroundDecoration: gold
            ? BoxDecoration(
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.55),
                ),
              )
            : null,
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: Text(
                target == 25 ? 'B' : '$target',
                style: TextStyle(
                  color: gold ? AppTheme.accent : Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  decoration: dead ? TextDecoration.lineThrough : null,
                  decorationColor: AppTheme.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            _MarkBox(marks: state.myMarks(target), mine: true, size: markSize),
            const Spacer(),
            _MarkBox(
              marks: state.oppMarks(target),
              mine: false,
              size: markSize,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final header = Container(
      height: 48,
      color: AppTheme.gamePanel,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _headerSide(mine: true),
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
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SeriesLegsScore(
                      myLegs: myLegs,
                      opponentLegs: opponentLegs,
                      fontSize: 12,
                    ),
                  ],
                )
              : Text(
                  l10n.vsLabel,
                  style: TextStyle(
                    color: AppTheme.textSecondary.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: _headerSide(mine: false),
            ),
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (myMpr != null || oppMpr != null) _mprBar(l10n),
          for (var i = 0; i < kCricketTargets.length; i++)
            _targetRow(i, kCricketTargets[i]),
        ],
      ),
    );
  }
}

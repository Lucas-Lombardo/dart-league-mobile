import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/cricket.dart';
import '../utils/app_theme.dart';
import 'design_system.dart';
import 'game_turn_ui.dart';

/// Visit-chip subtitle for one dart: "+60 pts" when it scored, else its mark
/// count ("1 marque", "0 marque"). A null effect is an empty slot.
String cricketChipSubtitle(AppLocalizations l10n, CricketDartEffect? effect) {
  if (effect == null) return l10n.cricketMarks(0);
  if (effect.pointsScored > 0) return l10n.plusPts(effect.pointsScored);
  return l10n.cricketMarks(effect.marksApplied);
}

/// Visit TOTAL text: the points when any dart scored, else "+N" marks.
String cricketVisitTotalText(
  AppLocalizations l10n,
  List<CricketDartEffect> effects,
) {
  var marks = 0;
  var points = 0;
  for (final e in effects) {
    marks += e.marksApplied;
    points += e.pointsScored;
  }
  if (points > 0) return l10n.plusPts(points);
  return '+$marks';
}

/// Hairline between the rows of the marks table: surfaceLight at 35 %.
const Color _rowHairline = Color(0x59334155);

/// One side's marks on one target, drawn as strokes (system D, 2026-09):
/// an empty hairline box, one slash, a cross, and — closed — a cross in a
/// circle tinted [AppTheme.success]. The strokes are white; the column, not
/// the glyph, carries the player's colour.
class CricketMarkCell extends StatelessWidget {
  final int marks;
  final double size;

  const CricketMarkCell({super.key, required this.marks, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final closed = marks >= 3;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: closed ? AppTheme.success.withValues(alpha: 0.14) : null,
        borderRadius: BorderRadius.circular(size * 0.3),
        border: closed
            ? null
            : Border.all(
                color: AppTheme.surfaceLight.withValues(alpha: 0.6),
              ),
      ),
      child: marks == 0
          ? null
          : CustomPaint(
              painter: _MarkStrokesPainter(
                marks: marks,
                color: closed ? AppTheme.success : AppTheme.textPrimary,
              ),
            ),
    );
  }
}

class _MarkStrokesPainter extends CustomPainter {
  final int marks;
  final Color color;

  const _MarkStrokesPainter({required this.marks, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.1
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final inset = size.width * 0.26;
    final a = Offset(inset, size.height - inset);
    final b = Offset(size.width - inset, inset);
    canvas.drawLine(a, b, paint);
    if (marks >= 2) {
      canvas.drawLine(
        Offset(inset, inset),
        Offset(size.width - inset, size.height - inset),
        paint,
      );
    }
    if (marks >= 3) {
      canvas.drawCircle(
        size.center(Offset.zero),
        size.width / 2 - paint.strokeWidth / 2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkStrokesPainter oldDelegate) =>
      oldDelegate.marks != marks || oldDelegate.color != color;
}

/// Target label: "B" for the bull, the number otherwise. A target the player
/// has closed while the opponent is still open reads in primaryLight (every
/// hit scores); a dead target (closed on both sides) is struck through.
Widget _targetLabel(
  int target, {
  required bool scoring,
  required bool dead,
  double fontSize = 15,
}) {
  return Text(
    target == 25 ? 'B' : '$target',
    style: TextStyle(
      color: scoring ? AppTheme.primaryLight : AppTheme.textPrimary,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      height: 1,
      decoration: dead ? TextDecoration.lineThrough : null,
      decorationColor: AppTheme.textSecondary,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

/// The cricket marks grid: 7 horizontal columns (20 → 15, Bull), the player's
/// marks on top, the opponent's below, on a flat surface card. Only the bot
/// screen's bot-turn view still uses it — the match screens moved to the
/// [CricketScoreTable] (2026-08-19 "tableau" direction).
class CricketBoardStrip extends StatelessWidget {
  final CricketState state;

  const CricketBoardStrip({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return DsCard(
      radius: AppTheme.radiusRow,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: Row(
        children: [
          for (final target in kCricketTargets)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: target == kCricketTargets.first ? 0 : 4,
                ),
                child: _TargetColumn(state: state, target: target),
              ),
            ),
        ],
      ),
    );
  }
}

/// One target's column (my mark cell / number / opponent mark cell) of the
/// [CricketBoardStrip].
class _TargetColumn extends StatelessWidget {
  final CricketState state;
  final int target;

  const _TargetColumn({required this.state, required this.target});

  @override
  Widget build(BuildContext context) {
    final scoring = state.isScoringForMe(target);
    final dead = state.isDead(target);
    return Opacity(
      opacity: dead ? 0.38 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: scoring ? AppTheme.primaryLight.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            CricketMarkCell(marks: state.myMarks(target)),
            const SizedBox(height: 7),
            _targetLabel(target, scoring: scoring, dead: dead, fontSize: 14),
            const SizedBox(height: 7),
            CricketMarkCell(marks: state.oppMarks(target)),
          ],
        ),
      ),
    );
  }
}

/// Full-width cricket score table (2026-08-19 "tableau" direction), on the
/// system's flat card: a group-label header (my name in blue, the opponent's
/// in rose, the series context in the middle), an optional MPR caption, one
/// hairlined row per target — my mark on the left, the opponent's on the
/// right — and the points row at the bottom. Replaces the camera HUD + board
/// strip + score bar trio of the 2026-08-18 layout on both match turns.
class CricketScoreTable extends StatelessWidget {
  final CricketState state;
  final String myName;
  final String opponentName;
  final String? seriesTitle;
  final int myLegs;
  final int opponentLegs;

  /// Which side carries the "playing" dot in the header.
  final bool myTurn;

  /// Marks-per-round averages. The caption is hidden when both are null:
  /// online matches don't ship marks totals over the wire, only the bot mode
  /// tracks them locally.
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
    this.rowHeight = 26,
  });

  Widget _dot(Color color) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _headerName({required bool mine}) {
    final color = mine ? AppTheme.playerBlueBright : AppTheme.opponentPinkBright;
    final dotColor = mine ? AppTheme.playerBlue : AppTheme.opponentPink;
    final showDot = myTurn == mine;
    final name = Flexible(
      child: Text(
        (mine ? myName : opponentName).toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.labelSmall.copyWith(color: color, height: 1),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: mine ? MainAxisAlignment.start : MainAxisAlignment.end,
      children: [
        if (mine && showDot) ...[_dot(dotColor), const SizedBox(width: 6)],
        name,
        if (!mine && showDot) ...[const SizedBox(width: 6), _dot(dotColor)],
      ],
    );
  }

  Widget _header(AppLocalizations l10n) {
    return SizedBox(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _headerName(mine: true),
              ),
            ),
            if (seriesTitle != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    seriesTitle!.toUpperCase(),
                    style: AppTheme.labelSmall.copyWith(fontSize: 10, height: 1),
                  ),
                  const SizedBox(width: 8),
                  SeriesLegsScore(
                    myLegs: myLegs,
                    opponentLegs: opponentLegs,
                    fontSize: 13,
                  ),
                ],
              )
            else
              Text(
                l10n.vsLabel,
                style: AppTheme.labelSmall.copyWith(
                  color: AppTheme.textTertiary,
                  height: 1,
                ),
              ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: _headerName(mine: false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mprCaption(AppLocalizations l10n) {
    Widget side(double? mpr, {required bool mine}) => Text(
          mpr == null ? '' : l10n.mprShort(mpr.toStringAsFixed(1)),
          style: TextStyle(
            color: mine ? AppTheme.playerBlueBright : AppTheme.opponentPinkBright,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
    return SizedBox(
      height: 18,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            side(myMpr, mine: true),
            const Spacer(),
            Text(
              l10n.cricketMprCaption,
              style: AppTheme.labelSmall.copyWith(fontSize: 9, height: 1),
            ),
            const Spacer(),
            side(oppMpr, mine: false),
          ],
        ),
      ),
    );
  }

  Widget _targetRow(int target) {
    final scoring = state.isScoringForMe(target);
    final dead = state.isDead(target);
    final cellSize = rowHeight < 24 ? 17.0 : 18.0;
    return Opacity(
      opacity: dead ? 0.38 : 1,
      child: Container(
        height: rowHeight,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: scoring ? AppTheme.primaryLight.withValues(alpha: 0.08) : null,
          border: const Border(top: BorderSide(color: _rowHairline)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: _targetLabel(target, scoring: scoring, dead: dead),
            ),
            const SizedBox(width: 10),
            CricketMarkCell(marks: state.myMarks(target), size: cellSize),
            const Spacer(),
            CricketMarkCell(marks: state.oppMarks(target), size: cellSize),
          ],
        ),
      ),
    );
  }

  /// "412 · POINTS · 260" (score mode) or the closed counts (no-score).
  Widget _pointsRow(AppLocalizations l10n) {
    final noScore = state.scoreMode == CricketScoreMode.noScore;
    String value({required bool mine}) {
      if (noScore) {
        final closed = mine ? state.myClosedCount : state.oppClosedCount;
        return '$closed/${kCricketTargets.length}';
      }
      return '${mine ? state.myPoints : state.oppPoints}';
    }

    Widget side({required bool mine}) => Text(
          value(mine: mine),
          style: TextStyle(
            color: mine ? AppTheme.playerBlueBright : AppTheme.opponentPinkBright,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        );
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _rowHairline)),
      ),
      child: Row(
        children: [
          side(mine: true),
          const Spacer(),
          Text(
            noScore
                ? l10n.cricketNoScoreLabel.toUpperCase()
                : l10n.pointsShortUpper,
            style: AppTheme.labelSmall.copyWith(fontSize: 10, height: 1),
          ),
          const Spacer(),
          side(mine: false),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DsCard(
      radius: AppTheme.radiusRow,
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(l10n),
          if (myMpr != null || oppMpr != null) _mprCaption(l10n),
          for (final target in kCricketTargets) _targetRow(target),
          _pointsRow(l10n),
        ],
      ),
    );
  }
}

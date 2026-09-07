import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'design_system.dart';
import 'game_turn_ui.dart';

/// Compact score band (system D, 2026-09) for the spectator screen and the
/// landscape layouts: a translucent surface strip with a hairline, the two
/// names in their identity colours over big white tabular scores, the series
/// context in the middle (group label, two-coloured legs, optional caption)
/// and an average caption under each score. The 6 px dot next to a name says
/// whose turn it is.
class TvScoreboard extends StatelessWidget {
  final int myScore;
  final int opponentScore;
  final String myName;
  final String opponentName;
  final bool isMyTurn;

  /// Kept for callers that size the old circular gauge; the band ignores it.
  final int startingScore;
  final double? myAverage;
  final double? opponentAverage;
  // When true, the current user is player 2 (second to throw) and should
  // render on the right side. The opponent moves to the left.
  final bool iAmPlayer2;

  /// "CLASSÉ · BO3" group label in the centre; null shows "vs".
  final String? seriesTitle;
  final int myLegs;
  final int opponentLegs;

  /// Small line under the legs ("Manche 1"); null hides it.
  final String? caption;

  const TvScoreboard({
    super.key,
    required this.myScore,
    required this.opponentScore,
    required this.myName,
    required this.opponentName,
    required this.isMyTurn,
    this.startingScore = 501,
    this.myAverage,
    this.opponentAverage,
    this.iAmPlayer2 = false,
    this.seriesTitle,
    this.myLegs = 0,
    this.opponentLegs = 0,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // me renders on the left unless the current user is player 2.
    final mePanel = _PlayerScore(
      name: myName,
      score: myScore,
      isActive: isMyTurn,
      color: AppTheme.playerBlueBright,
      dotColor: AppTheme.playerBlue,
      average: myAverage,
      isLeft: !iAmPlayer2,
    );
    final opponentPanel = _PlayerScore(
      name: opponentName,
      score: opponentScore,
      isActive: !isMyTurn,
      color: AppTheme.opponentPinkBright,
      dotColor: AppTheme.opponentPink,
      average: opponentAverage,
      isLeft: iAmPlayer2,
    );
    final legs = SeriesLegsScore(
      myLegs: iAmPlayer2 ? opponentLegs : myLegs,
      opponentLegs: iAmPlayer2 ? myLegs : opponentLegs,
      fontSize: 15,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(child: iAmPlayer2 ? opponentPanel : mePanel),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  (seriesTitle ?? l10n.vsLabel).toUpperCase(),
                  maxLines: 1,
                  style: AppTheme.labelSmall.copyWith(
                    fontSize: 10,
                    height: 1,
                    color: seriesTitle == null
                        ? AppTheme.textTertiary
                        : AppTheme.textSecondary,
                  ),
                ),
                if (seriesTitle != null) ...[
                  const SizedBox(height: 6),
                  legs,
                ],
                if (caption != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    caption!,
                    maxLines: 1,
                    style: AppTheme.caption.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: iAmPlayer2 ? mePanel : opponentPanel),
        ],
      ),
    );
  }
}

class _PlayerScore extends StatelessWidget {
  final String name;
  final int score;
  final bool isActive;
  final Color color;
  final Color dotColor;
  final double? average;
  // Which half of the band this panel occupies: text aligns to the outer edge.
  final bool isLeft;

  const _PlayerScore({
    required this.name,
    required this.score,
    required this.isActive,
    required this.color,
    required this.dotColor,
    this.average,
    this.isLeft = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
    );
    final nameText = Flexible(
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
    return Column(
      crossAxisAlignment:
          isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 13,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLeft && isActive) ...[dot, const SizedBox(width: 6)],
              nameText,
              if (!isLeft && isActive) ...[const SizedBox(width: 6), dot],
            ],
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$score',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        // Always reserve the caption line so the two columns stay symmetric
        // while one side has no rounds played yet.
        const SizedBox(height: 6),
        Opacity(
          opacity: (average != null && average! > 0) ? 1 : 0,
          child: Text(
            '${dsSentence(l10n.avgLabel)} ${(average ?? 0).toStringAsFixed(1)}',
            maxLines: 1,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

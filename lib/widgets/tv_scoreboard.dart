import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/score_converter.dart';
import '../l10n/app_localizations.dart';

/// PDC TV-style scoreboard with circular score displays.
class TvScoreboard extends StatelessWidget {
  final int myScore;
  final int opponentScore;
  final String myName;
  final String opponentName;
  final bool isMyTurn;
  final int startingScore;
  final double? myAverage;
  final double? opponentAverage;
  // When true, the current user is player 2 (second to throw) and should
  // render on the right side. The opponent moves to the left.
  final bool iAmPlayer2;

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
  });

  @override
  Widget build(BuildContext context) {
    final hint = (myScore >= 2 && myScore <= 170) ? checkoutHint(myScore) : null;
    final opponentHint = (opponentScore >= 2 && opponentScore <= 170) ? checkoutHint(opponentScore) : null;

    // me renders on the left unless the current user is player 2.
    final mePanel = _PlayerScore(
      name: myName,
      score: myScore,
      startingScore: startingScore,
      isActive: isMyTurn,
      color: AppTheme.primary,
      hint: hint,
      average: myAverage,
      isMe: true,
      isLeft: !iAmPlayer2,
    );
    final opponentPanel = _PlayerScore(
      name: opponentName,
      score: opponentScore,
      startingScore: startingScore,
      isActive: !isMyTurn,
      color: AppTheme.error,
      hint: opponentHint,
      average: opponentAverage,
      isMe: false,
      isLeft: iAmPlayer2,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.surface,
            AppTheme.surfaceLight.withValues(alpha: 0.6),
            AppTheme.surface,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(child: iAmPlayer2 ? opponentPanel : mePanel),
          // Center info
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(context).vsUppercase,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isMyTurn ? AppTheme.primary : AppTheme.error,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (isMyTurn ? AppTheme.primary : AppTheme.error).withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
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
  final int startingScore;
  final bool isActive;
  final Color color;
  final String? hint;
  final double? average;
  final bool isMe;
  // Which half of the scoreboard this panel occupies. Drives the direction of
  // the identity-color wash so it always fades from the outer edge to center.
  final bool isLeft;

  const _PlayerScore({
    required this.name,
    required this.score,
    required this.startingScore,
    required this.isActive,
    required this.color,
    this.hint,
    this.average,
    this.isMe = false,
    this.isLeft = true,
  });

  @override
  Widget build(BuildContext context) {
    final progress = 1.0 - (score / startingScore).clamp(0.0, 1.0);
    // Ownership is carried by the identity color (blue = you, red = opponent)
    // on the name, ring and background wash — always on, regardless of turn.
    // Turn is carried separately by the pure-white active number + ring glow.
    final identityColor = Color.lerp(color, Colors.white, 0.45)!;
    final numberColor = isActive ? Colors.white : Color.lerp(color, Colors.white, 0.70)!;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Size to the actual slot the scoreboard lives in, not the screen
        // width — otherwise in landscape (where the scoreboard lives in a
        // narrow right column) the circle is computed against the full
        // landscape width and either overflows or gets aggressively scaled
        // down by an enclosing FittedBox. constraints.maxWidth here is the
        // single-player slot width; the circle takes the bulk of it.
        final slotWidth = constraints.maxWidth;
        final nameFontSize = (slotWidth * 0.10).clamp(15.0, 30.0);
        // When the scoreboard is handed a bounded height (it fills its panel)
        // the circle expands to use the leftover vertical space, capped to the
        // slot width. While being measured inside a FittedBox (unbounded
        // height) it falls back to a width-derived diameter.
        final boundedHeight = constraints.maxHeight.isFinite;

        // Ring + score number at a given diameter. A FittedBox sizes the number
        // with a generous inset so it never collides with the ring, whatever
        // the digit count.
        Widget buildCircle(double size) {
          return SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _ScoreArcPainter(
                progress: progress,
                color: color,
                isActive: isActive,
              ),
              child: Center(
                child: Padding(
                  // Small inset so the digits nearly fill the ring (readable
                  // from a few metres away) without touching the stroke.
                  padding: EdgeInsets.all(size * 0.07),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: Text(
                      '$score',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        color: numberColor,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        fontSize: 50
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        final Widget circle = boundedHeight
            ? Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => Center(
                    child: buildCircle(math.min(c.maxWidth, c.maxHeight)),
                  ),
                ),
              )
            : buildCircle((slotWidth * 0.92).clamp(110.0, 240.0));

        return Container(
          width: slotWidth,
          padding: const EdgeInsets.symmetric(vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            // Identity wash: fades from the panel's outer edge toward center so
            // each half of the scoreboard reads as "blue side / red side".
            gradient: LinearGradient(
              begin: isLeft ? Alignment.centerLeft : Alignment.centerRight,
              end: isLeft ? Alignment.centerRight : Alignment.centerLeft,
              colors: [
                color.withValues(alpha: isActive ? 0.20 : 0.12),
                Colors.transparent,
              ],
              stops: const [0.0, 0.88],
            ),
          ),
          child: Column(
          mainAxisSize: boundedHeight ? MainAxisSize.max : MainAxisSize.min,
          children: [
            // "YOU" pill above the current user's name for quick identification.
            // Opacity reserves the same vertical space for the opponent panel
            // so the two name rows stay vertically aligned.
            Opacity(
              opacity: isMe ? 1 : 0,
              child: _YouBadge(fontSize: nameFontSize * 0.72, color: color),
            ),
            const SizedBox(height: 3),
            // Player name
            Text(
              name.toUpperCase(),
              style: TextStyle(
                color: identityColor,
                fontSize: nameFontSize,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 2),
            // Circular score — grows to fill the panel when height is bounded.
            circle,
            const SizedBox(height: 2),
            // Checkout hint
            SizedBox(
              height: 18,
              child: hint != null
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        hint!,
                        style: TextStyle(
                          color: AppTheme.success,
                          fontSize: (slotWidth * 0.07).clamp(11.0, 18.0),
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  : null,
            ),
            // Average score per round.
            // Always reserve the same vertical space so the two player
            // columns stay symmetric — otherwise an opponent with no rounds
            // played yet would render shorter, and Row's center alignment
            // would nudge the score circles out of horizontal alignment.
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Opacity(
                opacity: (average != null && average! > 0) ? 1 : 0,
                child: Text(
                  '${AppLocalizations.of(context).avgLabel} ${(average ?? 0).toStringAsFixed(1)}',
                  style: TextStyle(
                    color: identityColor.withValues(alpha: 0.9),
                    fontSize: (slotWidth * 0.09).clamp(14.0, 24.0),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
          ),
        );
      },
    );
  }
}

class _YouBadge extends StatelessWidget {
  final double fontSize;
  final Color color;

  const _YouBadge({required this.fontSize, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
      ),
      child: Text(
        AppLocalizations.of(context).youUpper,
        style: TextStyle(
          // Lightened identity tint so the label clears the 4.5:1 contrast bar
          // on the dark surface (raw sky-500 sits at ~3.6:1).
          color: Color.lerp(color, Colors.white, 0.55)!,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          height: 1,
        ),
      ),
    );
  }
}

class _ScoreArcPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool isActive;

  _ScoreArcPainter({
    required this.progress,
    required this.color,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strokeWidth = size.width * 0.06;
    final radius = size.width / 2 - strokeWidth;

    // Background circle — tinted with the identity color (not grey) so each
    // player's ring reads as blue/red from the very first turn, even when the
    // progress arc is still near-empty.
    final bgPaint = Paint()
      ..color = color.withValues(alpha: isActive ? 0.32 : 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    if (progress > 0) {
      final arcPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        arcPaint,
      );
    }

    // Glow for active player
    if (isActive) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, radius - 2, glowPaint);
    }
  }

  @override
  bool shouldRepaint(_ScoreArcPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      isActive != oldDelegate.isActive ||
      color != oldDelegate.color;
}

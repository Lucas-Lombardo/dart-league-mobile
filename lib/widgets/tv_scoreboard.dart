import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/score_converter.dart';

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

    final mePanel = _PlayerScore(
      name: myName,
      score: myScore,
      startingScore: startingScore,
      isActive: isMyTurn,
      color: AppTheme.primary,
      hint: hint,
      average: myAverage,
      isMe: true,
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
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'VS',
                  style: TextStyle(
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

  const _PlayerScore({
    required this.name,
    required this.score,
    required this.startingScore,
    required this.isActive,
    required this.color,
    this.hint,
    this.average,
    this.isMe = false,
  });

  @override
  Widget build(BuildContext context) {
    final progress = 1.0 - (score / startingScore).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.of(context).size.width;
        // Adaptive circle size: scale with screen width for visibility
        final circleSize = (screenWidth * 0.22).clamp(70.0, 110.0);
        final fontSize = circleSize * (score >= 100 ? 0.34 : 0.40);
        final nameFontSize = (screenWidth * 0.032).clamp(11.0, 15.0);

        return Column(
          mainAxisSize: MainAxisSize.min,
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
                color: isActive ? Colors.white : AppTheme.textSecondary,
                fontSize: nameFontSize,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 4),
            // Circular score
            SizedBox(
              width: circleSize,
              height: circleSize,
              child: CustomPaint(
                painter: _ScoreArcPainter(
                  progress: progress,
                  color: color,
                  isActive: isActive,
                ),
                child: Center(
                  child: Text(
                    '$score',
                    style: TextStyle(
                      color: isActive ? Colors.white : AppTheme.textSecondary,
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // Checkout hint
            SizedBox(
              height: 16,
              child: hint != null
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        hint!,
                        style: TextStyle(
                          color: AppTheme.success,
                          fontSize: (screenWidth * 0.028).clamp(10.0, 13.0),
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  : null,
            ),
            // Average score per round
            if (average != null && average! > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'AVG ${average!.toStringAsFixed(1)}',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: (screenWidth * 0.024).clamp(9.0, 11.0),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
          ],
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
        'YOU',
        style: TextStyle(
          color: color,
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

    // Background circle
    final bgPaint = Paint()
      ..color = isActive
          ? AppTheme.surfaceLight.withValues(alpha: 0.6)
          : AppTheme.surface
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

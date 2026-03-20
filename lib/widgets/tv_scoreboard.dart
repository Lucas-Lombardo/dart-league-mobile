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

  const TvScoreboard({
    super.key,
    required this.myScore,
    required this.opponentScore,
    required this.myName,
    required this.opponentName,
    required this.isMyTurn,
    this.startingScore = 501,
  });

  @override
  Widget build(BuildContext context) {
    final hint = (myScore >= 2 && myScore <= 170) ? checkoutHint(myScore) : null;
    final opponentHint = (opponentScore >= 2 && opponentScore <= 170) ? checkoutHint(opponentScore) : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          // Left player (me)
          Expanded(
            child: _PlayerScore(
              name: myName,
              score: myScore,
              startingScore: startingScore,
              isActive: isMyTurn,
              color: AppTheme.primary,
              hint: hint,
            ),
          ),
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
          // Right player (opponent)
          Expanded(
            child: _PlayerScore(
              name: opponentName,
              score: opponentScore,
              startingScore: startingScore,
              isActive: !isMyTurn,
              color: AppTheme.error,
              hint: opponentHint,
            ),
          ),
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

  const _PlayerScore({
    required this.name,
    required this.score,
    required this.startingScore,
    required this.isActive,
    required this.color,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final progress = 1.0 - (score / startingScore).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Adaptive circle size: use available width but cap it
        final circleSize = (constraints.maxWidth * 0.50).clamp(42.0, 64.0);
        final fontSize = circleSize * (score >= 100 ? 0.30 : 0.35);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Player name
            Text(
              name.toUpperCase(),
              style: TextStyle(
                color: isActive ? Colors.white : AppTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const SizedBox(height: 2),
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
            const SizedBox(height: 2),
            // Checkout hint
            SizedBox(
              height: 14,
              child: hint != null
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        hint!,
                        style: const TextStyle(
                          color: AppTheme.success,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  : null,
            ),
          ],
        );
      },
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
    final radius = size.width / 2 - 4;

    // Background circle
    final bgPaint = Paint()
      ..color = isActive
          ? AppTheme.surfaceLight.withValues(alpha: 0.6)
          : AppTheme.surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    if (progress > 0) {
      final arcPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
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

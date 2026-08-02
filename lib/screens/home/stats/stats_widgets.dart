import 'package:flutter/material.dart';
import '../../../utils/app_theme.dart';

/// Shared building blocks for the four Stats sub-tabs. Each sub-tab is a page
/// about one subject, so the pieces here exist to enforce one rule: exactly one
/// number dominates a page, everything else explains it.

class StatsCard extends StatelessWidget {
  final String? label;
  final List<Widget> children;
  final EdgeInsets padding;

  const StatsCard({
    super.key,
    this.label,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null) ...[
            StatsLabel(label!),
            const SizedBox(height: 10),
          ],
          ...children,
        ],
      ),
    );
  }
}

class StatsLabel extends StatelessWidget {
  final String text;

  const StatsLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// The one number a page is about. Nothing else on the page comes close in size.
class StatsHero extends StatelessWidget {
  final String value;
  final String? unit;
  final String? caption;
  final Widget? trailing;

  const StatsHero({
    super.key,
    required this.value,
    this.unit,
    this.caption,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1,
                    letterSpacing: -1.5,
                  ),
                ),
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 6),
              Text(
                unit!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ],
          ],
        ),
        if (caption != null) ...[
          const SizedBox(height: 6),
          Text(
            caption!,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.35),
          ),
        ],
      ],
    );
  }
}

class StatsDelta extends StatelessWidget {
  final double value;

  const StatsDelta(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final positive = value >= 0;
    return Text(
      '${positive ? '▲' : '▼'} ${value.abs().toStringAsFixed(1)}',
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: positive ? AppTheme.success : AppTheme.error,
      ),
    );
  }
}

class StatsRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const StatsRow({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled bar. [fraction] is the drawn width, kept separate from [value]
/// because the two breakdowns scale differently: the visit distribution is
/// relative to its own largest bucket, the double ladder to a fixed ceiling.
class StatsBar extends StatelessWidget {
  final String label;
  final double fraction;
  final String value;
  final Color color;

  const StatsBar({
    super.key,
    required this.label,
    required this.fraction,
    required this.value,
    this.color = AppTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Stack(
                children: [
                  Container(height: 10, color: AppTheme.surfaceLight.withValues(alpha: 0.45)),
                  FractionallySizedBox(
                    // A non-zero count must still be visible, otherwise "3 × 180"
                    // renders as an empty row and reads as zero.
                    widthFactor: fraction <= 0 ? 0 : fraction.clamp(0.02, 1.0),
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 58,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rolling-average curve for the Form page, with the previous block drawn as a
/// dashed baseline so the delta above it is legible without a legend.
class StatsCurve extends StatelessWidget {
  final List<double> points;
  final double? baseline;

  const StatsCurve({super.key, required this.points, this.baseline});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: CustomPaint(
        painter: _CurvePainter(points: points, baseline: baseline),
        size: Size.infinite,
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  final List<double> points;
  final double? baseline;

  _CurvePainter({required this.points, this.baseline});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final values = [...points, ?baseline];
    var min = values.reduce((a, b) => a < b ? a : b);
    var max = values.reduce((a, b) => a > b ? a : b);
    // A flat series would divide by zero; pad it so the line sits mid-height.
    if (max - min < 1) {
      min -= 1;
      max += 1;
    }
    final pad = (max - min) * 0.12;
    min -= pad;
    max += pad;

    double yOf(double v) => size.height - ((v - min) / (max - min)) * size.height;
    double xOf(int i) => (i / (points.length - 1)) * size.width;

    if (baseline != null) {
      final y = yOf(baseline!);
      final dash = Paint()
        ..color = AppTheme.surfaceLight
        ..strokeWidth = 1;
      for (double x = 0; x < size.width; x += 7) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), dash);
      }
    }

    final path = Path()..moveTo(xOf(0), yOf(points.first));
    for (var i = 1; i < points.length; i++) {
      path.lineTo(xOf(i), yOf(points[i]));
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.primary.withValues(alpha: 0.32),
            AppTheme.primary.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = AppTheme.primary
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(
      Offset(xOf(points.length - 1), yOf(points.last)),
      4,
      Paint()..color = AppTheme.primary,
    );
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.points != points || old.baseline != baseline;
}

/// Closing note on a page, explaining what the headline number actually means.
/// Cheap to render, and it stops the same question reaching support.
class StatsExplainer extends StatelessWidget {
  final String title;
  final String body;

  const StatsExplainer({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return StatsCard(
      label: title,
      children: [
        Text(
          body,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

/// Shown when a filter matches legs but this particular block has nothing to
/// say — never a row of dashes, which reads as a broken screen.
class StatsBlockEmpty extends StatelessWidget {
  final String message;

  const StatsBlockEmpty(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return StatsCard(
      children: [
        Text(
          message,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

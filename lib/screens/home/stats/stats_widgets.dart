import 'package:flutter/material.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/haptic_service.dart';
import '../../../widgets/design_system.dart';

/// Shared building blocks of the Stats tab (the head-to-head screen reuses
/// the card and the empty block). They enforce one rule per card: exactly one
/// number dominates, everything else explains it — on flat surface cards with
/// a hairline, in the app's visual system.

class StatsCard extends StatelessWidget {
  final String? label;
  final List<Widget> children;
  final EdgeInsets padding;

  const StatsCard({
    super.key,
    this.label,
    required this.children,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (label != null) ...[
            StatsLabel(label!),
            const SizedBox(height: 12),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// 11 / 700 spaced group label — the one place uppercase is allowed.
class StatsLabel extends StatelessWidget {
  final String text;

  const StatsLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: AppTheme.labelSmall);
  }
}

/// The one number a card is about. Nothing else on the card comes close in size.
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
                  style: AppTheme.displayLarge.copyWith(fontSize: 44, letterSpacing: -1),
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
          Text(caption!, style: AppTheme.caption.copyWith(height: 1.35)),
        ],
      ],
    );
  }
}

/// Signed change next to a hero number: green up, red down.
class StatsDelta extends StatelessWidget {
  final double value;

  const StatsDelta(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final positive = value >= 0;
    final color = positive ? AppTheme.success : AppTheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          positive ? Icons.north_rounded : Icons.south_rounded,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 2),
        Text(
          value.abs().toStringAsFixed(1),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// "Label ............ value" line of a card.
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// A labelled 8 px bar. [fraction] is the drawn width, kept separate from
/// [value] because the two breakdowns scale differently: the visit
/// distribution is relative to its own largest bucket, the double ladder to a
/// fixed ceiling.
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
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 8,
                child: Stack(
                  children: [
                    Container(color: Colors.white.withValues(alpha: 0.08)),
                    FractionallySizedBox(
                      // A non-zero count must still be visible, otherwise
                      // "3 × 180" renders as an empty row and reads as zero.
                      widthFactor: fraction <= 0 ? 0 : fraction.clamp(0.02, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 58,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rolling-average curve of the form card, with the previous block drawn as a
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
        ..color = AppTheme.textTertiary
        ..strokeWidth = 1;
      for (double x = 0; x < size.width; x += 8) {
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
            AppTheme.primary.withValues(alpha: 0.30),
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

/// Closing note of the page, explaining what the headline number actually
/// means. Cheap to render, and it stops the same question reaching support.
class StatsExplainer extends StatelessWidget {
  final String title;
  final String body;

  const StatsExplainer({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return StatsCard(
      label: title,
      children: [
        Text(body, style: AppTheme.caption.copyWith(height: 1.5)),
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
        Text(message, style: AppTheme.caption.copyWith(height: 1.5)),
      ],
    );
  }
}

/// Two-or-more-way segmented control, 40 px: a surface track with the active
/// segment lifted on surfaceLight. Haptics belong to the caller.
class StatsSegmentedControl extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  const StatsSegmentedControl({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(child: _segment(i)),
          ],
        ],
      ),
    );
  }

  Widget _segment(int i) {
    final selected = i == index;
    return Material(
      color: selected ? AppTheme.surfaceLight : Colors.transparent,
      borderRadius: BorderRadius.circular(9),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: selected ? null : () => onChanged(i),
        child: Center(
          child: Text(
            labels[i],
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Filter chip: quiet surface pill, tinted primary when selected.
class StatsChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const StatsChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final shape = StadiumBorder(
      side: BorderSide(
        color: selected
            ? AppTheme.primaryLight.withValues(alpha: 0.4)
            : AppTheme.border,
      ),
    );
    return Material(
      color: selected ? AppTheme.primary.withValues(alpha: 0.14) : AppTheme.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: shape,
        onTap: () {
          HapticService.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: selected ? AppTheme.primaryLight : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

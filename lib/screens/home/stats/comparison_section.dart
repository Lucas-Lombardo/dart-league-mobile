import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/player_percentiles.dart';
import '../../../services/stats_service.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/rank_translation.dart';
import '../../../widgets/design_system.dart';
import 'stats_widgets.dart';

/// Where the player stands among comparable players — the top of the Stats
/// screen.
///
/// Every other block on that screen answers "what are my numbers"; this one
/// answers "is that good", which a number on its own never settles. So nothing
/// here is shown without the cohort it was measured against: the headline and
/// the footnote both name it, and the backend widens the cohort from the
/// player's rank to everyone whenever that rank holds too few players to draw
/// a percentile from.
///
/// Loads on its own rather than through the Matches tab's single request: the
/// standing comes from nightly snapshots, on a different cadence and a
/// different window than the filter bar above it, and folding it into that
/// request would tie a 90-day figure to a filter that reads "30 days ranked".
class ComparisonSection extends StatefulWidget {
  const ComparisonSection({super.key});

  @override
  State<ComparisonSection> createState() => _ComparisonSectionState();
}

class _ComparisonSectionState extends State<ComparisonSection> {
  PlayerPercentiles? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await StatsService.getPercentiles();
      if (!mounted) return;
      setState(() => _data = data);
    } catch (_) {
      // A standing is the best thing on this page, never the reason it exists:
      // if the request fails the rest of the stats still render.
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (_failed || data == null) return const SizedBox.shrink();
    return ComparisonCards(data: data);
  }
}

/// The comparison's cards, laid out from an already-loaded standing. Split
/// from the loader so the cards can be rendered without the network.
class ComparisonCards extends StatelessWidget {
  final PlayerPercentiles data;

  const ComparisonCards({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    // No trailing spacer: the page this sits in already separates its children,
    // and one on the last block would double the gap under the section.
    final blocks = _blocks();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          blocks[i],
        ],
      ],
    );
  }

  /// The cards, in order. Built as a list so a card with nothing to say leaves
  /// no gap where it would have been.
  List<Widget> _blocks() {
    if (!data.eligible) return [_NotEnoughLegsCard(data: data)];
    return [
      _HeadlineCard(data: data),
      // A shape needs three corners.
      if (data.metrics.length >= 3) _ProfileCard(data: data),
      if (data.metrics.isNotEmpty) _StandingCard(data: data),
      if (data.strongest != null) _VerdictCard(data: data),
      _Footnote(cohort: data.cohort),
    ];
  }
}

/// Label for one axis, and the unit its value carries.
String metricLabel(AppLocalizations l10n, PercentileMetric metric) => switch (metric) {
  PercentileMetric.average => l10n.comparisonMetricScoring,
  PercentileMetric.checkoutPct => l10n.comparisonMetricFinishing,
  PercentileMetric.dartsToWinLeg => l10n.comparisonMetricConsistency,
  PercentileMetric.tonRate => l10n.comparisonMetricPower,
  PercentileMetric.bustRate => l10n.comparisonMetricComposure,
};

String _axisLabel(AppLocalizations l10n, PercentileMetric metric) => switch (metric) {
  PercentileMetric.average => l10n.comparisonAxisScoring,
  PercentileMetric.checkoutPct => l10n.comparisonAxisFinishing,
  PercentileMetric.dartsToWinLeg => l10n.comparisonAxisConsistency,
  PercentileMetric.tonRate => l10n.comparisonAxisPower,
  PercentileMetric.bustRate => l10n.comparisonAxisComposure,
};

String _num(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

/// Value with its unit. Percentages carry one, the others don't.
String formatMetric(PercentileMetric metric, double value) => switch (metric) {
  PercentileMetric.checkoutPct ||
  PercentileMetric.tonRate ||
  PercentileMetric.bustRate => '${_num(value)} %',
  _ => _num(value),
};

/// Cohort line, shown under the headline and again in the footnote.
String cohortLine(AppLocalizations l10n, PercentileCohort cohort) {
  final rank = cohort.rank;
  if (cohort.byRank && rank != null) {
    return l10n.comparisonCohortRank(RankTranslation.translate(l10n, rank), cohort.size);
  }
  return l10n.comparisonCohortAll(cohort.size);
}

/// "Top 12 %" · the cohort · the window it was measured over.
class _HeadlineCard extends StatelessWidget {
  final PlayerPercentiles data;

  const _HeadlineCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final top = data.topPercent;

    return DsCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    top != null ? l10n.comparisonTopPercent(top) : '—',
                    style: AppTheme.displayLarge,
                  ),
                ),
                const SizedBox(height: 4),
                Text(cohortLine(l10n, data.cohort), style: AppTheme.caption),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // The window is fixed server-side; this only names it.
          Text(
            l10n.statsWindowDays(data.cohort.windowDays),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final PlayerPercentiles data;

  const _ProfileCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DsCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.comparisonProfile, style: AppTheme.sectionTitle)),
              _LegendItem(label: l10n.statsLegendYou),
              const SizedBox(width: 14),
              _LegendItem(label: l10n.statsLegendMedian, dashed: true),
            ],
          ),
          const SizedBox(height: 6),
          // Full card width: the side labels need the room the padding would
          // otherwise take.
          SizedBox(
            height: 230,
            width: double.infinity,
            child: CustomPaint(
              painter: _RadarPainter(
                metrics: data.metrics,
                labels: {
                  for (final metric in data.metrics)
                    metric.key: _axisLabel(l10n, metric.key),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 14 × 2 line swatch + 11 / 600 label.
class _LegendItem extends StatelessWidget {
  final String label;
  final bool dashed;

  const _LegendItem({required this.label, this.dashed = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 2,
          child: dashed
              ? const CustomPaint(painter: _DashLinePainter())
              : const ColoredBox(color: AppTheme.primary),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _DashLinePainter extends CustomPainter {
  const _DashLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.textTertiary
      ..strokeWidth = size.height;
    final y = size.height / 2;
    for (double x = 0; x < size.width; x += 5) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 3, size.width), y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashLinePainter old) => false;
}

/// The five axes as one shape.
///
/// Each axis is drawn on the PERCENTILE, never on the raw value: an average of
/// 48 and a bust rate of 4 % share no scale, and plotting them together would
/// draw a shape that means nothing. The dashed pentagon is therefore always the
/// 50th percentile — the middle of the cohort — which is what makes "outside
/// the dashes is better than average" true on every axis at once, including the
/// two where a lower number is the better one.
class _RadarPainter extends CustomPainter {
  final List<PercentileEntry> metrics;
  final Map<PercentileMetric, String> labels;

  _RadarPainter({required this.metrics, required this.labels});

  static const _minRadiusFactor = 0.12;

  /// Horizontal room kept on each side for the side labels, and the vertical
  /// room above/below the shape for the top and bottom ones.
  static const _sideReserve = 72.0;
  static const _topReserve = 26.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (metrics.length < 3) return;

    final radius = math.min(size.width / 2 - _sideReserve, (size.height - 2 * _topReserve) / 2);
    if (radius <= 0) return;
    final center = Offset(size.width / 2, _topReserve + radius);
    final count = metrics.length;

    double angleOf(int index) => -math.pi / 2 + (2 * math.pi * index) / count;

    Offset pointAt(int index, double fraction) {
      final angle = angleOf(index);
      final r = radius * (_minRadiusFactor + (1 - _minRadiusFactor) * fraction);
      return center + Offset(math.cos(angle) * r, math.sin(angle) * r);
    }

    Path ringAt(double fraction) {
      final path = Path();
      for (var i = 0; i < count; i++) {
        final point = pointAt(i, fraction);
        i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
      }
      return path..close();
    }

    // Three rings at 33/66/100 % of the cohort.
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final fraction in [1.0, 0.66, 0.33]) {
      canvas.drawPath(ringAt(fraction), ring);
    }

    // Spokes.
    final spoke = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var i = 0; i < count; i++) {
      canvas.drawLine(center, pointAt(i, 1), spoke);
    }

    // The median ring: the cohort's middle, by definition the 50th percentile.
    canvas.drawPath(
      _dashed(ringAt(0.5)),
      Paint()
        ..color = AppTheme.textTertiary
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    // The player.
    final minePath = Path();
    for (var i = 0; i < count; i++) {
      final point = pointAt(i, (metrics[i].percentile / 100).clamp(0.0, 1.0));
      i == 0 ? minePath.moveTo(point.dx, point.dy) : minePath.lineTo(point.dx, point.dy);
    }
    minePath.close();
    canvas.drawPath(minePath, Paint()..color = AppTheme.primary.withValues(alpha: 0.22));
    canvas.drawPath(
      minePath,
      Paint()
        ..color = AppTheme.primary
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    final dot = Paint()..color = AppTheme.primary;
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(pointAt(i, (metrics[i].percentile / 100).clamp(0.0, 1.0)), 3.5, dot);
    }

    _paintLabels(canvas, size, center, radius, angleOf);
  }

  /// Labels sit just outside the outer ring, anchored away from the shape:
  /// right-hand labels start at their point, left-hand ones end at it, the
  /// top one is centred. Then clamped so nothing leaves the canvas.
  void _paintLabels(
    Canvas canvas,
    Size size,
    Offset center,
    double radius,
    double Function(int) angleOf,
  ) {
    for (var i = 0; i < metrics.length; i++) {
      final text = labels[metrics[i].key];
      if (text == null) continue;

      // A TextPainter sits outside the widget tree, so it inherits nothing
      // from the theme: the AppTheme style carries the app font.
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: AppTheme.labelSmall.copyWith(fontSize: 10, letterSpacing: 0.3),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final angle = angleOf(i);
      final cos = math.cos(angle);
      final sin = math.sin(angle);
      final anchor = center + Offset(cos, sin) * (radius + 12);

      double dx;
      if (cos > 0.15) {
        dx = anchor.dx;
      } else if (cos < -0.15) {
        dx = anchor.dx - painter.width;
      } else {
        dx = anchor.dx - painter.width / 2;
      }
      double dy;
      if (sin < -0.5) {
        dy = anchor.dy - painter.height;
      } else if (sin > 0.5) {
        dy = anchor.dy;
      } else {
        dy = anchor.dy - painter.height / 2;
      }

      painter.paint(
        canvas,
        Offset(
          dx.clamp(0.0, math.max(0.0, size.width - painter.width)),
          dy.clamp(0.0, math.max(0.0, size.height - painter.height)),
        ),
      );
    }
  }

  /// Dashes a closed path by walking its metrics — Flutter has no dash effect.
  Path _dashed(Path source, {double on = 3, double off = 3}) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + on, metric.length);
        result.addPath(metric.extractPath(distance, next), Offset.zero);
        distance = next + off;
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.metrics != metrics || old.labels != labels;
}

class _StandingCard extends StatelessWidget {
  final PlayerPercentiles data;

  const _StandingCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DsCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.comparisonWhereYouStand, style: AppTheme.sectionTitle),
          const SizedBox(height: 14),
          for (var i = 0; i < data.metrics.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _PercentileRow(
              entry: data.metrics[i],
              label: metricLabel(l10n, data.metrics[i].key),
            ),
          ],
        ],
      ),
    );
  }
}

/// One metric: the value, how much of the cohort it beats, and a bar whose fill
/// IS that share — so the median always sits at the halfway mark.
class _PercentileRow extends StatelessWidget {
  final PercentileEntry entry;
  final String label;

  const _PercentileRow({required this.entry, required this.label});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fraction = (entry.percentile / 100).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatMetric(entry.key, entry.value),
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.comparisonBeatsPercent(entry.percentile.round()),
              style: AppTheme.caption.copyWith(fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: 12,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 3,
                  left: 0,
                  right: 0,
                  child: DsProgressBar(value: fraction, height: 6),
                ),
                // The median marker, always at the middle of the bar.
                Positioned(
                  left: constraints.maxWidth / 2 - 1,
                  top: 0,
                  child: Container(
                    width: 2,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppTheme.textTertiary,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VerdictCard extends StatelessWidget {
  final PlayerPercentiles data;

  const _VerdictCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final strongest = data.strongest;
    final weakest = data.weakest;
    if (strongest == null && weakest == null) return const SizedBox.shrink();

    final spans = <InlineSpan>[];
    void add(String heading, PercentileMetric metric) {
      final entry = data.entry(metric);
      if (entry == null) return;
      if (spans.isNotEmpty) spans.add(const TextSpan(text: ' '));
      spans.add(
        TextSpan(
          text: '$heading : ',
          style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700),
        ),
      );
      spans.add(
        TextSpan(
          text:
              '${metricLabel(l10n, metric).toLowerCase()} — '
              '${formatMetric(metric, entry.value)}, '
              '${l10n.comparisonBeatsPercent(entry.percentile.round())}.',
        ),
      );
    }

    if (strongest != null) add(l10n.comparisonStrength, strongest);
    // A single-axis player has no weakest axis worth naming.
    if (weakest != null && weakest != strongest) add(l10n.comparisonWeakness, weakest);
    if (spans.isEmpty) return const SizedBox.shrink();

    return DsCard(
      padding: const EdgeInsets.all(18),
      child: Text.rich(
        TextSpan(children: spans),
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          height: 1.5,
        ),
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  final PercentileCohort cohort;

  const _Footnote({required this.cohort});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        l10n.comparisonFootnote(cohort.windowDays, cohort.minLegs),
        textAlign: TextAlign.center,
        style: AppTheme.caption.copyWith(color: AppTheme.textTertiary, height: 1.5),
      ),
    );
  }
}

class _NotEnoughLegsCard extends StatelessWidget {
  final PlayerPercentiles data;

  const _NotEnoughLegsCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final remaining = data.legsUntilEligible;
    // Two different reasons land here and they must not be mixed. Short of
    // legs: a progress bar and how many are left. Enough legs but no crowd to
    // compare against yet: no bar at all — nothing is progressing, the group
    // is simply still being built.
    final waitingOnCohort = remaining <= 0;
    final progress = data.cohort.minLegs > 0
        ? (data.legs / data.cohort.minLegs).clamp(0.0, 1.0)
        : 0.0;

    return StatsCard(
      label: l10n.comparisonTitle,
      children: [
        Text(
          waitingOnCohort
              ? l10n.comparisonLegsToGo(0)
              : l10n.comparisonNotEnoughLegs,
          style: AppTheme.bodyMedium.copyWith(fontSize: 13),
        ),
        if (!waitingOnCohort) ...[
          const SizedBox(height: 14),
          DsProgressBar(value: progress, height: 6),
          const SizedBox(height: 8),
          Text(l10n.comparisonLegsToGo(remaining), style: AppTheme.caption),
        ],
      ],
    );
  }
}

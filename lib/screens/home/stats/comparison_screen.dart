import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/player_percentiles.dart';
import '../../../services/stats_service.dart';
import '../../../utils/app_navigator.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/haptic_service.dart';
import '../../../utils/rank_translation.dart';
import 'stats_widgets.dart';

/// Where the player stands among comparable players.
///
/// Every other stats screen answers "what are my numbers"; this one answers
/// "is that good", which is the question a number on its own never settles. So
/// nothing here is shown without the cohort it was measured against — the
/// footnote and the headline both name it, and the backend widens the cohort
/// from the player's rank to everyone whenever the rank is too small to draw a
/// percentile from.
class ComparisonScreen extends StatefulWidget {
  const ComparisonScreen({super.key});

  @override
  State<ComparisonScreen> createState() => _ComparisonScreenState();
}

class _ComparisonScreenState extends State<ComparisonScreen> {
  bool _loading = true;
  String? _error;
  PlayerPercentiles? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final data = await StatsService.getPercentiles();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.comparisonTitle),
        backgroundColor: AppTheme.surface,
      ),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppTheme.error, size: 56),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: AppTheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: Text(l10n.retry)),
            ],
          ),
        ),
      );
    }

    final data = _data;
    if (data == null) return const SizedBox.shrink();

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      color: AppTheme.primary,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        itemCount: _blocks(data).length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _blocks(data)[index],
      ),
    );
  }

  /// The page's cards, in order. Built as a list rather than a fixed column so
  /// a card that has nothing to say leaves no gap where it would have been.
  List<Widget> _blocks(PlayerPercentiles data) {
    if (!data.eligible) return [_NotEnoughLegsCard(data: data)];
    return [
      _HeadlineCard(data: data),
      // Needs three corners to be a shape at all.
      if (data.metrics.length >= 3) _ProfileCard(data: data),
      if (data.metrics.isNotEmpty) _StandingCard(data: data),
      if (data.strongest != null) _VerdictCard(data: data),
      _Footnote(cohort: data.cohort),
    ];
  }
}

/// Entry point to the comparison, sitting at the top of the Form page.
///
/// Loads on its own rather than through the Matches tab's single request: the
/// standing comes from the nightly snapshots, on a different cadence and a
/// different window than the filter bar above it, and folding it into that
/// request would tie a 90-day figure to a filter that says "30 days · ranked".
/// It stays visible while the player is still short of the minimum so the
/// screen is discoverable before it has anything to compare.
class ComparisonTeaser extends StatefulWidget {
  const ComparisonTeaser({super.key});

  @override
  State<ComparisonTeaser> createState() => _ComparisonTeaserState();
}

class _ComparisonTeaserState extends State<ComparisonTeaser> {
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
      // A standing is a bonus on this page, never the reason it exists: if the
      // request fails the card simply isn't there.
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = _data;
    if (_failed || data == null) return const SizedBox.shrink();

    final top = data.topPercent;
    final headline = data.eligible && top != null
        ? l10n.comparisonTopPercent(top)
        : '—';
    final caption = data.eligible
        ? cohortLine(l10n, data.cohort)
        : l10n.comparisonLegsToGo(data.legsUntilEligible);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          HapticService.lightImpact();
          AppNavigator.toScreen(context, const ComparisonScreen());
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accent.withValues(alpha: 0.1),
                  border: Border.all(color: AppTheme.accent, width: 2),
                ),
                child: const Icon(Icons.workspace_premium, color: AppTheme.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatsLabel(l10n.comparisonTeaserLabel),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              headline,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      caption,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
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

class _HeadlineCard extends StatelessWidget {
  final PlayerPercentiles data;

  const _HeadlineCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final top = data.topPercent;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accent.withValues(alpha: 0.1),
              border: Border.all(color: AppTheme.accent, width: 3),
            ),
            child: const Icon(Icons.workspace_premium, color: AppTheme.accent, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    top != null ? l10n.comparisonTopPercent(top) : '—',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -1,
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  cohortLine(l10n, data.cohort),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
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
    return StatsCard(
      label: l10n.comparisonProfile,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _LegendDot(color: AppTheme.primary, label: l10n.comparisonTeaserLabel),
            const SizedBox(width: 14),
            _LegendDot(
              color: AppTheme.textSecondary,
              label: l10n.comparisonMedianMarker,
              dashed: true,
            ),
          ],
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 1.16,
          child: CustomPaint(
            painter: _RadarPainter(
              metrics: data.metrics,
              labels: {
                for (final metric in data.metrics)
                  metric.key: _axisLabel(l10n, metric.key),
              },
            ),
            size: Size.infinite,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;

  const _LegendDot({required this.color, required this.label, this.dashed = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            color: dashed ? null : color,
            borderRadius: BorderRadius.circular(2),
            border: dashed ? Border.all(color: color, width: 1.4) : null,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
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

  @override
  void paint(Canvas canvas, Size size) {
    if (metrics.length < 3) return;

    // Room for the labels sitting outside the outer ring.
    final radius = math.min(size.width, size.height) / 2 - 34;
    if (radius <= 0) return;
    final center = Offset(size.width / 2, size.height / 2 - 4);
    final count = metrics.length;

    Offset pointAt(int index, double fraction) {
      final angle = -math.pi / 2 + (2 * math.pi * index) / count;
      final r = radius * (_minRadiusFactor + (1 - _minRadiusFactor) * fraction);
      return center + Offset(math.cos(angle) * r, math.sin(angle) * r);
    }

    final web = Paint()
      ..color = AppTheme.surfaceLight
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Three rings at 33/66/100 % of the cohort.
    for (final ring in [1.0, 0.66, 0.33]) {
      final path = Path();
      for (var i = 0; i < count; i++) {
        final point = pointAt(i, ring);
        i == 0 ? path.moveTo(point.dx, point.dy) : path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, web);
    }

    // Spokes.
    for (var i = 0; i < count; i++) {
      canvas.drawLine(center, pointAt(i, 1), web);
    }

    // The median ring: the cohort's middle, by definition the 50th percentile.
    final medianPath = Path();
    for (var i = 0; i < count; i++) {
      final point = pointAt(i, 0.5);
      i == 0 ? medianPath.moveTo(point.dx, point.dy) : medianPath.lineTo(point.dx, point.dy);
    }
    medianPath.close();
    canvas.drawPath(
      _dashed(medianPath),
      Paint()
        ..color = AppTheme.textSecondary
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke,
    );

    // The player.
    final minePath = Path();
    for (var i = 0; i < count; i++) {
      final point = pointAt(i, (metrics[i].percentile / 100).clamp(0.0, 1.0));
      i == 0 ? minePath.moveTo(point.dx, point.dy) : minePath.lineTo(point.dx, point.dy);
    }
    minePath.close();
    canvas.drawPath(
      minePath,
      Paint()..color = AppTheme.primary.withValues(alpha: 0.22),
    );
    canvas.drawPath(
      minePath,
      Paint()
        ..color = AppTheme.primary
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    for (var i = 0; i < count; i++) {
      canvas.drawCircle(
        pointAt(i, (metrics[i].percentile / 100).clamp(0.0, 1.0)),
        4,
        Paint()..color = AppTheme.primary,
      );
    }

    _paintLabels(canvas, size, center, radius, count, pointAt);
  }

  void _paintLabels(
    Canvas canvas,
    Size size,
    Offset center,
    double radius,
    int count,
    Offset Function(int, double) pointAt,
  ) {
    for (var i = 0; i < count; i++) {
      final text = labels[metrics[i].key];
      if (text == null) continue;

      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final anchor = pointAt(i, 1);
      final direction = anchor - center;
      // Push the label clear of the outer ring, then keep it inside the canvas:
      // the left- and right-most labels are the ones that would otherwise be
      // clipped by the artboard edge.
      final offset = Offset(
        (anchor.dx + direction.dx * 0.16 - painter.width / 2)
            .clamp(0.0, math.max(0.0, size.width - painter.width)),
        (anchor.dy + direction.dy * 0.16 - painter.height / 2)
            .clamp(0.0, math.max(0.0, size.height - painter.height)),
      );
      painter.paint(canvas, offset);
    }
  }

  /// Dashes a closed path by walking its metrics — Flutter has no dash effect.
  Path _dashed(Path source, {double on = 5, double off = 4}) {
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
    return StatsCard(
      label: l10n.comparisonWhereYouStand,
      children: [
        for (final metric in data.metrics)
          _PercentileRow(entry: metric, label: metricLabel(l10n, metric.key)),
      ],
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                formatMetric(entry.key, entry.value),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.comparisonBeatsPercent(entry.percentile.round()),
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 12,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: 2,
                    left: 0,
                    right: 0,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Stack(
                        children: [
                          Container(
                            height: 8,
                            color: AppTheme.surfaceLight.withValues(alpha: 0.45),
                          ),
                          FractionallySizedBox(
                            widthFactor: fraction,
                            child: Container(
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // The median marker, always at the middle of the bar.
                  Positioned(
                    left: constraints.maxWidth / 2 - 1,
                    top: 0,
                    child: Container(width: 2, height: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
          style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
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

    return StatsCard(
      children: [
        Text.rich(
          TextSpan(children: spans),
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _Footnote extends StatelessWidget {
  final PercentileCohort cohort;

  const _Footnote({required this.cohort});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Text(
      l10n.comparisonFootnote(cohort.windowDays, cohort.minLegs),
      textAlign: TextAlign.center,
      style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, height: 1.5),
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
    final progress = data.cohort.minLegs > 0
        ? (data.legs / data.cohort.minLegs).clamp(0.0, 1.0)
        : 0.0;

    return StatsCard(
      label: l10n.comparisonTitle,
      children: [
        Text(
          l10n.comparisonNotEnoughLegs,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 13,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Stack(
            children: [
              Container(height: 8, color: AppTheme.surfaceLight.withValues(alpha: 0.45)),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(height: 8, color: AppTheme.primary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.comparisonLegsToGo(remaining),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
}

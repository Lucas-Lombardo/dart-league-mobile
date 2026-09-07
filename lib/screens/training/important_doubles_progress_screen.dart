import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/training.dart';
import '../../services/training_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import 'logic/important_doubles_strategy.dart';

/// One 60-dart block, as replayed from a stored session.
class _Block {
  final int target;
  final int hits;
  final int darts;
  final DateTime at;

  const _Block({
    required this.target,
    required this.hits,
    required this.darts,
    required this.at,
  });

  int get hitRate => hitRatePercent(hits, darts);
}

/// Everything recorded for a single double, oldest block first.
class _DoubleProgress {
  final int target;
  final List<_Block> blocks;

  const _DoubleProgress(this.target, this.blocks);

  int get sessions => blocks.length;
  int get totalDarts => blocks.fold(0, (a, b) => a + b.darts);
  int get last => blocks.last.hitRate;
  DateTime get lastAt => blocks.last.at;

  int get average {
    final hits = blocks.fold(0, (a, b) => a + b.hits);
    return hitRatePercent(hits, totalDarts);
  }

  /// Change against the previous session on this double — null on the first.
  int? get delta =>
      blocks.length < 2 ? null : last - blocks[blocks.length - 2].hitRate;

  List<int> get series => blocks.map((b) => b.hitRate).toList();
}

/// Where a double sits in the list: the strongest one reads success, the
/// weakest error, everything in between the neutral primary. Semantic only —
/// no per-drill colour.
enum _Tone { best, worst, neutral }

/// Per-double progression across Important Doubles sessions. Everything is
/// derived client-side from the stored session details — the drill writes one
/// entry per 60-dart block, so no dedicated endpoint is needed.
class ImportantDoublesProgressScreen extends StatefulWidget {
  const ImportantDoublesProgressScreen({super.key});

  @override
  State<ImportantDoublesProgressScreen> createState() =>
      _ImportantDoublesProgressScreenState();
}

class _ImportantDoublesProgressScreenState
    extends State<ImportantDoublesProgressScreen> {
  bool _loading = true;
  String? _error;
  List<_DoubleProgress> _progress = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await TrainingService.listSessions(
        type: TrainingType.importantDoubles,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _progress = _group(sessions);
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

  /// Flattens sessions into per-double timelines. The API returns newest
  /// first; each double's blocks are re-sorted oldest first so "previous
  /// session" and the sparkline read left to right.
  List<_DoubleProgress> _group(List<TrainingSessionRecord> sessions) {
    final byTarget = <int, List<_Block>>{};
    for (final s in sessions) {
      final doubles = s.details?['doubles'];
      if (doubles is! List) continue;
      for (final entry in doubles) {
        if (entry is! Map) continue;
        final target = (entry['target'] as num?)?.toInt();
        final hits = (entry['hits'] as num?)?.toInt();
        final darts = (entry['darts'] as num?)?.toInt();
        if (target == null || hits == null || darts == null || darts <= 0) {
          continue;
        }
        byTarget
            .putIfAbsent(target, () => [])
            .add(
              _Block(
                target: target,
                hits: hits,
                darts: darts,
                at: s.completedAt ?? s.createdAt,
              ),
            );
      }
    }
    final result = byTarget.entries.map((e) {
      final blocks = e.value..sort((a, b) => a.at.compareTo(b.at));
      return _DoubleProgress(e.key, blocks);
    }).toList();
    // Most recently trained double first — that's the one being worked on.
    result.sort((a, b) => b.lastAt.compareTo(a.lastAt));
    return result;
  }

  /// The strongest and the weakest double of the list, so the two rows that
  /// matter can be read at a glance. Null while there is nothing to compare.
  (int?, int?) get _extremes {
    if (_progress.length < 2) return (null, null);
    var best = _progress.first;
    var worst = _progress.first;
    for (final p in _progress) {
      if (p.average > best.average) best = p;
      if (p.average < worst.average) worst = p;
    }
    if (best.average == worst.average) return (null, null);
    return (best.target, worst.target);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l10n.trainingProgressTitle)),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: AppTheme.primary,
          ),
        ),
      );
    }
    if (_error != null) {
      return _centeredCard(
        icon: Icons.error_outline_rounded,
        title: _error!,
        action: ElevatedButton(onPressed: _load, child: Text(l10n.retry)),
      );
    }
    if (_progress.isEmpty) {
      return _centeredCard(
        icon: Icons.my_location_outlined,
        title: l10n.trainingProgressEmptyTitle,
        subtitle: l10n.trainingProgressEmpty,
      );
    }
    final (bestTarget, worstTarget) = _extremes;
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: _progress.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final p = _progress[i];
          return _DoubleCard(
            progress: p,
            tone: p.target == bestTarget
                ? _Tone.best
                : p.target == worstTarget
                ? _Tone.worst
                : _Tone.neutral,
          );
        },
      ),
    );
  }

  /// Empty / error state: one card, a quiet 32 px icon, a row title and an
  /// optional caption.
  Widget _centeredCard({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DsCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 32, color: AppTheme.textTertiary),
              const SizedBox(height: 14),
              Text(
                title,
                style: AppTheme.rowTitle,
                textAlign: TextAlign.center,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: AppTheme.caption,
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, height: 48, child: action),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One double: its name, its hit rate, the bar, the volume caption and — once
/// there are two sessions — the session-by-session sparkline.
class _DoubleCard extends StatelessWidget {
  final _DoubleProgress progress;
  final _Tone tone;

  const _DoubleCard({required this.progress, required this.tone});

  Color get _color => switch (tone) {
    _Tone.best => AppTheme.success,
    _Tone.worst => AppTheme.error,
    _Tone.neutral => AppTheme.primary,
  };

  /// "hier" / "aujourd’hui" / "4 sept." — lower-cased so it reads inside the
  /// caption sentence.
  String _lastSessionDay(BuildContext context, AppLocalizations l10n) {
    final at = progress.lastAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    if (day == today) return l10n.todayLabel.toLowerCase();
    if (day == today.subtract(const Duration(days: 1))) {
      return l10n.yesterdayLabel.toLowerCase();
    }
    try {
      return DateFormat(
        'd MMM',
        Localizations.localeOf(context).languageCode,
      ).format(at);
    } catch (_) {
      return DateFormat('MMM d').format(at);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final delta = progress.delta;
    return DsCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text('D${progress.target}', style: AppTheme.sectionTitle),
              ),
              if (delta != null) ...[
                _DeltaTag(delta: delta),
                const SizedBox(width: 12),
              ],
              Text(
                '${progress.average} %',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DsProgressBar(
            value: progress.average / 100,
            color: _color,
            height: 6,
          ),
          const SizedBox(height: 10),
          Text(
            '${l10n.trainingProgressSessionsDarts(progress.sessions, progress.totalDarts)}'
            ' · ${l10n.trainingProgressLastSession(_lastSessionDay(context, l10n))}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption,
          ),
          if (progress.series.length > 1) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 44,
              child: CustomPaint(
                painter: _SparklinePainter(progress.series),
                size: Size.infinite,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Change since the previous session on this double: up is success, down is
/// error, flat is quiet. No pill — the colour of the number says it.
class _DeltaTag extends StatelessWidget {
  final int delta;

  const _DeltaTag({required this.delta});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final flat = delta == 0;
    final up = delta > 0;
    final color = flat
        ? AppTheme.textTertiary
        : up
        ? AppTheme.success
        : AppTheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          flat
              ? Icons.remove_rounded
              : up
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded,
          color: color,
          size: 14,
        ),
        const SizedBox(width: 3),
        Text(
          l10n.ptsLabel(delta.abs()),
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Hit rate session after session, in the accent of the system: a primary
/// line over a quiet baseline. Scaled from 0 to the best score of the series
/// (floored at 10) so the line shows absolute level, not a zoomed-in wiggle
/// that makes a 1-point change look like a breakthrough.
class _SparklinePainter extends CustomPainter {
  final List<int> values;

  _SparklinePainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final max = values.reduce((a, b) => a > b ? a : b).clamp(10, 100);
    final dx = size.width / (values.length - 1);
    double yFor(int v) => size.height - (v / max) * size.height;

    // The axis the line is read against.
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = AppTheme.textTertiary.withValues(alpha: 0.4)
        ..strokeWidth = 1,
    );

    final points = <Offset>[
      for (var i = 0; i < values.length; i++) Offset(i * dx, yFor(values[i])),
    ];

    final fill = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fill.lineTo(p.dx, p.dy);
    }
    fill.lineTo(points.last.dx, size.height);
    fill.close();
    canvas.drawPath(
      fill,
      Paint()..color = AppTheme.primary.withValues(alpha: 0.14),
    );

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = AppTheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(points.last, 3.5, Paint()..color = AppTheme.primary);
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      !identical(oldDelegate.values, values);
}

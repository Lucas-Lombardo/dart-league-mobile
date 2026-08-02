import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/training.dart';
import '../../services/training_service.dart';
import '../../utils/app_theme.dart';
import 'logic/important_doubles_strategy.dart';
import 'training_select_screen.dart' show kImportantDoublesColor;

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
  int get best => blocks.map((b) => b.hitRate).reduce((a, b) => a > b ? a : b);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.trainingProgressTitle)),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: kImportantDoublesColor),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: AppTheme.error)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    }
    if (_progress.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.my_location,
                size: 48,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(height: 16),
              Text(
                l10n.trainingProgressEmpty,
                style: AppTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kImportantDoublesColor,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        itemCount: _progress.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _DoubleCard(progress: _progress[i]),
      ),
    );
  }
}

class _DoubleCard extends StatelessWidget {
  final _DoubleProgress progress;

  const _DoubleCard({required this.progress});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final delta = progress.delta;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: kImportantDoublesColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'D${progress.target}',
                style: const TextStyle(
                  color: kImportantDoublesColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.trainingProgressSessionsDarts(
                    progress.sessions,
                    progress.totalDarts,
                  ),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              if (delta != null) _DeltaPill(delta: delta),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _metric(
                  label: l10n.trainingBest,
                  value: '${progress.best} %',
                  color: AppTheme.success,
                ),
              ),
              _divider(),
              Expanded(
                child: _metric(
                  label: l10n.trainingAverage,
                  value: '${progress.average} %',
                  color: AppTheme.primary,
                ),
              ),
              _divider(),
              Expanded(
                child: _metric(
                  label: l10n.trainingLast,
                  value: '${progress.last} %',
                  color: AppTheme.accent,
                ),
              ),
            ],
          ),
          if (progress.series.length > 1) ...[
            const SizedBox(height: 16),
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

  Widget _divider() =>
      Container(width: 1, height: 36, color: AppTheme.surfaceLight);

  Widget _metric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _DeltaPill extends StatelessWidget {
  final int delta;

  const _DeltaPill({required this.delta});

  @override
  Widget build(BuildContext context) {
    final flat = delta == 0;
    final up = delta > 0;
    final color = flat
        ? AppTheme.textSecondary
        : up
        ? AppTheme.success
        : AppTheme.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            flat
                ? Icons.remove
                : up
                ? Icons.arrow_upward
                : Icons.arrow_downward,
            color: color,
            size: 13,
          ),
          const SizedBox(width: 4),
          Text(
            '${delta.abs()} pts',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Hit rate session after session. Scaled from 0 to the best score of the
/// series (floored at 10) so the line shows absolute level, not a zoomed-in
/// wiggle that makes a 1-point change look like a breakthrough.
class _SparklinePainter extends CustomPainter {
  final List<int> values;

  _SparklinePainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final max = values.reduce((a, b) => a > b ? a : b).clamp(10, 100);
    final dx = size.width / (values.length - 1);
    double yFor(int v) => size.height - (v / max) * size.height;

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
      Paint()..color = kImportantDoublesColor.withValues(alpha: 0.14),
    );

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = kImportantDoublesColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawCircle(
      points.last,
      3.5,
      Paint()..color = kImportantDoublesColor,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      !identical(oldDelegate.values, values);
}

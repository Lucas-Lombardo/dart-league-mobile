import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/training.dart';
import '../../services/training_service.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';
import '../training/logic/atc_mode.dart';
import '../training/logic/atc_strategy.dart';
import '../training/logic/bobs_27_strategy.dart';
import '../training/logic/checkout_50_strategy.dart';
import '../training/logic/checkout_finish_strategy.dart';
import '../training/logic/high_score_strategy.dart';
import '../training/logic/jdc_challenge_strategy.dart';
import '../training/logic/training_strategy.dart';
import '../training/checkout_vision_screen.dart';
import '../training/important_doubles_progress_screen.dart';
import '../training/quick_count_screen.dart';
import '../training/training_ai_screen.dart';
import '../training/training_select_screen.dart';
import 'stats/stats_widgets.dart';

class TrainingStatsTab extends StatefulWidget {
  const TrainingStatsTab({super.key});

  @override
  State<TrainingStatsTab> createState() => _TrainingStatsTabState();
}

class _TrainingStatsTabState extends State<TrainingStatsTab> {
  bool _loading = true;
  String? _error;
  List<TrainingTypeStats> _stats = const [];

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
      final stats = await TrainingService.getStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
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
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          DsCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.error_outline_rounded, size: 32, color: AppTheme.textTertiary),
                const SizedBox(height: 10),
                Text(_error!, textAlign: TextAlign.center, style: AppTheme.caption),
                const SizedBox(height: 14),
                OutlinedButton(onPressed: _load, child: Text(l10n.retry)),
              ],
            ),
          ),
        ],
      );
    }
    final hasAny = _stats.any((s) => s.sessions > 0);
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DsSectionHeader(title: l10n.trainingStatsHeader),
            const SizedBox(height: 12),
            if (!hasAny)
              _buildEmpty(l10n)
            else
              for (var i = 0; i < _stats.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                TrainingStatCard(
                  stats: _stats[i],
                  onTap: () => _openTraining(_stats[i].type),
                  // Only Important Doubles records a per-target breakdown
                  // worth charting session over session.
                  onProgress: _stats[i].type == TrainingType.importantDoubles &&
                          _stats[i].sessions > 0
                      ? () {
                          HapticService.lightImpact();
                          AppNavigator.toScreen(
                            context,
                            const ImportantDoublesProgressScreen(),
                          );
                        }
                      : null,
                ),
              ],
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: () {
                HapticService.mediumImpact();
                AppNavigator.toScreen(
                  context,
                  const TrainingSelectScreen(),
                ).then((_) => _load());
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(dsSentence(l10n.trainingStartNewSession)),
            ),
          ],
        ),
      ),
    );
  }

  void _openTraining(TrainingType type) {
    HapticService.mediumImpact();
    TrainingStrategy strategy;
    switch (type) {
      case TrainingType.aroundTheClock:
        strategy = AtcStrategy(mode: AtcMode.single);
        break;
      case TrainingType.aroundTheClockDouble:
        strategy = AtcStrategy(mode: AtcMode.double);
        break;
      case TrainingType.aroundTheClockTriple:
        strategy = AtcStrategy(mode: AtcMode.triple);
        break;
      case TrainingType.bobs27:
        strategy = Bobs27Strategy();
        break;
      case TrainingType.highScore:
        strategy = HighScoreStrategy();
        break;
      case TrainingType.checkout50:
        strategy = Checkout50Strategy();
        break;
      case TrainingType.checkout81:
        strategy = CheckoutFinishStrategy(startScore: 81);
        break;
      case TrainingType.checkout121:
        strategy = CheckoutFinishStrategy(startScore: 121);
        break;
      case TrainingType.botTraining:
        // Bot training doesn't use the strategy/TrainingAiScreen flow — it
        // reuses the placement game screens. Open the rank picker, which
        // routes through the placement camera setup on selection.
        openBotTrainingPicker(context).then((_) => _load());
        return;
      case TrainingType.jdcChallenge:
        strategy = JdcChallengeStrategy();
        break;
      case TrainingType.importantDoubles:
        // Needs its targets picked first, like bot training needs a rank.
        openImportantDoublesPicker(context).then((_) => _load());
        return;
      case TrainingType.quickCount:
        // Camera-free quiz — no strategy, its screen is self-contained.
        AppNavigator.toScreen(
          context,
          const QuickCountScreen(),
        ).then((_) => _load());
        return;
      case TrainingType.checkoutVision:
        AppNavigator.toScreen(
          context,
          const CheckoutVisionScreen(),
        ).then((_) => _load());
        return;
    }
    AppNavigator.toScreen(
      context,
      TrainingAiScreen(strategy: strategy),
    ).then((_) => _load());
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    return DsCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.fitness_center_rounded, size: 32, color: AppTheme.textTertiary),
          const SizedBox(height: 10),
          Text(l10n.trainingNoSessionsYet, textAlign: TextAlign.center, style: AppTheme.rowTitle),
          const SizedBox(height: 4),
          Text(
            l10n.trainingCompleteSessionToTrack,
            textAlign: TextAlign.center,
            style: AppTheme.caption,
          ),
        ],
      ),
    );
  }
}

/// One exercise: icon disc, name, chevron, then its best / average / last /
/// attempts (or the bot and quiz variants).
class TrainingStatCard extends StatelessWidget {
  final TrainingTypeStats stats;
  final VoidCallback onTap;

  /// Opens a drill-specific progression view. Null when the drill has none.
  final VoidCallback? onProgress;

  const TrainingStatCard({
    super.key,
    required this.stats,
    required this.onTap,
    this.onProgress,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = trainingDisplayName(l10n, stats.type);
    final hasData = stats.sessions > 0;
    return DsCard(
      radius: AppTheme.radiusRow,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
                child: Icon(_iconFor(stats.type), size: 20, color: const Color(0xFFE2E8F0)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.sectionTitle,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textTertiary),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasData)
            Text(
              l10n.trainingNotYetPlayed,
              style: AppTheme.caption.copyWith(fontStyle: FontStyle.italic),
            )
          else if (stats.type == TrainingType.botTraining)
            _BotTrainingModes(stats: stats)
          else if (stats.type == TrainingType.importantDoubles)
            _percentRow(l10n)
          else if (stats.type == TrainingType.quickCount ||
              stats.type == TrainingType.checkoutVision)
            _quizRow(l10n)
          else
            _defaultRow(l10n),
          if (onProgress != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onProgress,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.show_chart_rounded, size: 16),
                label: Text(l10n.trainingViewProgress),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Best/average/last as percentages — Important Doubles scores a hit rate,
  /// so a bare "21" would read as points.
  Widget _percentRow(AppLocalizations l10n) {
    String pct(num? v) => v == null ? '—' : '${_formatNum(v)} %';
    return _MetricsRow(
      metrics: [
        _Metric(l10n.trainingBest, pct(stats.bestScore), AppTheme.success),
        _Metric(l10n.trainingAverage, pct(stats.averageScore), AppTheme.primaryLight),
        _Metric(l10n.trainingLast, pct(stats.lastScore), AppTheme.textPrimary),
        _Metric(l10n.trainingAttempts, '${stats.sessions}', AppTheme.textSecondary),
      ],
    );
  }

  /// Quiz drills (Calcul family): accuracy percentages plus the average
  /// answer time the backend aggregates from the session details.
  Widget _quizRow(AppLocalizations l10n) {
    String pct(num? v) => v == null ? '—' : '${_formatNum(v)} %';
    final avgMs = stats.averageAnswerMs;
    final time = avgMs == null
        ? '—'
        : '${(avgMs / 1000).toStringAsFixed(1)} s';
    return _MetricsRow(
      metrics: [
        _Metric(l10n.trainingBest, pct(stats.bestScore), AppTheme.success),
        _Metric(l10n.trainingAverage, pct(stats.averageScore), AppTheme.primaryLight),
        _Metric(l10n.trainingQuizTimeAvgLabel, time, AppTheme.textPrimary),
        _Metric(l10n.trainingAttempts, '${stats.sessions}', AppTheme.textSecondary),
      ],
    );
  }

  Widget _defaultRow(AppLocalizations l10n) {
    final bestLabel = stats.higherIsBetter
        ? l10n.trainingBest
        : l10n.trainingBestLow;
    return _MetricsRow(
      metrics: [
        _Metric(bestLabel, _formatNum(stats.bestScore), AppTheme.success),
        _Metric(l10n.trainingAverage, _formatNum(stats.averageScore), AppTheme.primaryLight),
        _Metric(l10n.trainingLast, _formatNum(stats.lastScore), AppTheme.textPrimary),
        _Metric(l10n.trainingAttempts, '${stats.sessions}', AppTheme.textSecondary),
      ],
    );
  }

  String _formatNum(num? v) {
    if (v == null) return '—';
    if (v == v.toInt()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  IconData _iconFor(TrainingType type) {
    switch (type) {
      case TrainingType.aroundTheClock:
      case TrainingType.aroundTheClockDouble:
      case TrainingType.aroundTheClockTriple:
        return Icons.schedule_outlined;
      case TrainingType.bobs27:
        return Icons.gps_fixed_rounded;
      case TrainingType.highScore:
        return Icons.local_fire_department_outlined;
      case TrainingType.checkout50:
        return Icons.center_focus_strong_outlined;
      case TrainingType.checkout81:
      case TrainingType.checkout121:
        return Icons.flag_outlined;
      case TrainingType.botTraining:
        return Icons.smart_toy_outlined;
      case TrainingType.jdcChallenge:
        return Icons.emoji_events_outlined;
      case TrainingType.importantDoubles:
        return Icons.my_location_outlined;
      case TrainingType.quickCount:
        return Icons.calculate_outlined;
      case TrainingType.checkoutVision:
        return Icons.track_changes_rounded;
    }
  }
}

class _Metric {
  final String label;
  final String value;
  final Color color;

  const _Metric(this.label, this.value, this.color);
}

/// Equal columns separated by hairlines: group label over a 16 / 700 figure.
class _MetricsRow extends StatelessWidget {
  final List<_Metric> metrics;

  const _MetricsRow({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0) Container(width: 1, height: 32, color: AppTheme.border),
          Expanded(
            child: Column(
              children: [
                Text(
                  metrics[i].label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTheme.labelSmall.copyWith(fontSize: 10, letterSpacing: 0.8),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    metrics[i].value,
                    style: TextStyle(
                      color: metrics[i].color,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Bot-training card body: a mode filter (Tous / 501 / 301 / Cricket) over
/// the three metrics. "Tous" shows the historic all-modes aggregate; the
/// cricket chip merges both variants and switches the middle metric to MPR.
/// Chips only appear for modes actually played (and at least two of them).
class _BotTrainingModes extends StatefulWidget {
  final TrainingTypeStats stats;

  const _BotTrainingModes({required this.stats});

  @override
  State<_BotTrainingModes> createState() => _BotTrainingModesState();
}

class _BotTrainingModesState extends State<_BotTrainingModes> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final modes = widget.stats.modes ?? const <BotModeStats>[];

    final available = <String>[
      if (modes.any((m) => m.mode == '501' && m.sessions > 0)) '501',
      if (modes.any((m) => m.mode == '301' && m.sessions > 0)) '301',
      if (modes.any((m) => m.mode.startsWith('cricket') && m.sessions > 0))
        'cricket',
    ];
    final showChips = available.length > 1 ||
        (available.length == 1 && available.first != '501');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showChips) ...[
          Row(
            children: [
              _chip(l10n.statsFilterAll, 'all'),
              for (final mode in available) ...[
                const SizedBox(width: 6),
                _chip(mode == 'cricket' ? l10n.cricketLabel : mode, mode),
              ],
            ],
          ),
          const SizedBox(height: 12),
        ],
        _metricsRow(l10n),
      ],
    );
  }

  Widget _chip(String label, String value) {
    return StatsChip(
      label: label,
      selected: _filter == value,
      onTap: () => setState(() => _filter = value),
    );
  }

  Widget _metricsRow(AppLocalizations l10n) {
    int sessions;
    num? avg;
    num? winRate;
    var isCricket = false;

    if (_filter == 'all') {
      sessions = widget.stats.sessions;
      avg = widget.stats.averageScore;
      winRate = widget.stats.winRate;
      // The backend's global average only aggregates X01 sessions (cricket
      // ones carry an MPR, not a 3-dart average). Next to a session count
      // that includes cricket it would pass one mode's average off as the
      // whole history's — show nothing and let the per-mode chips answer.
      final modes = widget.stats.modes ?? const <BotModeStats>[];
      final hasCricket =
          modes.any((m) => m.mode.startsWith('cricket') && m.sessions > 0);
      final hasX01 =
          modes.any((m) => !m.mode.startsWith('cricket') && m.sessions > 0);
      if (hasCricket && hasX01) avg = null;
    } else if (_filter == 'cricket') {
      isCricket = true;
      final buckets = (widget.stats.modes ?? const <BotModeStats>[])
          .where((m) => m.mode.startsWith('cricket'))
          .toList();
      sessions = buckets.fold(0, (a, b) => a + b.sessions);
      num winSum = 0;
      var winWeight = 0;
      num avgSum = 0;
      var avgWeight = 0;
      for (final b in buckets) {
        // A bucket without a winRate must not weigh in the denominator, or it
        // would drag the merged rate down instead of simply being excluded.
        if (b.winRate != null) {
          winSum += b.winRate! * b.sessions;
          winWeight += b.sessions;
        }
        if (b.averageScore != null) {
          avgSum += b.averageScore! * b.sessions;
          avgWeight += b.sessions;
        }
      }
      winRate = winWeight > 0 ? winSum / winWeight : null;
      avg = avgWeight > 0 ? avgSum / avgWeight : null;
    } else {
      final bucket = (widget.stats.modes ?? const <BotModeStats>[])
          .where((m) => m.mode == _filter)
          .toList();
      sessions = bucket.isEmpty ? 0 : bucket.first.sessions;
      avg = bucket.isEmpty ? null : bucket.first.averageScore;
      winRate = bucket.isEmpty ? null : bucket.first.winRate;
    }

    String fmt(num? v) {
      if (v == null) return '—';
      if (v == v.toInt()) return v.toInt().toString();
      return v.toStringAsFixed(1);
    }

    return _MetricsRow(
      metrics: [
        _Metric(l10n.trainingGames, '$sessions', AppTheme.textSecondary),
        _Metric(
          isCricket ? 'MPR' : l10n.avgScore,
          isCricket && avg != null ? avg.toStringAsFixed(2) : fmt(avg),
          AppTheme.primaryLight,
        ),
        _Metric(
          l10n.winRate,
          winRate == null ? '—' : '${(winRate * 100).round()} %',
          AppTheme.success,
        ),
      ],
    );
  }
}

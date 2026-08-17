import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/training.dart';
import '../../services/training_service.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../training/logic/atc_mode.dart';
import '../training/logic/atc_strategy.dart';
import '../training/logic/bobs_27_strategy.dart';
import '../training/logic/checkout_50_strategy.dart';
import '../training/logic/checkout_finish_strategy.dart';
import '../training/logic/high_score_strategy.dart';
import '../training/logic/jdc_challenge_strategy.dart';
import '../training/logic/training_strategy.dart';
import '../training/important_doubles_progress_screen.dart';
import '../training/training_ai_screen.dart';
import '../training/training_select_screen.dart';

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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 64),
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
      );
    }
    final hasAny = _stats.any((s) => s.sessions > 0);
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.trainingStatsHeader, style: AppTheme.titleLarge),
            const SizedBox(height: 16),
            if (!hasAny)
              _buildEmpty(l10n)
            else
              ..._stats.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TrainingStatCard(
                    stats: s,
                    onTap: () => _openTraining(s.type),
                    // Only Important Doubles records a per-target breakdown
                    // worth charting session over session.
                    onProgress:
                        s.type == TrainingType.importantDoubles &&
                            s.sessions > 0
                        ? () {
                            HapticService.lightImpact();
                            AppNavigator.toScreen(
                              context,
                              const ImportantDoublesProgressScreen(),
                            );
                          }
                        : null,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                HapticService.mediumImpact();
                AppNavigator.toScreen(
                  context,
                  const TrainingSelectScreen(),
                ).then((_) => _load());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(l10n.trainingStartNewSession),
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
    }
    AppNavigator.toScreen(
      context,
      TrainingAiScreen(strategy: strategy),
    ).then((_) => _load());
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.fitness_center,
            size: 48,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.trainingNoSessionsYet,
            style: AppTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.trainingCompleteSessionToTrack,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TrainingStatCard extends StatelessWidget {
  final TrainingTypeStats stats;
  final VoidCallback onTap;

  /// Opens a drill-specific progression view. Null when the drill has none.
  final VoidCallback? onProgress;

  const _TrainingStatCard({
    required this.stats,
    required this.onTap,
    this.onProgress,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = trainingDisplayName(l10n, stats.type);
    final hasData = stats.sessions > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.surfaceLight.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    _iconFor(stats.type),
                    color: _colorFor(stats.type),
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(name, style: AppTheme.titleLarge)),
                  const Icon(
                    Icons.chevron_right,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!hasData)
                Text(
                  l10n.trainingNotYetPlayed,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else if (stats.type == TrainingType.botTraining)
                _BotTrainingModes(stats: stats)
              else if (stats.type == TrainingType.importantDoubles)
                _percentRow(l10n)
              else
                _defaultRow(l10n),
              if (onProgress != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onProgress,
                    style: TextButton.styleFrom(
                      foregroundColor: kImportantDoublesColor,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.show_chart, size: 18),
                    label: Text(l10n.trainingViewProgress),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Best/average/last as percentages — Important Doubles scores a hit rate,
  /// so a bare "21" would read as points.
  Widget _percentRow(AppLocalizations l10n) {
    String pct(num? v) => v == null ? '—' : '${_formatNum(v)} %';
    return Row(
      children: [
        Expanded(
          child: _metric(
            label: l10n.trainingBest,
            value: pct(stats.bestScore),
            color: AppTheme.success,
          ),
        ),
        _divider(),
        Expanded(
          child: _metric(
            label: l10n.trainingAverage,
            value: pct(stats.averageScore),
            color: AppTheme.primary,
          ),
        ),
        _divider(),
        Expanded(
          child: _metric(
            label: l10n.trainingLast,
            value: pct(stats.lastScore),
            color: AppTheme.accent,
          ),
        ),
        _divider(),
        Expanded(
          child: _metric(
            label: l10n.trainingAttempts,
            value: '${stats.sessions}',
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _defaultRow(AppLocalizations l10n) {
    final bestLabel = stats.higherIsBetter
        ? l10n.trainingBest
        : l10n.trainingBestLow;
    return Row(
      children: [
        Expanded(
          child: _metric(
            label: bestLabel,
            value: _formatNum(stats.bestScore),
            color: AppTheme.success,
          ),
        ),
        _divider(),
        Expanded(
          child: _metric(
            label: l10n.trainingAverage,
            value: _formatNum(stats.averageScore),
            color: AppTheme.primary,
          ),
        ),
        _divider(),
        Expanded(
          child: _metric(
            label: l10n.trainingLast,
            value: _formatNum(stats.lastScore),
            color: AppTheme.accent,
          ),
        ),
        _divider(),
        Expanded(
          child: _metric(
            label: l10n.trainingAttempts,
            value: '${stats.sessions}',
            color: AppTheme.textSecondary,
          ),
        ),
      ],
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
        return Icons.schedule;
      case TrainingType.bobs27:
        return Icons.gps_fixed;
      case TrainingType.highScore:
        return Icons.local_fire_department;
      case TrainingType.checkout50:
        return Icons.center_focus_strong;
      case TrainingType.checkout81:
      case TrainingType.checkout121:
        return Icons.flag_outlined;
      case TrainingType.botTraining:
        return Icons.smart_toy;
      case TrainingType.jdcChallenge:
        return Icons.emoji_events;
      case TrainingType.importantDoubles:
        return Icons.my_location;
    }
  }

  Color _colorFor(TrainingType type) {
    switch (type) {
      case TrainingType.aroundTheClock:
        return AppTheme.primary;
      case TrainingType.aroundTheClockDouble:
        return AppTheme.success;
      case TrainingType.aroundTheClockTriple:
        return AppTheme.error;
      case TrainingType.bobs27:
        return AppTheme.accent;
      case TrainingType.highScore:
        return AppTheme.error;
      case TrainingType.checkout50:
        return AppTheme.success;
      case TrainingType.checkout81:
        return AppTheme.primary;
      case TrainingType.checkout121:
        return AppTheme.accent;
      case TrainingType.botTraining:
        return AppTheme.accent;
      case TrainingType.jdcChallenge:
        return const Color(0xFFEAB308);
      case TrainingType.importantDoubles:
        return kImportantDoublesColor;
    }
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
    final selected = _filter == value;
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        setState(() => _filter = value);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.13)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : AppTheme.surfaceLight.withValues(alpha: 0.8),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
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
      num avgSum = 0;
      var avgWeight = 0;
      for (final b in buckets) {
        winSum += (b.winRate ?? 0) * b.sessions;
        if (b.averageScore != null) {
          avgSum += b.averageScore! * b.sessions;
          avgWeight += b.sessions;
        }
      }
      winRate = sessions > 0 ? winSum / sessions : null;
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

    Widget metric(String label, String value, Color color) {
      return Expanded(
        child: Column(
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
        ),
      );
    }

    Widget divider() =>
        Container(width: 1, height: 36, color: AppTheme.surfaceLight);

    return Row(
      children: [
        metric(l10n.trainingGames, '$sessions', AppTheme.textSecondary),
        divider(),
        metric(
          isCricket ? 'MPR' : l10n.avgScore,
          isCricket && avg != null ? avg.toStringAsFixed(2) : fmt(avg),
          AppTheme.primary,
        ),
        divider(),
        metric(
          l10n.winRate,
          winRate == null ? '—' : '${(winRate * 100).round()}%',
          AppTheme.success,
        ),
      ],
    );
  }
}

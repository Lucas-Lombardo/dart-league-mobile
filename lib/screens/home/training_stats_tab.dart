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
import '../training/logic/training_strategy.dart';
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
              ..._stats.map((s) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TrainingStatCard(stats: s, onTap: () => _openTraining(s.type)),
                  )),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () {
                HapticService.mediumImpact();
                AppNavigator.toScreen(context, const TrainingSelectScreen())
                    .then((_) => _load());
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
          const Icon(Icons.fitness_center,
              size: 48, color: AppTheme.textSecondary),
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

  const _TrainingStatCard({required this.stats, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = trainingDisplayName(l10n, stats.type);
    final hasData = stats.sessions > 0;
    final best = stats.bestScore;
    final avg = stats.averageScore;
    final last = stats.lastScore;
    final bestLabel =
        stats.higherIsBetter ? l10n.trainingBest : l10n.trainingBestLow;
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
                  Icon(_iconFor(stats.type),
                      color: _colorFor(stats.type), size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(name, style: AppTheme.titleLarge),
                  ),
                  const Icon(Icons.chevron_right,
                      color: AppTheme.textSecondary),
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
              else
                Row(
                  children: [
                    Expanded(
                      child: _metric(
                        label: bestLabel,
                        value: _formatNum(best),
                        color: AppTheme.success,
                      ),
                    ),
                    _divider(),
                    Expanded(
                      child: _metric(
                        label: l10n.trainingAverage,
                        value: _formatNum(avg),
                        color: AppTheme.primary,
                      ),
                    ),
                    _divider(),
                    Expanded(
                      child: _metric(
                        label: l10n.trainingLast,
                        value: _formatNum(last),
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
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 36,
        color: AppTheme.surfaceLight,
      );

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
    }
  }
}

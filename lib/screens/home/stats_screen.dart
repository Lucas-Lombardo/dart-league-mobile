import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import 'ranked_stats_tab.dart';
import 'training_stats_tab.dart';

enum StatsTab { ranked, training }

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  StatsTab _tab = StatsTab.ranked;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: _TabButton(
                  label: l10n.rankedStatsTab,
                  icon: Icons.military_tech_outlined,
                  selected: _tab == StatsTab.ranked,
                  onTap: () => _selectTab(StatsTab.ranked),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TabButton(
                  label: l10n.trainingStatsTab,
                  icon: Icons.fitness_center,
                  selected: _tab == StatsTab.training,
                  onTap: () => _selectTab(StatsTab.training),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _tab == StatsTab.ranked
              ? const RankedStatsTab()
              : const TrainingStatsTab(),
        ),
      ],
    );
  }

  void _selectTab(StatsTab tab) {
    if (tab == _tab) return;
    HapticService.lightImpact();
    setState(() => _tab = tab);
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.18)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? AppTheme.primary
                  : AppTheme.surfaceLight.withValues(alpha: 0.5),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppTheme.primary : AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppTheme.primary : AppTheme.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

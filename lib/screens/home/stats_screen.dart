import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_navigator.dart';
import '../profile/replay_library_screen.dart';
import 'stats/matches_stats_tab.dart';
import 'training_stats_tab.dart';

enum StatsTab { matches, training }

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  StatsTab _tab = StatsTab.matches;

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
                  // "Classé" is no longer a tab — it moved into the Mode filter,
                  // alongside friendly, tournament and bot legs.
                  label: l10n.matchStatsTab,
                  icon: Icons.sports_esports_outlined,
                  selected: _tab == StatsTab.matches,
                  onTap: () => _selectTab(StatsTab.matches),
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
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: _ReplaysEntryCard(l10n: l10n),
        ),
        Expanded(
          child: _tab == StatsTab.matches
              ? const MatchesStatsTab()
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


/// Slim entry to the replay library — the clips live in « Mes replays »,
/// reachable from the player's own stats page (no extra nav item).
class _ReplaysEntryCard extends StatelessWidget {
  final AppLocalizations l10n;

  const _ReplaysEntryCard({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        AppNavigator.toScreen(context, const ReplayLibraryScreen());
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppTheme.playerBlue.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.movie_outlined,
                color: AppTheme.playerBlue, size: 20),
            const SizedBox(width: 10),
            Text(
              l10n.myReplays,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right,
                color: AppTheme.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

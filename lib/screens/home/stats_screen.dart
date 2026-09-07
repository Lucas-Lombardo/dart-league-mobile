import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_navigator.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';
import '../profile/match_history_screen.dart';
import 'stats/matches_stats_tab.dart';
import 'stats/stats_widgets.dart';
import 'training_stats_tab.dart';

enum StatsTab { matches, training }

/// The Stats tab: its own header (the shell draws none for bottom-bar tabs),
/// a Matchs / Entraînement segmented control, and the selected page.
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
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: DsScreenHeader(
            title: l10n.stats,
            actions: [
              DsIconButton(
                icon: Icons.history_rounded,
                tooltip: dsSentence(l10n.viewFullMatchHistory),
                onTap: () => AppNavigator.toScreen(context, const MatchHistoryScreen()),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: StatsSegmentedControl(
            // "Classé" is no longer a tab — it moved into the Mode filter,
            // alongside friendly, tournament and bot legs.
            labels: [l10n.matchStatsTab, l10n.trainingStatsTab],
            index: _tab.index,
            onChanged: (i) => _selectTab(StatsTab.values[i]),
          ),
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

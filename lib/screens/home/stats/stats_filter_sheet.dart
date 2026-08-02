import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/stats_summary.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/haptic_service.dart';

class StatsFilter {
  final StatsPeriod period;
  final Set<MatchMode> modes;

  const StatsFilter({required this.period, required this.modes});

  StatsFilter copyWith({StatsPeriod? period, Set<MatchMode>? modes}) =>
      StatsFilter(period: period ?? this.period, modes: modes ?? this.modes);
}

/// The two filter rows of the original design collapsed into one sheet. On a
/// phone those rows cost ~45 px at the top of every single page; here they cost
/// one line, and the current selection stays readable without opening anything.
Future<StatsFilter?> showStatsFilterSheet(
  BuildContext context,
  StatsFilter current,
) {
  return showModalBottomSheet<StatsFilter>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      var draft = current;
      final l10n = AppLocalizations.of(sheetContext);

      return StatefulBuilder(
        builder: (builderContext, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(l10n.statsFilters, style: AppTheme.titleLarge),
                  const SizedBox(height: 20),
                  _SheetLabel(l10n.statsPeriod),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final period in StatsPeriod.values)
                        _Chip(
                          label: _periodLabel(l10n, period),
                          selected: draft.period == period,
                          onTap: () {
                            HapticService.lightImpact();
                            setSheetState(() => draft = draft.copyWith(period: period));
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _SheetLabel(l10n.statsMode),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final mode in MatchMode.values)
                        _Chip(
                          label: modeLabel(l10n, mode),
                          selected: draft.modes.contains(mode),
                          onTap: () {
                            final next = {...draft.modes};
                            // Clearing the last mode would show an empty screen
                            // with no way back, so the last one is sticky.
                            if (next.contains(mode) && next.length == 1) return;
                            HapticService.lightImpact();
                            next.contains(mode) ? next.remove(mode) : next.add(mode);
                            setSheetState(() => draft = draft.copyWith(modes: next));
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  ElevatedButton(
                    onPressed: () {
                      HapticService.mediumImpact();
                      Navigator.of(builderContext).pop(draft);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(l10n.statsApply),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

String _periodLabel(AppLocalizations l10n, StatsPeriod period) => switch (period) {
  StatsPeriod.last7Days => l10n.statsPeriod7,
  StatsPeriod.last30Days => l10n.statsPeriod30,
  StatsPeriod.last90Days => l10n.statsPeriod90,
  StatsPeriod.all => l10n.statsPeriodAll,
};

String modeLabel(AppLocalizations l10n, MatchMode mode) => switch (mode) {
  MatchMode.ranked => l10n.statsModeRanked,
  MatchMode.friendly => l10n.statsModeFriendly,
  MatchMode.tournament => l10n.statsModeTournament,
  MatchMode.placement => l10n.statsModeBot,
};

String periodLabel(AppLocalizations l10n, StatsPeriod period) => _periodLabel(l10n, period);

class _SheetLabel extends StatelessWidget {
  final String text;

  const _SheetLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.primary : AppTheme.surfaceLight,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppTheme.primary : AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

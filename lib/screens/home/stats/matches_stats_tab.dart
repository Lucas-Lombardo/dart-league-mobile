import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/stats_summary.dart';
import '../../../services/stats_service.dart';
import '../../../utils/app_navigator.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/haptic_service.dart';
import '../../profile/match_history_screen.dart';
import 'stats_filter_sheet.dart';
import 'stats_pages.dart';

enum _SubTab { form, scoring, finishing, consistency }

/// The Matches tab: one filter bar, four sub-tabs, one network request.
///
/// Replaces the old single-scroll layout where four equally weighted cards
/// competed for attention. Each sub-tab now owns one subject, and the Form tab
/// repeats the other three headline numbers so the most common visit — "where
/// am I at" — still costs no navigation at all.
class MatchesStatsTab extends StatefulWidget {
  const MatchesStatsTab({super.key});

  @override
  State<MatchesStatsTab> createState() => _MatchesStatsTabState();
}

class _MatchesStatsTabState extends State<MatchesStatsTab> {
  // Ranked only by default. Pooling ranked with bot placement legs is exactly
  // what made the old numbers meaningless.
  StatsFilter _filter = const StatsFilter(
    period: StatsPeriod.last30Days,
    modes: {MatchMode.ranked},
  );
  _SubTab _tab = _SubTab.form;
  bool _loading = true;
  String? _error;
  StatsSummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [showSpinner] is off for pull-to-refresh: swapping the list for a spinner
  /// would unmount the RefreshIndicator's own child while it is still running.
  Future<void> _load({bool showSpinner = true}) async {
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final summary = await StatsService.getSummary(
        period: _filter.period,
        modes: _filter.modes,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
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

  Future<void> _openFilters() async {
    HapticService.lightImpact();
    final next = await showStatsFilterSheet(context, _filter);
    if (next == null || !mounted) return;
    setState(() => _filter = next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: _FilterBar(filter: _filter, onTap: _openFilters),
        ),
        const SizedBox(height: 12),
        _SubTabBar(
          current: _tab,
          onSelect: (tab) {
            if (tab == _tab) return;
            HapticService.lightImpact();
            setState(() => _tab = tab);
          },
        ),
        Expanded(child: _buildBody(l10n)),
      ],
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

    final summary = _summary;
    if (summary == null || summary.isEmpty) return _buildEmpty(l10n);

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      color: AppTheme.primary,
      child: switch (_tab) {
        _SubTab.form => StatsFormPage(summary: summary),
        _SubTab.scoring => StatsScoringPage(summary: summary),
        _SubTab.finishing => StatsFinishingPage(summary: summary),
        _SubTab.consistency => StatsConsistencyPage(summary: summary),
      },
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      color: AppTheme.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                const Icon(Icons.query_stats, size: 46, color: AppTheme.textSecondary),
                const SizedBox(height: 16),
                Text(
                  l10n.statsNoDataForFilter,
                  style: AppTheme.bodyLarge.copyWith(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.statsNoDataHint,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.45,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => AppNavigator.toScreen(context, const MatchHistoryScreen()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.surfaceLight,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
            ),
            icon: const Icon(Icons.history_rounded),
            label: Text(l10n.viewFullMatchHistory),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final StatsFilter filter;
  final VoidCallback onTap;

  const _FilterBar({required this.filter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final modes = MatchMode.values
        .where(filter.modes.contains)
        .map((m) => modeLabel(l10n, m))
        .join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppTheme.surfaceLight.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Text(
                periodLabel(l10n, filter.period),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 7),
                child: Text('·', style: TextStyle(color: AppTheme.textSecondary)),
              ),
              Expanded(
                child: Text(
                  modes,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Icon(Icons.expand_more, color: AppTheme.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubTabBar extends StatelessWidget {
  final _SubTab current;
  final ValueChanged<_SubTab> onSelect;

  const _SubTabBar({required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = {
      _SubTab.form: l10n.statsSubtabForm,
      _SubTab.scoring: l10n.statsSubtabScoring,
      _SubTab.finishing: l10n.statsSubtabFinishing,
      _SubTab.consistency: l10n.statsSubtabConsistency,
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.surfaceLight)),
      ),
      child: Row(
        children: [
          for (final tab in _SubTab.values)
            Expanded(
              child: InkWell(
                onTap: () => onSelect(tab),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 9, top: 2),
                  child: Column(
                    children: [
                      // The four labels must all stay visible — the whole point
                      // of this layout — so they shrink rather than scroll.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          labels[tab]!,
                          style: TextStyle(
                            color: current == tab ? AppTheme.primary : AppTheme.textSecondary,
                            fontSize: 14,
                            fontWeight: current == tab ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        height: 2,
                        color: current == tab ? AppTheme.primary : Colors.transparent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/stats_summary.dart';
import '../../../services/stats_service.dart';
import '../../../utils/app_navigator.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/haptic_service.dart';
import '../../../widgets/design_system.dart';
import '../../profile/match_history_screen.dart';
import 'stats_filter_sheet.dart';
import 'stats_pages.dart';

/// The Matches tab: one page, one network request.
///
/// It was four sub-tabs (form, scoring, finishing, consistency) until the
/// figures they held could be read against other players: once every headline
/// number carries a percentile, splitting them across screens only hid them.
/// The filter bar is passed down into the page rather than pinned here — it
/// governs the figures below it and not the standing above it.
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
    return _buildBody(l10n);
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
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

    final summary = _summary;
    if (summary == null || summary.isEmpty) return _buildEmpty(l10n);

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      color: AppTheme.primary,
      child: StatsOverviewPage(
        summary: summary,
        filterBar: StatsFilterBar(filter: _filter, onTap: _openFilters),
      ),
    );
  }

  /// No leg matches the filter. The filter pill stays so the player can widen
  /// it — otherwise a narrow filter would leave no way back.
  Widget _buildEmpty(AppLocalizations l10n) {
    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      color: AppTheme.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          StatsFilterBar(filter: _filter, onTap: _openFilters),
          const SizedBox(height: 12),
          DsCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.query_stats_rounded, size: 32, color: AppTheme.textTertiary),
                const SizedBox(height: 10),
                Text(l10n.statsNoDataForFilter, textAlign: TextAlign.center, style: AppTheme.rowTitle),
                const SizedBox(height: 4),
                Text(
                  l10n.statsNoDataHint,
                  textAlign: TextAlign.center,
                  style: AppTheme.caption.copyWith(height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => AppNavigator.toScreen(context, const MatchHistoryScreen()),
            icon: const Icon(Icons.history_rounded, size: 20),
            label: Text(dsSentence(l10n.viewFullMatchHistory)),
          ),
        ],
      ),
    );
  }
}

/// "30 j · Classé ▾" — the current filter in one line; tapping opens the sheet.
class StatsFilterBar extends StatelessWidget {
  final StatsFilter filter;
  final VoidCallback onTap;

  const StatsFilterBar({super.key, required this.filter, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final modes = MatchMode.values
        .where(filter.modes.contains)
        .map((m) => modeLabel(l10n, m))
        .join(' · ');

    return SizedBox(
      height: 40,
      child: DsCard(
        radius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        onTap: onTap,
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${periodLabel(l10n, filter.period)} · $modes',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.expand_more_rounded, color: AppTheme.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }
}

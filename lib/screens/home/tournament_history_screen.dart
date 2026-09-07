import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/tournament_provider.dart';
import '../../models/tournament.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/design_system.dart';
import 'tournament_detail_screen.dart';

/// Past tournaments, one 72 px row each: name (gold cup when a physical prize
/// was won), "date · N joueurs", and the final placement on the right — gold /
/// silver / bronze for the podium, quiet grey below it. A two-segment scope
/// toggle narrows the list to the tournaments the user actually played.
class TournamentHistoryScreen extends StatefulWidget {
  const TournamentHistoryScreen({super.key});

  @override
  State<TournamentHistoryScreen> createState() => _TournamentHistoryScreenState();
}

class _TournamentHistoryScreenState extends State<TournamentHistoryScreen> {
  // Default view is every completed tournament; the toggle narrows the list
  // to the ones the user actually played.
  bool _showOnlyMine = false;

  @override
  void initState() {
    super.initState();
    // After the first frame: loadTournamentHistory() notifies synchronously,
    // and calling it straight from initState marked the Consumer dirty while
    // the tree was still building ("setState during build").
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadHistory();
    });
  }

  Future<void> _loadHistory() async {
    final provider = context.read<TournamentProvider>();
    await provider.loadTournamentHistory();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l10n.tournamentHistoryTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: _ScopeToggle(
              showOnlyMine: _showOnlyMine,
              onChanged: (mine) {
                if (_showOnlyMine == mine) return;
                HapticService.lightImpact();
                setState(() => _showOnlyMine = mine);
              },
            ),
          ),
          Expanded(
            child: Consumer<TournamentProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  );
                }

                final history = _showOnlyMine
                    ? provider.tournamentHistory
                        .where((t) => t.participated)
                        .toList()
                    : provider.tournamentHistory;

                if (history.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _loadHistory,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      children: [
                        SizedBox(height: MediaQuery.of(context).size.height * 0.18),
                        DsCard(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.history_rounded,
                                size: 28,
                                color: AppTheme.textTertiary,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _showOnlyMine
                                    ? l10n.noParticipatedTournaments
                                    : l10n.noTournamentHistory,
                                textAlign: TextAlign.center,
                                style: AppTheme.rowTitle,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l10n.noTournamentHistoryHint,
                                textAlign: TextAlign.center,
                                style: AppTheme.caption,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    itemCount: history.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _TournamentHistoryRow(tournament: history[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// "Tous | Les miens" scope toggle — same control as the leaderboard.
class _ScopeToggle extends StatelessWidget {
  final bool showOnlyMine;
  final ValueChanged<bool> onChanged;

  const _ScopeToggle({required this.showOnlyMine, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    Widget segment(String label, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppTheme.surfaceLight : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          segment(l10n.historyFilterAll, !showOnlyMine, () => onChanged(false)),
          segment(l10n.historyFilterMine, showOnlyMine, () => onChanged(true)),
        ],
      ),
    );
  }
}

/// One past tournament, 72 px. The medal colours are semantic (1st / 2nd /
/// 3rd); everything else stays grey, and gold appears only for a trophy the
/// user actually won.
class _TournamentHistoryRow extends StatelessWidget {
  final TournamentHistory tournament;

  const _TournamentHistoryRow({required this.tournament});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final placement = tournament.placement;
    final wonTrophy = tournament.placement == 1 &&
        tournament.hasPrize &&
        !tournament.hasCashPrize;

    return SizedBox(
      height: 72,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
        onTap: () => AppNavigator.toScreen(
          context,
          TournamentDetailScreen(tournamentId: tournament.id),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          tournament.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      if (wonTrophy) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.emoji_events_outlined,
                          size: 14,
                          color: AppTheme.accent,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _metaLine(context, l10n),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (tournament.participated && placement != null)
              Text(
                l10n.historyPlacementOrdinal(placement),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _placementColor(placement),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              )
            else
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppTheme.textTertiary,
              ),
          ],
        ),
      ),
    );
  }

  /// "4 sept. 2026 · 16 joueurs" — the date and the field size, which is the
  /// only "format" a finished tournament still carries.
  String _metaLine(BuildContext context, AppLocalizations l10n) {
    final locale = Localizations.localeOf(context).toString();
    String date;
    try {
      date = DateFormat('d MMM y', locale).format(tournament.scheduledDate.toLocal());
    } catch (_) {
      date = DateFormat('d MMM y').format(tournament.scheduledDate.toLocal());
    }
    return '$date · ${tournament.totalParticipants} ${l10n.players}';
  }

  /// Medals only: gold / silver / bronze are semantic here, every other
  /// placement reads in the quiet secondary grey.
  static Color _placementColor(int placement) {
    if (placement == 1) return AppTheme.gold;
    if (placement == 2) return AppTheme.silver;
    if (placement == 3) return AppTheme.bronze;
    return AppTheme.textSecondary;
  }
}

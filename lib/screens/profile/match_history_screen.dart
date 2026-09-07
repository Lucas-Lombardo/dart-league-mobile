import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_navigator.dart';
import '../../services/user_service.dart';
import '../../models/match.dart';
import '../../models/inactivity_penalty.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/recent_matches_widget.dart';
import '../home/stats/stats_widgets.dart';
import '../matchmaking/camera_setup_screen.dart';
import '../placement/placement_hub_screen.dart';

/// The full match history: one [MatchRowTile] per match (or per BO3 series),
/// inactivity penalties in the same timeline, a chip row to filter by kind
/// once the list mixes several.
class MatchHistoryScreen extends StatefulWidget {
  const MatchHistoryScreen({super.key});

  @override
  State<MatchHistoryScreen> createState() => _MatchHistoryScreenState();
}

/// Kinds a history can be narrowed to. Placement legs count as bot matches,
/// as they do in the Stats filter.
enum _HistoryFilter { all, ranked, friendly, tournament, bot }

class _MatchHistoryScreenState extends State<MatchHistoryScreen> {
  List<_HistoryEntry> _entries = [];
  bool _isLoading = true;
  String? _error;
  _HistoryFilter _filter = _HistoryFilter.all;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final userId = auth.currentUser?.id;

      if (userId != null) {
        final matches = await UserService.getUserMatches(userId);

        // Additive feature: an old backend has no such endpoint, so don't let
        // it break the whole history — just show matches.
        List<InactivityPenalty> penalties = [];
        try {
          penalties = await UserService.getInactivityPenalties(userId);
        } catch (_) {
          penalties = [];
        }

        final entries = <_HistoryEntry>[
          ..._collapseSeriesLegs(matches),
          ...penalties.map((p) => _HistoryEntry.penalty(p)),
        ]..sort((a, b) => b.date.compareTo(a.date));

        setState(() {
          _entries = entries;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Collapse BO3 legs (same seriesId) into ONE history entry. The newest leg
  /// is the representative: its winner IS the series winner (the series ends
  /// on the deciding leg) and it carries the series ELO deltas (intermediate
  /// legs are stamped 0). Legs won are counted across the group so the row
  /// shows "2 – 1" instead of a 501 remainder.
  List<_HistoryEntry> _collapseSeriesLegs(List<Match> matches) {
    final entries = <_HistoryEntry>[];
    final bySeries = <String, List<Match>>{};
    for (final match in matches) {
      final seriesId = match.seriesId;
      if (seriesId == null) {
        entries.add(_HistoryEntry.match(match));
      } else {
        bySeries.putIfAbsent(seriesId, () => []).add(match);
      }
    }
    for (final legs in bySeries.values) {
      legs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final newest = legs.first;
      // Prefer the SERVER's tally (attached to each leg row): counting leg
      // rows shows an abandoned 2-1 series as "1 - 1" (the credited legs were
      // never played) and undercounts when old legs fall past the page limit.
      // Fall back to counting for older backends without the fields.
      final p1Legs = newest.seriesPlayer1LegsWon ??
          legs.where((m) => m.winnerId.isNotEmpty && m.winnerId == m.player1Id).length;
      final p2Legs = newest.seriesPlayer2LegsWon ??
          legs.where((m) => m.winnerId.isNotEmpty && m.winnerId == m.player2Id).length;
      entries.add(_HistoryEntry.series(newest, p1Legs, p2Legs));
    }
    return entries;
  }

  static _HistoryFilter _kindOf(Match match) => switch (match.matchType) {
        'friendly' => _HistoryFilter.friendly,
        'tournament' => _HistoryFilter.tournament,
        'bot' || 'placement' => _HistoryFilter.bot,
        _ => _HistoryFilter.ranked,
      };

  /// "Tous" plus every kind the list actually contains, in a fixed order.
  List<_HistoryFilter> get _availableFilters {
    final present = _entries
        .where((e) => e.match != null)
        .map((e) => _kindOf(e.match!))
        .toSet();
    return [
      _HistoryFilter.all,
      for (final f in _HistoryFilter.values)
        if (f != _HistoryFilter.all && present.contains(f)) f,
    ];
  }

  /// Penalties are an ELO event: they belong to the ranked timeline.
  bool _matchesFilter(_HistoryEntry entry) {
    if (_filter == _HistoryFilter.all) return true;
    if (entry.penalty != null) return _filter == _HistoryFilter.ranked;
    return _kindOf(entry.match!) == _filter;
  }

  String _filterLabel(AppLocalizations l10n, _HistoryFilter filter) => switch (filter) {
        _HistoryFilter.all => l10n.historyFilterAll,
        _HistoryFilter.ranked => l10n.statsModeRanked,
        _HistoryFilter.friendly => l10n.statsModeFriendly,
        _HistoryFilter.tournament => l10n.statsModeTournament,
        _HistoryFilter.bot => l10n.statsModeBot,
      };

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final userId = auth.currentUser?.id ?? '';
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.matchHistoryTitle)),
      body: _buildBody(l10n, userId),
    );
  }

  Widget _buildBody(AppLocalizations l10n, String userId) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: _MessageCard(
          icon: Icons.error_outline_rounded,
          title: l10n.errorWithMessage.replaceAll('{message}', _error ?? ''),
          action: ElevatedButton(onPressed: _loadMatches, child: Text(l10n.retry)),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: _MessageCard(
          icon: Icons.history_rounded,
          title: l10n.noMatchesYet,
          subtitle: l10n.playGameToSeeHistory,
        ),
      );
    }

    final filters = _availableFilters;
    // A single kind needs no chips; "Tous" alone would be a button that does
    // nothing.
    final showChips = filters.length > 2;
    final visible = _entries.where(_matchesFilter).toList();

    return RefreshIndicator(
      onRefresh: _loadMatches,
      color: AppTheme.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        itemCount: visible.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            if (!showChips) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _FilterRow(
                labels: [for (final f in filters) _filterLabel(l10n, f)],
                index: filters.indexOf(_filter),
                onChanged: (i) => setState(() => _filter = filters[i]),
              ),
            );
          }
          final entry = visible[index - 1];
          return Padding(
            padding: EdgeInsets.only(bottom: index == visible.length ? 0 : 10),
            child: entry.penalty != null
                ? _PenaltyRow(penalty: entry.penalty!)
                : _buildMatchRow(entry, userId),
          );
        },
      ),
    );
  }

  Widget _buildMatchRow(_HistoryEntry entry, String userId) {
    final match = entry.match!;
    return MatchRowTile(
      match: match,
      userId: userId,
      seriesP1Legs: entry.seriesP1Legs,
      seriesP2Legs: entry.seriesP2Legs,
      // A finished match opens its detail (the tile's default); one still in
      // progress takes the player back into it.
      onTap: match.isInProgress ? () => _rejoinMatch(match, userId) : null,
    );
  }

  void _rejoinMatch(Match match, String userId) {
    if (match.isPlacement) {
      AppNavigator.toScreen(context, const PlacementHubScreen());
      return;
    }
    final opponentId = match.getOpponentId(userId);
    final opponentUsername = match.getOpponentUsername(userId);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CameraSetupScreen(
          rejoinMatchId: match.id,
          rejoinOpponentId: opponentId,
          rejoinOpponentUsername: opponentUsername,
        ),
      ),
    ).then((_) => _loadMatches());
  }
}

/// Horizontal row of quiet filter chips (the Stats tab's chip), 8 px apart.
class _FilterRow extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  const _FilterRow({required this.labels, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            StatsChip(
              label: labels[i],
              selected: i == index,
              onTap: () {
                if (i != index) onChanged(i);
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// An inactivity penalty in the timeline: same 60 px row as a match, an
/// hourglass square in place of the result and the ELO taken on the right.
class _PenaltyRow extends StatelessWidget {
  final InactivityPenalty penalty;

  const _PenaltyRow({required this.penalty});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 60,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.hourglass_empty_rounded, size: 18, color: AppTheme.error),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.inactivityPenaltyTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.rowTitle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${l10n.inactivityPenaltyDescription} · '
                    '${MatchRowTile.relativeDate(context, penalty.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '-${penalty.amount}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppTheme.error,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty / error state: a card with a quiet icon, a title, an optional line
/// and an optional action.
class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const _MessageCard({required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppTheme.textTertiary),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: AppTheme.rowTitle),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, textAlign: TextAlign.center, style: AppTheme.caption),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

/// A single row in the merged history timeline: either a [Match] or an
/// [InactivityPenalty]. `date` is the sort key shared by both.
class _HistoryEntry {
  final DateTime date;
  final Match? match;
  final InactivityPenalty? penalty;
  // Set for a collapsed BO3 series entry: legs won by player1/player2 of the
  // representative (newest) leg. Null for classic matches and penalties.
  final int? seriesP1Legs;
  final int? seriesP2Legs;

  _HistoryEntry.match(Match m)
      : match = m,
        penalty = null,
        seriesP1Legs = null,
        seriesP2Legs = null,
        date = m.createdAt;

  _HistoryEntry.series(Match newestLeg, this.seriesP1Legs, this.seriesP2Legs)
      : match = newestLeg,
        penalty = null,
        date = newestLeg.createdAt;

  _HistoryEntry.penalty(InactivityPenalty p)
      : match = null,
        penalty = p,
        seriesP1Legs = null,
        seriesP2Legs = null,
        date = p.createdAt;
}

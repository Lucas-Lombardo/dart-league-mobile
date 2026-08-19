import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/head_to_head.dart';
import '../../services/stats_service.dart';
import '../../utils/app_theme.dart';
import '../home/stats/stats_widgets.dart';

/// Everything two players have done to each other.
///
/// The record counts ENCOUNTERS — a ranked best-of-3 is one meeting, not three
/// — while the dart figures are drawn from every leg those meetings contained.
/// The two numbers differ, so both are labelled rather than blended into one
/// count that would be wrong for one of them.
class HeadToHeadScreen extends StatefulWidget {
  final String opponentId;
  final String opponentUsername;

  const HeadToHeadScreen({
    super.key,
    required this.opponentId,
    required this.opponentUsername,
  });

  @override
  State<HeadToHeadScreen> createState() => _HeadToHeadScreenState();
}

class _HeadToHeadScreenState extends State<HeadToHeadScreen> {
  bool _loading = true;
  String? _error;
  HeadToHead? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    setState(() {
      if (showSpinner) _loading = true;
      _error = null;
    });
    try {
      final data = await StatsService.getHeadToHead(widget.opponentId);
      if (!mounted) return;
      setState(() {
        _data = data;
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
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.headToHeadTitle),
        backgroundColor: AppTheme.surface,
      ),
      body: _buildBody(l10n),
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

    final data = _data;
    if (data == null) return const SizedBox.shrink();

    return RefreshIndicator(
      onRefresh: () => _load(showSpinner: false),
      color: AppTheme.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          _Versus(username: widget.opponentUsername, data: data),
          const SizedBox(height: 12),
          if (!data.hasHistory)
            StatsBlockEmpty(l10n.headToHeadNoHistory)
          else ...[
            _RecordCard(data: data),
            if (data.legs > 0) ...[
              const SizedBox(height: 12),
              _DuelCard(data: data),
            ],
            if (data.recent.isNotEmpty) ...[
              const SizedBox(height: 12),
              _RecentCard(data: data),
            ],
          ],
        ],
      ),
    );
  }
}

class _Versus extends StatelessWidget {
  final String username;
  final HeadToHead data;

  const _Versus({required this.username, required this.data});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Side(
            initial: 'V',
            name: AppLocalizations.of(context).you,
            color: AppTheme.playerBlue,
            bright: AppTheme.playerBlueBright,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 22),
          child: Text(
            'VS',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: _Side(
            initial: username.isNotEmpty ? username[0].toUpperCase() : '?',
            name: username,
            elo: data.opponent.elo,
            color: AppTheme.opponentPink,
            bright: AppTheme.opponentPinkBright,
          ),
        ),
      ],
    );
  }
}

class _Side extends StatelessWidget {
  final String initial;
  final String name;
  final int? elo;
  final Color color;
  final Color bright;

  const _Side({
    required this.initial,
    required this.name,
    required this.color,
    required this.bright,
    this.elo,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color, width: 2.5),
          ),
          child: Text(
            initial,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: bright),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        if (elo != null)
          Text(
            '$elo ELO',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
      ],
    );
  }
}

class _RecordCard extends StatelessWidget {
  final HeadToHead data;

  const _RecordCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final record = data.record;
    final total = record.wins + record.losses;
    final lastDecided = data.recent.where((e) => e.won != null).firstOrNull;

    return StatsCard(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${record.wins}',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                color: AppTheme.playerBlueBright,
                letterSpacing: -1,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Text('–', style: TextStyle(fontSize: 20, color: Color(0xFF64748B))),
            ),
            Text(
              '${record.losses}',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                color: AppTheme.opponentPinkBright,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Center(
          child: Text(
            '${record.encounters} ${l10n.headToHeadEncounters}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
        ),
        if (total > 0) ...[
          const SizedBox(height: 12),
          _SplitBar(wins: record.wins, losses: record.losses),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            for (final mode in data.byMode) ...[
              if (mode != data.byMode.first) _divider(),
              Expanded(
                child: _Tally(
                  label: _modeLabel(l10n, mode.mode),
                  value: '${mode.wins} – ${mode.losses}',
                ),
              ),
            ],
            if (lastDecided != null) ...[
              if (data.byMode.isNotEmpty) _divider(),
              Expanded(
                child: _Tally(
                  label: l10n.headToHeadLastResult,
                  value: lastDecided.won == true ? l10n.victory : l10n.defeat,
                  color: lastDecided.won == true ? AppTheme.success : AppTheme.error,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _divider() => Container(width: 1, height: 30, color: AppTheme.surfaceLight);
}

String _modeLabel(AppLocalizations l10n, String mode) => switch (mode) {
  'ranked' => l10n.statsModeRanked,
  'friendly' => l10n.statsModeFriendly,
  'tournament' => l10n.statsModeTournament,
  _ => mode,
};

/// Wins against defeats as one bar. A 2px gap keeps the two blocks legible
/// where the split is lopsided.
class _SplitBar extends StatelessWidget {
  final int wins;
  final int losses;

  const _SplitBar({required this.wins, required this.losses});

  @override
  Widget build(BuildContext context) {
    final total = wins + losses;
    if (total == 0) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            if (wins > 0) Expanded(flex: wins, child: Container(color: AppTheme.playerBlue)),
            if (wins > 0 && losses > 0)
              Container(width: 2, color: AppTheme.surface),
            if (losses > 0)
              Expanded(flex: losses, child: Container(color: AppTheme.opponentPink)),
          ],
        ),
      ),
    );
  }
}

class _Tally extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _Tally({required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color ?? Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

/// The dart figures, side by side. Blue is always the player and pink always
/// the opponent — the same identity the in-match screens use.
class _DuelCard extends StatelessWidget {
  final HeadToHead data;

  const _DuelCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final me = data.me;
    final them = data.them;

    return StatsCard(
      label: l10n.headToHeadInTheirMatches,
      children: [
        _DuelRow(
          label: l10n.avgThreeDart,
          mine: me.average,
          theirs: them.average,
        ),
        _DuelRow(
          label: l10n.headToHeadTons,
          mine: me.tons.toDouble(),
          theirs: them.tons.toDouble(),
          decimals: 0,
        ),
        _DuelRow(
          label: l10n.count180s,
          mine: me.count180.toDouble(),
          theirs: them.count180.toDouble(),
          decimals: 0,
        ),
        _DuelRow(
          label: l10n.statsCheckout,
          mine: me.checkoutPct,
          theirs: them.checkoutPct,
          suffix: ' %',
        ),
        _DuelRow(
          label: l10n.bestCheckout,
          mine: me.bestCheckout?.toDouble(),
          theirs: them.bestCheckout?.toDouble(),
          decimals: 0,
          highlightBest: true,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.headToHeadLegsBasis(data.legs),
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
        ),
      ],
    );
  }
}

class _DuelRow extends StatelessWidget {
  final String label;
  final double? mine;
  final double? theirs;
  final int decimals;
  final String suffix;

  /// Paints the leading value gold rather than blue — used for records, where
  /// "best" reads better than "mine".
  final bool highlightBest;

  const _DuelRow({
    required this.label,
    required this.mine,
    required this.theirs,
    this.decimals = 1,
    this.suffix = '',
    this.highlightBest = false,
  });

  String _format(double? value) {
    if (value == null) return '—';
    final text = decimals == 0
        ? value.toStringAsFixed(0)
        : (value == value.roundToDouble()
              ? value.toStringAsFixed(0)
              : value.toStringAsFixed(1));
    return '$text$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final a = mine ?? 0;
    final b = theirs ?? 0;
    final total = a + b;
    // Both bars share the row's width in proportion to the two values, so the
    // comparison is readable without either side carrying an axis.
    final mineFlex = total > 0 ? (a / total * 1000).round() : 500;
    final theirsFlex = total > 0 ? (b / total * 1000).round() : 500;
    final mineLeads = mine != null && (theirs == null || a > b);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Text(
              _format(mine),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: highlightBest && mineLeads
                    ? AppTheme.gold
                    : AppTheme.playerBlueBright,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              children: [
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        Expanded(
                          flex: mineFlex.clamp(1, 1000),
                          child: Container(color: AppTheme.playerBlue),
                        ),
                        Container(width: 2, color: AppTheme.surface),
                        Expanded(
                          flex: theirsFlex.clamp(1, 1000),
                          child: Container(color: AppTheme.opponentPink),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 54,
            child: Text(
              _format(theirs),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: highlightBest && !mineLeads && theirs != null
                    ? AppTheme.gold
                    : AppTheme.opponentPinkBright,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  final HeadToHead data;

  const _RecentCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StatsCard(
      label: l10n.headToHeadRecentMeetings,
      children: [
        for (var i = 0; i < data.recent.length; i++) ...[
          if (i > 0) const Divider(height: 16, color: AppTheme.surfaceLight),
          _EncounterRow(encounter: data.recent[i]),
        ],
      ],
    );
  }
}

class _EncounterRow extends StatelessWidget {
  final HeadToHeadEncounter encounter;

  const _EncounterRow({required this.encounter});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final won = encounter.won;
    final color = won == null
        ? AppTheme.textSecondary
        : (won ? AppTheme.success : AppTheme.error);

    final title = <String>[
      _modeLabel(l10n, encounter.mode),
      if (encounter.myLegs != null && encounter.theirLegs != null)
        '${encounter.myLegs} – ${encounter.theirLegs}',
    ].join(' · ');

    final averages = encounter.myAverage != null && encounter.theirAverage != null
        ? '${l10n.avgThreeDart} ${_one(encounter.myAverage!)} · ${_one(encounter.theirAverage!)}'
        : null;
    final subtitle = [
      if (encounter.playedAt != null) _formatDate(encounter.playedAt!),
      ?averages,
    ].join(' · ');

    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Text(
            won == null ? '–' : (won ? l10n.formWinLetter : l10n.formLossLetter),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
        if (encounter.eloChange != 0)
          Text(
            encounter.eloChange > 0 ? '+${encounter.eloChange}' : '${encounter.eloChange}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: encounter.eloChange > 0 ? AppTheme.success : AppTheme.error,
            ),
          ),
      ],
    );
  }

  String _one(double value) =>
      value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

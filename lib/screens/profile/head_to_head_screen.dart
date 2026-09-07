import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/head_to_head.dart';
import '../../models/match.dart';
import '../../services/stats_service.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/premium_badge.dart';
import '../../widgets/recent_matches_widget.dart';
import '../home/stats/stats_widgets.dart';
import 'match_detail_screen.dart';

/// Everything two players have done to each other.
///
/// The record counts ENCOUNTERS — a ranked best-of-3 is one meeting, not three
/// — while the dart figures are drawn from every leg those meetings contained.
/// The two numbers differ, so both are labelled rather than blended into one
/// count that would be wrong for one of them.
///
/// Blue is always me and rose always the opponent, the identity the in-match
/// screens and the match detail already use.
class HeadToHeadScreen extends StatefulWidget {
  final String opponentId;
  final String opponentUsername;

  /// Data to render without fetching — previews and tests only; the app
  /// always leaves this null and lets the screen load itself.
  final HeadToHead? initialData;

  const HeadToHeadScreen({
    super.key,
    required this.opponentId,
    required this.opponentUsername,
    this.initialData,
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
    if (widget.initialData != null) {
      _data = widget.initialData;
      _loading = false;
      return;
    }
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
      appBar: AppBar(title: Text(l10n.headToHeadTitle)),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: _MessageCard(
          icon: Icons.error_outline_rounded,
          title: _error!,
          action: OutlinedButton(onPressed: _load, child: Text(l10n.retry)),
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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          _RecordCard(username: widget.opponentUsername, data: data),
          if (!data.hasHistory) ...[
            const SizedBox(height: 14),
            _MessageCard(
              icon: Icons.compare_arrows_rounded,
              title: l10n.headToHeadNoHistory,
            ),
          ] else ...[
            if (data.legs > 0) ...[
              const SizedBox(height: 28),
              DsSectionHeader(title: l10n.headToHeadInTheirMatches),
              const SizedBox(height: 12),
              _DuelCard(data: data),
            ],
            if (data.recent.isNotEmpty) ...[
              const SizedBox(height: 28),
              DsSectionHeader(title: l10n.headToHeadRecentMeetings),
              const SizedBox(height: 12),
              for (var i = 0; i < data.recent.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                _EncounterRow(
                  encounter: data.recent[i],
                  opponentUsername: widget.opponentUsername,
                  opponentIsPremium: data.opponent.isPremium,
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

String _format(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

String _modeLabel(AppLocalizations l10n, String mode) => switch (mode) {
      'ranked' => l10n.statsModeRanked,
      'friendly' => l10n.statsModeFriendly,
      'tournament' => l10n.statsModeTournament,
      _ => mode,
    };

/// The versus block AND the record in one card: me (blue) against them (rose)
/// around the tally, the encounters line, the split bar, and the breakdown by
/// mode with the last result.
class _RecordCard extends StatelessWidget {
  final String username;
  final HeadToHead data;

  const _RecordCard({required this.username, required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final record = data.record;
    final total = record.wins + record.losses;
    final lastDecided = data.recent.where((e) => e.won != null).firstOrNull;
    final hasBreakdown = data.byMode.isNotEmpty || lastDecided != null;
    final elo = data.opponent.elo;

    const scoreStyle = TextStyle(
      fontSize: 34,
      fontWeight: FontWeight.w800,
      height: 1,
      letterSpacing: -0.7,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    return StatsCard(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: _Identity(
                name: l10n.youLabel,
                isPremium: false,
                color: AppTheme.playerBlueBright,
                alignEnd: false,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text.rich(
                TextSpan(
                  style: scoreStyle,
                  children: [
                    TextSpan(
                      text: '${record.wins}',
                      style: const TextStyle(color: AppTheme.playerBlueBright),
                    ),
                    const TextSpan(
                      text: ' – ',
                      style: TextStyle(color: AppTheme.textTertiary),
                    ),
                    TextSpan(
                      text: '${record.losses}',
                      style: const TextStyle(color: AppTheme.opponentPinkBright),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _Identity(
                name: username,
                isPremium: data.opponent.isPremium,
                color: AppTheme.opponentPinkBright,
                alignEnd: true,
                subline: elo > 0 ? '$elo ${l10n.eloLabel}' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '${record.encounters} ${l10n.headToHeadEncounters.toLowerCase()}',
            style: AppTheme.caption,
          ),
        ),
        if (total > 0) ...[
          const SizedBox(height: 12),
          _TwoToneBar(
            mine: record.wins.toDouble(),
            theirs: record.losses.toDouble(),
          ),
        ],
        if (hasBreakdown) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              for (final mode in data.byMode) ...[
                if (mode != data.byMode.first) const _TallyDivider(),
                Expanded(
                  child: _Tally(
                    label: _modeLabel(l10n, mode.mode),
                    value: '${mode.wins} – ${mode.losses}',
                  ),
                ),
              ],
              if (lastDecided != null) ...[
                if (data.byMode.isNotEmpty) const _TallyDivider(),
                Expanded(
                  child: _Tally(
                    label: dsSentence(l10n.headToHeadLastResult),
                    value: lastDecided.won == true ? l10n.victory : l10n.defeat,
                    color: lastDecided.won == true ? AppTheme.success : AppTheme.error,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// One side of the versus row: the name in its identity colour, the premium
/// crown after it, and an optional quiet line under it.
class _Identity extends StatelessWidget {
  final String name;
  final bool isPremium;
  final Color color;
  final bool alignEnd;
  final String? subline;

  const _Identity({
    required this.name,
    required this.isPremium,
    required this.color,
    required this.alignEnd,
    this.subline,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: alignEnd ? TextAlign.end : TextAlign.start,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
              ),
            ),
            PremiumBadge(isPremium: isPremium, size: 12, color: AppTheme.accent),
          ],
        ),
        if (subline != null) ...[
          const SizedBox(height: 3),
          Text(
            subline!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption,
          ),
        ],
      ],
    );
  }
}

/// The 4 px two-tone bar of the system: mine on the left in dim blue, theirs
/// on the right in rose, split in proportion with a 2 px gap between them.
class _TwoToneBar extends StatelessWidget {
  final double mine;
  final double theirs;

  const _TwoToneBar({required this.mine, required this.theirs});

  @override
  Widget build(BuildContext context) {
    final total = mine + theirs;
    final mineFlex = total > 0 ? (mine / total * 1000).round() : 500;
    final theirsFlex = total > 0 ? (theirs / total * 1000).round() : 500;
    return SizedBox(
      height: 4,
      child: Row(
        children: [
          Expanded(
            flex: mineFlex.clamp(1, 1000),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.playerBlueDim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            flex: theirsFlex.clamp(1, 1000),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.opponentPink.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TallyDivider extends StatelessWidget {
  const _TallyDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: AppTheme.border);
}

/// "Classé" over "3 – 1": a quiet caption label and the figure under it.
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
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.caption,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color ?? AppTheme.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// The dart figures side by side, in the vocabulary of the match stats card:
/// my value on the left, the label in the middle, theirs on the right, over a
/// bar split in proportion.
class _DuelCard extends StatelessWidget {
  final HeadToHead data;

  const _DuelCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final me = data.me;
    final them = data.them;

    return StatsCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      children: [
        Row(
          children: [
            _Legend(label: l10n.youLabel, color: AppTheme.playerBlueDim),
            const SizedBox(width: 14),
            Flexible(
              child: _Legend(
                label: data.opponent.username.isEmpty ? '—' : data.opponent.username,
                color: AppTheme.opponentPink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _DuelRow(label: l10n.avgThreeDart, mine: me.average, theirs: them.average),
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
          showBars: false,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.headToHeadLegsBasis(data.legs),
          style: AppTheme.caption.copyWith(color: AppTheme.textTertiary),
        ),
      ],
    );
  }
}

/// "● Vous" / "● DODO180": 7 px identity dot + 11 / 600 secondary label.
class _Legend extends StatelessWidget {
  final String label;
  final Color color;

  const _Legend({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
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
  final bool showBars;

  const _DuelRow({
    required this.label,
    required this.mine,
    required this.theirs,
    this.decimals = 1,
    this.suffix = '',
    this.showBars = true,
  });

  String _value(double? value) {
    if (value == null) return '—';
    final text = decimals == 0 ? value.toStringAsFixed(0) : _format(value);
    return '$text$suffix';
  }

  Widget _side({required bool mine}) {
    final value = mine ? this.mine : theirs;
    return SizedBox(
      width: 70,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
        child: Text(
          _value(value),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: mine ? AppTheme.playerBlueBright : AppTheme.opponentPinkBright,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _side(mine: true),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              _side(mine: false),
            ],
          ),
          if (showBars) ...[
            const SizedBox(height: 6),
            _TwoToneBar(mine: mine ?? 0, theirs: theirs ?? 0),
          ],
        ],
      ),
    );
  }
}

/// One meeting of the list. A decided encounter with a known leg score is the
/// app's standard match row ([MatchRowTile]) — same square, same "Classé ·
/// date" line, same ELO delta, and the same tap into the match detail. What
/// the head-to-head payload cannot fill (an abandoned meeting, an old row
/// without legs) falls back to the quiet list row rather than inventing a
/// score.
class _EncounterRow extends StatelessWidget {
  final HeadToHeadEncounter encounter;
  final String opponentUsername;
  final bool opponentIsPremium;

  const _EncounterRow({
    required this.encounter,
    required this.opponentUsername,
    required this.opponentIsPremium,
  });

  /// Ids local to the row: [MatchRowTile] only ever compares them to the
  /// userId it is handed, and the head-to-head payload has no player ids.
  static const _meId = 'me';
  static const _themId = 'them';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final won = encounter.won;
    final myLegs = encounter.myLegs;
    final theirLegs = encounter.theirLegs;

    if (won != null && myLegs != null && theirLegs != null) {
      return MatchRowTile(
        userId: _meId,
        match: Match(
          id: encounter.matchId,
          player1Id: _meId,
          player2Id: _themId,
          player1Username: l10n.youLabel,
          player2Username: opponentUsername,
          player2IsPremium: opponentIsPremium,
          player1Score: myLegs,
          player2Score: theirLegs,
          winnerId: won ? _meId : _themId,
          player1EloChange: encounter.eloChange,
          player2EloChange: -encounter.eloChange,
          createdAt: encounter.playedAt ?? DateTime.now(),
          status: 'completed',
          matchType: encounter.mode,
        ),
      );
    }

    return DsListRow(
      leading: won == null
          ? Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.textTertiary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Text(
                '–',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textTertiary,
                  height: 1,
                ),
              ),
            )
          : DsResultSquare(
              won: won,
              letter: won ? l10n.formWinLetter : l10n.formLossLetter,
            ),
      title: _modeLabel(l10n, encounter.mode),
      subtitle: encounter.playedAt == null
          ? null
          : MatchRowTile.relativeDate(context, encounter.playedAt!),
      // No chevron: these rows sit next to [MatchRowTile] ones, which carry
      // the ELO delta or nothing at all.
      trailing: encounter.eloChange == 0
          ? const SizedBox.shrink()
          : Text(
              '${encounter.eloChange > 0 ? '+' : ''}${encounter.eloChange}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: encounter.eloChange > 0 ? AppTheme.success : AppTheme.error,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
      onTap: () => AppNavigator.toScreen(
        context,
        MatchDetailScreen(matchId: encounter.matchId),
      ),
    );
  }
}

/// Empty / error state: a card with a quiet icon, a title and an optional
/// action.
class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? action;

  const _MessageCard({required this.icon, required this.title, this.action});

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppTheme.textTertiary),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: AppTheme.rowTitle),
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

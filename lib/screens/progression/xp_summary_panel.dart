import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../providers/progression_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/progression/progression_widgets.dart';
import '../league/league_models.dart';
import '../league/league_store.dart';
import 'progression_format.dart';

/// "XP earned" block of the end-of-match screen (mockup FinDeMatchXP): the
/// XP lines since [since], the level bar, and "Level 15 reached · Brass frame
/// unlocked". XP is awarded asynchronously, so the provider retries until
/// [expectRefId] (the series id) shows up. Under the card, the league line
/// (« Ligue Acier : +50 pts, tu passes de 6ᵉ à 4ᵉ. ») when this match earned
/// league points. Static — nothing animates.
class XpSummaryPanel extends StatefulWidget {
  final DateTime since;
  final String? expectRefId;

  /// Test hook: replaces GET /league/match-delta.
  final Future<LeagueMatchDelta?> Function(DateTime since)? loadLeague;

  const XpSummaryPanel({super.key, required this.since, this.expectRefId, this.loadLeague});

  @override
  State<XpSummaryPanel> createState() => _XpSummaryPanelState();
}

class _XpSummaryPanelState extends State<XpSummaryPanel> {
  XpFeed? _feed;
  bool _loading = true;
  LeagueMatchDelta? _league;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    ProgressionProvider? provider;
    try {
      provider = context.read<ProgressionProvider>();
    } on ProviderNotFoundException {
      provider = null;
    }
    if (provider != null) {
      final feed = await provider.waitForXp(widget.since, expectRefId: widget.expectRefId);
      if (!mounted) return;
      setState(() {
        _feed = feed;
        _loading = false;
      });
    }
    await _loadLeague();
  }

  /// Once the XP is in (the league points come from the same event), then
  /// once more 2 s later if they were not counted yet. Never throws: no line
  /// on an older server or without a group this week.
  Future<void> _loadLeague() async {
    final load = widget.loadLeague ?? LeagueApi.getMatchDelta;
    for (final wait in const [Duration.zero, Duration(seconds: 2)]) {
      if (wait > Duration.zero) await Future<void>.delayed(wait);
      if (!mounted) return;
      LeagueMatchDelta? delta;
      try {
        delta = await load(widget.since);
      } catch (e) {
        debugPrint('XpSummaryPanel league line: $e');
        return;
      }
      if (!mounted) return;
      if (delta != null) {
        setState(() => _league = delta);
        return;
      }
    }
  }

  /// « Ligue Acier : +50 pts, tu passes de 6ᵉ à 4ᵉ. »
  static String leagueLine(AppLocalizations l10n, BuildContext context, LeagueMatchDelta d) {
    final league = l10n.leagueName(d.league.name.resolve(context));
    return d.moved
        ? l10n.leagueMatchMoved(league, d.points, l10n.leaguePlace(d.positionBefore), l10n.leaguePlace(d.positionAfter))
        : l10n.leagueMatchStayed(league, d.points, l10n.leaguePlace(d.positionAfter));
  }

  Widget _withLeague(BuildContext context, Widget card) {
    final d = _league;
    if (d == null) return card;
    final line = Text(
      leagueLine(AppLocalizations.of(context), context, d),
      style: AppTheme.caption.copyWith(fontSize: 13),
    );
    if (card is SizedBox) return line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [card, const SizedBox(height: 10), line],
    );
  }

  @override
  Widget build(BuildContext context) => _withLeague(context, _buildXp(context));

  Widget _buildXp(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final feed = _feed;
    if (feed == null || feed.entries.isEmpty) {
      if (!_loading) return const SizedBox.shrink();
      return DsCard(
        child: Row(
          children: [
            Text(l10n.xpEarnedTitle, style: AppTheme.sectionTitle),
            const Spacer(),
            Text(l10n.xpPending, style: AppTheme.caption),
          ],
        ),
      );
    }
    final p = context.watch<ProgressionProvider>();
    final s = feed.progression;
    final unlocked = feed.levelUps
        .expand((l) => [...l.itemIds, ...l.premiumItemIds])
        .map(p.item)
        .whereType<ItemDef>()
        .toList();
    return DsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.xpEarnedTitle, style: AppTheme.sectionTitle)),
              Text(
                l10n.questXp(feed.totalAmount),
                style: AppTheme.titleLarge.copyWith(color: AppTheme.primaryLight),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final e in feed.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              // A long quest name wraps on a second line, its XP stays on the first.
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      e.label.resolve(context),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.caption.copyWith(fontSize: 13, color: const Color(0xFFCBD5E1)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(l10n.questXp(e.amount), style: AppTheme.caption.copyWith(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              LevelChip(level: s.level),
              const SizedBox(width: 8),
              Expanded(child: XpProgressBar(xpIntoLevel: s.xpIntoLevel, xpToNext: s.xpToNext)),
              const SizedBox(width: 8),
              LevelChip(level: s.level + 1),
            ],
          ),
          if (feed.levelAfter > feed.levelBefore) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (unlocked.isNotEmpty) ...[
                  ProgressionItemVisual(item: unlocked.first, monogramText: s.cosmetics.monogram, size: 36),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.xpLevelReached(feed.levelAfter), style: AppTheme.rowTitle),
                      if (unlocked.isNotEmpty)
                        Text(
                          l10n.xpItemUnlocked(itemKindAndName(context, unlocked.first)),
                          style: AppTheme.caption,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/match_stats.dart';
import '../services/stats_service.dart';
import '../utils/app_theme.dart';

/// The stats of the match that just ended, on the end-of-match screen.
///
/// Loads itself from the match id rather than being handed figures by the game
/// screens: the server has already replayed these darts (the match detail
/// screen has shown the same numbers for months), and re-deriving them on the
/// client is how the two ended up disagreeing everywhere else.
///
/// It renders NOTHING until it has real figures — no spinner, no skeleton. The
/// screen underneath it carries the actions a player needs (confirm the result,
/// report the opponent) and those must never be pushed down the page by a
/// placeholder that may be replaced by nothing at all.
class MatchStatsCard extends StatefulWidget {
  final String matchId;

  /// Landscape packs the same card into a narrower column.
  final bool compact;

  const MatchStatsCard({super.key, required this.matchId, this.compact = false});

  @override
  State<MatchStatsCard> createState() => _MatchStatsCardState();
}

class _MatchStatsCardState extends State<MatchStatsCard> {
  MatchStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats = await StatsService.getMatchCard(widget.matchId);
      if (!mounted || stats.isEmpty) return;
      setState(() => _stats = stats);
    } catch (_) {
      // The card is a bonus on this screen; its absence costs the player
      // nothing, while a visible error would sit between them and the
      // confirm button.
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final me = stats.me;
    final them = stats.opponent;
    final delta = stats.deltaVsWindow;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.gamePanel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.matchStatsTitle.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              _Legend(label: l10n.you, color: AppTheme.playerBlue),
              const SizedBox(width: 10),
              Flexible(
                child: _Legend(
                  label: them.username.isEmpty ? '—' : them.username,
                  color: AppTheme.opponentPink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DuelRow(
            label: l10n.avgThreeDart,
            mine: me.average,
            theirs: them.average,
          ),
          _DuelRow(
            label: l10n.statsBestVisit,
            mine: me.bestVisit > 0 ? me.bestVisit.toDouble() : null,
            theirs: them.bestVisit > 0 ? them.bestVisit.toDouble() : null,
            decimals: 0,
          ),
          if (me.doublesAttempted > 0 || them.doublesAttempted > 0)
            _DuelRow(
              label: l10n.matchStatsDoubles,
              mine: me.checkoutPct,
              theirs: them.checkoutPct,
              suffix: ' %',
              mineCaption: '${me.doublesHit}/${me.doublesAttempted}',
              theirsCaption: '${them.doublesHit}/${them.doublesAttempted}',
            ),
          if (me.bestCheckout != null || them.bestCheckout != null)
            _DuelRow(
              label: l10n.bestCheckout,
              mine: me.bestCheckout?.toDouble(),
              theirs: them.bestCheckout?.toDouble(),
              decimals: 0,
              showBars: false,
              highlightBest: true,
            ),
          if (delta != null) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: AppTheme.surfaceLight),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.matchStatsVsWindow(
                      _format(stats.windowAverage!),
                      stats.windowDays,
                    ),
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  '${delta >= 0 ? '▲' : '▼'} ${_format(delta.abs())}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: delta >= 0 ? AppTheme.success : AppTheme.error,
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

String _format(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

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
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// One figure for each side, with a bar splitting the row in proportion.
class _DuelRow extends StatelessWidget {
  final String label;
  final double? mine;
  final double? theirs;
  final int decimals;
  final String suffix;
  final String? mineCaption;
  final String? theirsCaption;
  final bool showBars;
  final bool highlightBest;

  const _DuelRow({
    required this.label,
    required this.mine,
    required this.theirs,
    this.decimals = 1,
    this.suffix = '',
    this.mineCaption,
    this.theirsCaption,
    this.showBars = true,
    this.highlightBest = false,
  });

  String _value(double? value) {
    if (value == null) return '—';
    final text = decimals == 0 ? value.toStringAsFixed(0) : _format(value);
    return '$text$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final a = mine ?? 0;
    final b = theirs ?? 0;
    final total = a + b;
    final mineFlex = total > 0 ? (a / total * 1000).round() : 500;
    final theirsFlex = total > 0 ? (b / total * 1000).round() : 500;
    final mineLeads = mine != null && (theirs == null || a > b);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    _value(mine),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: highlightBest && mineLeads
                          ? AppTheme.gold
                          : AppTheme.playerBlueBright,
                    ),
                  ),
                ),
                if (mineCaption != null)
                  Text(
                    mineCaption!,
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                  ),
              ],
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
                if (showBars) ...[
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
                          Container(width: 2, color: AppTheme.gamePanel),
                          Expanded(
                            flex: theirsFlex.clamp(1, 1000),
                            child: Container(color: AppTheme.opponentPink),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _value(theirs),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: highlightBest && !mineLeads && theirs != null
                          ? AppTheme.gold
                          : AppTheme.opponentPinkBright,
                    ),
                  ),
                ),
                if (theirsCaption != null)
                  Text(
                    theirsCaption!,
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/match_stats.dart';
import '../services/stats_service.dart';
import '../utils/app_theme.dart';
import 'design_system.dart';

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

  /// Figures to show without fetching — previews and tests only; the game
  /// screens always leave this null and let the card load itself.
  final MatchStats? initialStats;

  const MatchStatsCard({
    super.key,
    required this.matchId,
    this.compact = false,
    this.initialStats,
  });

  @override
  State<MatchStatsCard> createState() => _MatchStatsCardState();
}

class _MatchStatsCardState extends State<MatchStatsCard> {
  MatchStats? _stats;

  @override
  void initState() {
    super.initState();
    _stats = widget.initialStats;
    if (_stats == null) _load();
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

    return DsCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(l10n.matchStatsTitle, style: AppTheme.sectionTitle),
              ),
              _Legend(label: dsSentence(l10n.you), color: AppTheme.playerBlueDim),
              const SizedBox(width: 12),
              Flexible(
                child: _Legend(
                  label: them.username.isEmpty ? '—' : them.username,
                  color: AppTheme.opponentPink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
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
            ),
          if (delta != null) ...[
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.matchStatsVsWindow(
                      _format(stats.windowAverage!),
                      stats.windowDays,
                    ),
                    style: AppTheme.caption,
                  ),
                ),
                Icon(
                  delta >= 0
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  size: 14,
                  color: delta >= 0 ? AppTheme.success : AppTheme.error,
                ),
                const SizedBox(width: 3),
                Text(
                  _format(delta.abs()),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: delta >= 0 ? AppTheme.success : AppTheme.error,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

/// One figure for each side — mine on the left in bright blue, theirs on the
/// right in bright rose, the label between — over a 4 px two-tone bar split in
/// proportion.
class _DuelRow extends StatelessWidget {
  final String label;
  final double? mine;
  final double? theirs;
  final int decimals;
  final String suffix;
  final String? mineCaption;
  final String? theirsCaption;
  final bool showBars;

  const _DuelRow({
    required this.label,
    required this.mine,
    required this.theirs,
    this.decimals = 1,
    this.suffix = '',
    this.mineCaption,
    this.theirsCaption,
    this.showBars = true,
  });

  String _value(double? value) {
    if (value == null) return '—';
    final text = decimals == 0 ? value.toStringAsFixed(0) : _format(value);
    return '$text$suffix';
  }

  Widget _side({required bool mine}) {
    final value = mine ? this.mine : theirs;
    final caption = mine ? mineCaption : theirsCaption;
    return SizedBox(
      width: 70,
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
            child: Text(
              _value(value),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.1,
                color: mine
                    ? AppTheme.playerBlueBright
                    : AppTheme.opponentPinkBright,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (caption != null)
            Text(
              caption,
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = mine ?? 0;
    final b = theirs ?? 0;
    final total = a + b;
    final mineFlex = total > 0 ? (a / total * 1000).round() : 500;
    final theirsFlex = total > 0 ? (b / total * 1000).round() : 500;

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
                    style: AppTheme.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              _side(mine: false),
            ],
          ),
          if (showBars) ...[
            const SizedBox(height: 6),
            SizedBox(
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
            ),
          ],
        ],
      ),
    );
  }
}

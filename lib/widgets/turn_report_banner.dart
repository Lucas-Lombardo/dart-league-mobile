import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/turn_report_service.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import 'design_system.dart';

/// The winning-visit banner, on the two screens a losing player can land on
/// after their opponent checks out: the between-legs screen and the end-of-
/// match screen.
///
/// It exists because the loser has no other chance: the server sends
/// `game_won` and the board is gone — `confirm_win` is emitted by the WINNER,
/// so there is no confirmation step on this side to hang a button off. Without
/// this banner the single most contested visit of a match would be the only one
/// that can't be reported.
///
/// No countdown, unlike the in-game bar: nothing is being played, so there is
/// no reason to rush the decision. A second tap takes it back.
class WinningVisitBanner extends StatefulWidget {
  /// Posts the flag. Called at most once per screen.
  final VoidCallback onFlag;

  /// Points the winning visit scored, shown so the target is explicit.
  final int? volleyScore;

  /// The leg this visit won — the key the flag state is tracked under.
  final String matchId;

  const WinningVisitBanner({
    super.key,
    required this.onFlag,
    required this.matchId,
    this.volleyScore,
  });

  @override
  State<WinningVisitBanner> createState() => _WinningVisitBannerState();
}

class _WinningVisitBannerState extends State<WinningVisitBanner> {
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    // Survives a rebuild of the end screen (orientation change, leg
    // transition): the flag lives in the service, not in this widget.
    _sent = TurnReportService.winningVolleyFlagged(widget.matchId);
  }

  void _tap() {
    if (_sent) return;
    HapticService.mediumImpact();
    setState(() => _sent = true);
    widget.onFlag();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Rose-tinted card: the opponent's identity colour, as everywhere a
    // report concerns THEIR visit. The pill flips to an outline once sent.
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DsCard(
        radius: AppTheme.radiusControl,
        color: AppTheme.secondary.withValues(alpha: 0.08),
        side: BorderSide(color: AppTheme.opponentPink.withValues(alpha: 0.5)),
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        onTap: _sent ? null : _tap,
        child: Row(
          children: [
            const Icon(
              Icons.flag_outlined,
              color: AppTheme.opponentPinkBright,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                dsSentence(
                  widget.volleyScore != null
                      ? l10n.flagWinningVisit(widget.volleyScore!)
                      : l10n.turnReportWinningNoLeg,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _sent ? Colors.transparent : AppTheme.opponentPink,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _sent
                      ? AppTheme.opponentPink.withValues(alpha: 0.6)
                      : AppTheme.opponentPink,
                ),
              ),
              child: Text(
                dsSentence(_sent ? l10n.flagDone : l10n.flagAction),
                style: TextStyle(
                  color: _sent ? AppTheme.opponentPinkBright : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

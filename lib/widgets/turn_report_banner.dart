import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/turn_report_service.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';

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
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _sent ? null : _tap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.opponentPink.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.opponentPink.withValues(alpha: 0.55),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _sent ? Icons.flag : Icons.flag_outlined,
                  color: AppTheme.opponentPinkBright,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.volleyScore != null
                        ? l10n.flagWinningVisit(widget.volleyScore!)
                        : l10n.turnReportWinningNoLeg,
                    style: const TextStyle(
                      color: AppTheme.opponentPinkBright,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _sent
                        ? Colors.transparent
                        : AppTheme.opponentPink.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.opponentPinkBright.withValues(alpha: 0.7),
                    ),
                  ),
                  child: Text(
                    _sent ? '${l10n.flagDone} ✓' : l10n.flagAction,
                    style: TextStyle(
                      color: _sent
                          ? AppTheme.opponentPinkBright
                          : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

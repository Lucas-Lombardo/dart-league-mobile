import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/local_match_config.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/game_turn_ui.dart';
import '../game/match_end_view.dart';

// Chrome shared by the local (hot-seat) X01 and cricket screens: the AI
// loading placeholder, the transient turn banner, the leave confirmation and
// the end-of-match view. Purely presentational — the screens own the state.
//
// System D (2026-09): flat surfaces, hairline borders, sentence case, and the
// in-match identity convention — player 1 is blue, player 2 is rose, on every
// screen of a local match.

/// Player 1 (left / blue) or player 2 (right / rose) identity colour.
Color localPlayerColor(int player) =>
    player == 0 ? AppTheme.playerBlue : AppTheme.opponentPink;

/// The brighter variant used for text on dark surfaces.
Color localPlayerTextColor(int player) =>
    player == 0 ? AppTheme.playerBlueBright : AppTheme.opponentPinkBright;

/// Full-screen placeholder while the camera and the AI model come up.
class LocalMatchLoadingView extends StatelessWidget {
  const LocalMatchLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: AppTheme.primary,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              dsSentence(AppLocalizations.of(context).loadingAutoScoring),
              style: AppTheme.caption.copyWith(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

/// Transient "it's X's turn" pill shown top-center right after a hands-free
/// turn switch. Positioned — goes straight into the game screen's Stack.
///
/// Same glass hint pill as the camera guidance ones (background at 85 %,
/// hairline), with the thrower's identity dot and name — no gradient, no glow.
class LocalTurnBanner extends StatelessWidget {
  final String name;
  final double safeTop;

  /// 0 = player 1 (blue), 1 = player 2 (rose).
  final int player;

  const LocalTurnBanner({
    super.key,
    required this.name,
    required this.safeTop,
    this.player = 0,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Positioned(
      top: safeTop + 52,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.96 + 0.04 * t, child: child),
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.background.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: localPlayerColor(player),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    dsSentence(l10n.turnOf(name)),
                    style: TextStyle(
                      color: localPlayerTextColor(player),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Leave-match confirmation of the local screens. Resolves to true when the
/// player chose to leave. Same frame as every other in-match dialog.
Future<bool> showLeaveLocalMatchDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final shouldLeave = await showGameDialog<bool>(
    context,
    accent: AppTheme.error,
    icon: Icons.logout_rounded,
    title: l10n.leaveMatch,
    content: Text(l10n.leaveMatchWarning, style: AppTheme.bodyMedium),
    actionsBuilder: (ctx) => [
      OutlinedButton(
        onPressed: () => Navigator.pop(ctx, false),
        child: Text(dsSentence(l10n.stay)),
      ),
      ElevatedButton(
        onPressed: () => Navigator.pop(ctx, true),
        style: gameFilledButtonStyle(AppTheme.error),
        child: Text(dsSentence(l10n.leave)),
      ),
    ],
  );
  return shouldLeave ?? false;
}

/// End of a local match, on the shared [MatchEndView]: result disc, sentence-
/// case title, the two-coloured legs tile (player 1 blue – player 2 rose),
/// the optional per-player stat rows and ONE primary action (rematch) over a
/// quiet "back home" outline.
class LocalMatchEndView extends StatelessWidget {
  final LocalMatchConfig config;
  final int winner;
  final List<int> legsWon;
  final List<Widget> stats;
  final VoidCallback onRematch;
  final VoidCallback onBack;
  final String? backLabel;

  const LocalMatchEndView({
    super.key,
    required this.config,
    required this.winner,
    required this.legsWon,
    this.stats = const [],
    required this.onRematch,
    required this.onBack,
    this.backLabel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final winnerName = config.nameOf(winner);

    final panel = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: onRematch,
            icon: const Icon(Icons.replay_rounded, size: 20),
            label: Text(dsSentence(l10n.rematchButton)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            onPressed: onBack,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.textSecondary,
              textStyle: gameButtonTextStyle.copyWith(fontSize: 14),
            ),
            child: Text(backLabel ?? dsSentence(l10n.backToHome)),
          ),
        ),
      ],
    );

    return MatchEndView(
      // Hot seat: somebody in the room won, so the screen always wears the
      // winning colours; the subtitle names them.
      didWin: true,
      title: l10n.victory,
      subtitle: l10n.localMatchWinner(winnerName),
      // "2 – 1" reads player 1 (blue) – player 2 (rose), the same identity
      // the header used all match long; the caption names the two sides.
      scoreLine: '${legsWon[0]} – ${legsWon[1]}',
      scoreCaption: '${config.nameOf(0)} – ${config.nameOf(1)}',
      preCard: stats.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < stats.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    stats[i],
                  ],
                ],
              ),
            ),
      panel: panel,
    );
  }
}

/// One stat row of [LocalMatchEndView] (outlined icon · label · value): a flat
/// surface card with a hairline, the value in the owner's identity colour.
class LocalMatchStatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const LocalMatchStatRow({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return DsCard(
      radius: AppTheme.radiusRow,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.rowTitle,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

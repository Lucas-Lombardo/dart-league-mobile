import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/local_match_config.dart';
import '../../utils/app_theme.dart';

// Chrome shared by the local (hot-seat) X01 and cricket screens: the AI
// loading placeholder, the transient turn banner, the leave confirmation and
// the end-of-match view. Purely presentational — the screens own the state.

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
            const CircularProgressIndicator(color: AppTheme.primary),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context).loadingAutoScoring,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

/// Transient "it's X's turn" pill shown top-center right after a hands-free
/// turn switch. Positioned — goes straight into the game screen's Stack.
class LocalTurnBanner extends StatelessWidget {
  final String name;
  final double safeTop;

  const LocalTurnBanner({super.key, required this.name, required this.safeTop});

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
              child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.5),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sports_esports,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    l10n.turnOf(name).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
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
/// player chose to leave.
Future<bool> showLeaveLocalMatchDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final shouldLeave = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppTheme.error, width: 2),
      ),
      title: Row(children: [
        const Icon(Icons.warning, color: AppTheme.error, size: 32),
        const SizedBox(width: 12),
        Text(l10n.leaveMatch,
            style: AppTheme.titleLarge
                .copyWith(color: AppTheme.error, fontWeight: FontWeight.bold)),
      ]),
      content: Text(l10n.leaveMatchWarning,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.stay),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
          child: Text(l10n.leave),
        ),
      ],
    ),
  );
  return shouldLeave ?? false;
}

/// End of a local match: winner, legs line, optional stat rows (the cricket
/// screen adds each player's MPR), then rematch / back.
class LocalMatchEndView extends StatelessWidget {
  final LocalMatchConfig config;
  final int winner;
  final List<int> legsWon;
  final List<Widget> stats;
  final VoidCallback onRematch;
  final VoidCallback onBack;

  const LocalMatchEndView({
    super.key,
    required this.config,
    required this.winner,
    required this.legsWon,
    this.stats = const [],
    required this.onRematch,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final winnerName = config.nameOf(winner);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.success, width: 4),
                    ),
                    child: const Icon(Icons.emoji_events,
                        color: AppTheme.success, size: 80),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    '${l10n.victory.toUpperCase()}!',
                    style: AppTheme.displayLarge
                        .copyWith(color: AppTheme.success, fontSize: 44),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.localMatchWinner(winnerName),
                    style: AppTheme.bodyLarge.copyWith(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${config.nameOf(0)}  ${legsWon[0]} — ${legsWon[1]}  ${config.nameOf(1)}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  if (stats.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    for (int i = 0; i < stats.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      stats[i],
                    ],
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onRematch,
                      icon: const Icon(Icons.replay),
                      label: Text(l10n.rematchButton),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onBack,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary,
                        side: BorderSide(
                            color: AppTheme.surfaceLight.withValues(alpha: 0.8)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(l10n.backToHome),
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

/// One stat pill of [LocalMatchEndView] (icon · label · value).
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

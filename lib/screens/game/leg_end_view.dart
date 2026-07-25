import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';

/// Between-legs view shared by ranked BO3 and tournament BO3: leg result +
/// series score + a "next leg" spinner. No buttons — the server's next-leg
/// event flips the provider back to a live leg and the caller's build returns
/// the board. Leaving here would forfeit the series, exactly like leaving
/// mid-leg, hence the guarded PopScope.
class LegEndView extends StatelessWidget {
  final bool wonLeg;
  final int myLegsWon;
  final int opponentLegsWon;
  final int legsNeeded;

  /// The caller's leave-confirmation flow (BaseGameScreenState.onWillPop):
  /// return true to allow the pop — the forfeit was confirmed and handled.
  final Future<bool> Function() onAttemptPop;

  const LegEndView({
    super.key,
    required this.wonLeg,
    required this.myLegsWon,
    required this.opponentLegsWon,
    required this.legsNeeded,
    required this.onAttemptPop,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accent = wonLeg ? AppTheme.success : AppTheme.error;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await onAttemptPop() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.all(isLandscape ? 16 : 24),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 3),
                      ),
                      child: Icon(
                        wonLeg ? Icons.check_circle_outline : Icons.close,
                        color: accent,
                        size: isLandscape ? 40 : 56,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      wonLeg
                          ? l10n.legWon.toUpperCase()
                          : l10n.legLost.toUpperCase(),
                      style: AppTheme.displayLarge.copyWith(
                          color: accent, fontSize: isLandscape ? 28 : 36),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '$myLegsWon – $opponentLegsWon',
                      style: AppTheme.displayLarge.copyWith(
                          color: Colors.white,
                          fontSize: isLandscape ? 32 : 44),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.firstToNLegs(legsNeeded),
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    const CircularProgressIndicator(color: AppTheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      l10n.nextLeg,
                      style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                          letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

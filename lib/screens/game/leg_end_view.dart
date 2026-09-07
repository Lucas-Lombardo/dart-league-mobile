import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/game_turn_ui.dart';

/// Between-legs view shared by ranked BO3 and tournament BO3: leg result +
/// series score + a "next leg" spinner. No buttons — the server's next-leg
/// event flips the provider back to a live leg and the caller's build returns
/// the board. Leaving here would forfeit the series, exactly like leaving
/// mid-leg, hence the guarded PopScope.
///
/// Flat background, one column: a tinted result disc, the sentence-case
/// title, the two-coloured legs score, the "first to N" caption and the
/// countdown under a small primary spinner.
class LegEndView extends StatelessWidget {
  final bool wonLeg;
  final int myLegsWon;
  final int opponentLegsWon;
  final int legsNeeded;

  /// The caller's leave-confirmation flow (BaseGameScreenState.onWillPop):
  /// return true to allow the pop — the forfeit was confirmed and handled.
  final Future<bool> Function() onAttemptPop;

  /// Optional banner pinned above the result — the "report their winning
  /// visit" offer, shown to the player who just lost the leg. This screen and
  /// the end-of-match one are the only two places the loser lands after a
  /// checkout, so they are the only two places that visit can be reported.
  final Widget? banner;

  /// Seconds still owed to this screen before the next leg may replace it
  /// (see BaseGameScreenState.legEndMinDwell). 0 means the next leg is simply
  /// not ready yet — the spinner keeps its open-ended "next leg" wording.
  final int secondsLeft;

  const LegEndView({
    super.key,
    required this.wonLeg,
    required this.myLegsWon,
    required this.opponentLegsWon,
    required this.legsNeeded,
    required this.onAttemptPop,
    this.banner,
    this.secondsLeft = 0,
  });

  /// The countdown label mixes caps and a unit ("MANCHE SUIVANTE DANS 6 s"),
  /// which [dsSentence] leaves alone; this one always sentence-cases.
  static String _sentence(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final accent = wonLeg ? AppTheme.success : AppTheme.error;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final discSize = isLandscape ? 72.0 : 96.0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await onAttemptPop() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ?banner,
                  Container(
                    width: discSize,
                    height: discSize,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accent.withValues(alpha: 0.6),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      wonLeg ? Icons.check_rounded : Icons.close_rounded,
                      color: accent,
                      size: isLandscape ? 32 : 40,
                    ),
                  ),
                  SizedBox(height: isLandscape ? 18 : 26),
                  Text(
                    dsSentence(wonLeg ? l10n.legWon : l10n.legLost),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isLandscape ? 26 : 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  SizedBox(height: isLandscape ? 16 : 22),
                  SeriesLegsScore(
                    myLegs: myLegsWon,
                    opponentLegs: opponentLegsWon,
                    fontSize: isLandscape ? 40 : 48,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.firstToNLegs(legsNeeded),
                    textAlign: TextAlign.center,
                    style: AppTheme.caption.copyWith(fontSize: 13),
                  ),
                  SizedBox(height: isLandscape ? 28 : 44),
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: AppTheme.primary,
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    // Counting down while the screen is held open: without
                    // the number, a screen that stays put for six seconds
                    // reads as a freeze rather than as time being offered.
                    _sentence(
                      secondsLeft > 0
                          ? l10n.nextLegIn(secondsLeft)
                          : l10n.nextLeg,
                    ),
                    textAlign: TextAlign.center,
                    style: AppTheme.caption.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
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

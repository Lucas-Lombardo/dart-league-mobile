import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/tournament_game_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/tournament_round.dart';
import '../../widgets/design_system.dart';
import 'tournament_end_screen.dart';

/// Verdict of a tournament series, in the end-of-match vocabulary: the
/// tournament pill, an 88 px success / error disc, "Vous avancez !" or
/// "Éliminé", the round + opponent caption, the legs tile, and the single
/// primary button that continues the run (or goes home).
class TournamentMatchResultScreen extends StatelessWidget {
  final String tournamentMatchId;
  final String tournamentId;
  final String tournamentName;
  final String roundName;
  final String opponentUsername;
  final String? seriesWinnerId;
  final int myLegsWon;
  final int opponentLegsWon;
  final int bestOf;

  const TournamentMatchResultScreen({
    super.key,
    required this.tournamentMatchId,
    required this.tournamentId,
    required this.tournamentName,
    required this.roundName,
    required this.opponentUsername,
    required this.seriesWinnerId,
    required this.myLegsWon,
    required this.opponentLegsWon,
    required this.bestOf,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthProvider>();
    final myUserId = auth.currentUser?.id;
    final didWin = seriesWinnerId == myUserId;
    final accent = didWin ? AppTheme.success : AppTheme.error;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 64),
                // The verdict at the top, the single action pinned at the
                // bottom — one scroll view so short screens and large font
                // scales can never overflow.
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        DsPill(label: tournamentName),
                        const SizedBox(height: 16),
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: accent.withValues(alpha: 0.6),
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            didWin
                                ? Icons.emoji_events_outlined
                                : Icons.sentiment_dissatisfied_outlined,
                            color: accent,
                            size: 38,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          dsSentence(didWin ? l10n.youAdvance : l10n.eliminated),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.7,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${localizedRoundName(roundName, l10n)} · ${l10n.vs} $opponentUsername',
                          textAlign: TextAlign.center,
                          style: AppTheme.caption.copyWith(fontSize: 14),
                        ),
                        const SizedBox(height: 18),
                        _buildLegsTile(l10n),
                      ],
                    ),
                    Column(
                      children: [
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () => _onContinue(context, didWin),
                            child: Text(dsSentence(
                                didWin ? l10n.continueButton : l10n.returnHome)),
                          ),
                        ),
                      ],
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

  /// "2 – 1" over "AU MEILLEUR DE 3": my legs in blue, theirs in rose, the
  /// same identity colours the game screen uses.
  Widget _buildLegsTile(AppLocalizations l10n) {
    const base = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      height: 1,
      color: AppTheme.textPrimary,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return SizedBox(
      height: 64,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$myLegsWon',
                    style: base.copyWith(color: AppTheme.playerBlueBright)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    '–',
                    style: base.copyWith(
                      color: AppTheme.textTertiary,
                      fontSize: 20,
                    ),
                  ),
                ),
                Text('$opponentLegsWon',
                    style: base.copyWith(color: AppTheme.opponentPinkBright)),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '${l10n.bestOf} $bestOf'.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.labelSmall.copyWith(fontSize: 10, height: 1),
            ),
          ],
        ),
      ),
    );
  }

  void _onContinue(BuildContext context, bool didWin) {
    HapticService.mediumImpact();
    // Winners of a non-final round are QUALIFIED, not placed — the medal
    // ceremony (TournamentEndScreen) used to show them "3rd/4th place". They
    // go home and wait for the next-round invite instead.
    if (didWin && roundName != 'final') {
      final provider = context.read<TournamentGameProvider>();
      AppNavigator.toHomeClearing(context);
      try {
        provider.reset();
      } catch (_) {}
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => TournamentEndScreen(
          tournamentId: tournamentId,
          tournamentName: tournamentName,
          roundName: roundName,
          didWin: didWin,
          opponentUsername: opponentUsername,
          myLegsWon: myLegsWon,
          opponentLegsWon: opponentLegsWon,
        ),
      ),
    );
  }
}

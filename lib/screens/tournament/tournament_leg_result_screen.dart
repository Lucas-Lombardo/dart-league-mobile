import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';

class TournamentLegResultScreen extends StatelessWidget {
  final String tournamentMatchId;
  final String tournamentName;
  final String roundName;
  final String opponentUsername;
  final String? legWinnerId;
  final int myLegsWon;
  final int opponentLegsWon;
  final int legsNeeded;
  final int bestOf;
  final int currentLeg;

  const TournamentLegResultScreen({
    super.key,
    required this.tournamentMatchId,
    required this.tournamentName,
    required this.roundName,
    required this.opponentUsername,
    required this.legWinnerId,
    required this.myLegsWon,
    required this.opponentLegsWon,
    required this.legsNeeded,
    required this.bestOf,
    required this.currentLeg,
  });

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final myUserId = auth.currentUser?.id;
    final myUsername = auth.currentUser?.username ?? 'You';
    final didWinLeg = legWinnerId == myUserId;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Result icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: (didWinLeg ? AppTheme.success : AppTheme.error).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: didWinLeg ? AppTheme.success : AppTheme.error,
                    width: 3,
                  ),
                ),
                child: Icon(
                  didWinLeg ? Icons.check_circle : Icons.cancel,
                  color: didWinLeg ? AppTheme.success : AppTheme.error,
                  size: 64,
                ),
              ),
              const SizedBox(height: 24),

              Text(
                didWinLeg ? AppLocalizations.of(context).legWon : AppLocalizations.of(context).legLost,
                style: TextStyle(
                  color: didWinLeg ? AppTheme.success : AppTheme.error,
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Leg $currentLeg ${AppLocalizations.of(context).legComplete}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 40),

              // Series scoreboard
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.surfaceLight),
                ),
                child: Column(
                  children: [
                    Text(
                      tournamentName,
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${roundName.replaceAll('_', ' ').toUpperCase()} • ${AppLocalizations.of(context).bestOf} $bestOf',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildPlayerScore(myUsername, myLegsWon, true, context: context),
                        const Text(
                          '-',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 40,
                            fontWeight: FontWeight.w300,
                          ),
                        ),
                        _buildPlayerScore(opponentUsername, opponentLegsWon, false, context: context),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Leg indicators
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(bestOf, (index) {
                        Color color;
                        if (index < myLegsWon) {
                          color = AppTheme.success;
                        } else if (index < myLegsWon + opponentLegsWon) {
                          color = AppTheme.error;
                        } else {
                          color = AppTheme.surfaceLight;
                        }
                        return Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${AppLocalizations.of(context).firstToLegsWins} $legsNeeded legs',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 3),

              // Continue button — pops back to game screen, which will start the next leg
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () {
                    HapticService.mediumImpact();
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    AppLocalizations.of(context).nextLeg,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerScore(String username, int legsWon, bool isMe, {required BuildContext context}) {
    return Column(
      children: [
        Text(
          isMe ? AppLocalizations.of(context).you : username,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          '$legsWon',
          style: TextStyle(
            color: isMe ? AppTheme.primary : AppTheme.error,
            fontSize: 48,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

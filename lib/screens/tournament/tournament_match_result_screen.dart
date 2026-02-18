import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/tournament_game_provider.dart';

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
    final auth = context.read<AuthProvider>();
    final myUserId = auth.currentUser?.id;
    final myUsername = auth.currentUser?.username ?? 'You';
    final didWin = seriesWinnerId == myUserId;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const Spacer(flex: 1),

                  // Trophy / defeat icon
                  Container(
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: (didWin ? AppTheme.success : AppTheme.error).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: didWin ? AppTheme.success : AppTheme.error,
                        width: 4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (didWin ? AppTheme.success : AppTheme.error).withValues(alpha: 0.4),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Icon(
                      didWin ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                      color: didWin ? AppTheme.success : AppTheme.error,
                      size: 80,
                    ),
                  ),
                  const SizedBox(height: 32),

                  Text(
                    didWin ? 'YOU ADVANCE!' : 'ELIMINATED',
                    style: TextStyle(
                      color: didWin ? AppTheme.success : AppTheme.error,
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    didWin
                        ? 'Congratulations! You won the series.'
                        : 'Better luck next time.',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  // Match result card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: didWin ? AppTheme.success.withValues(alpha: 0.3) : AppTheme.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tournamentName,
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          roundName.replaceAll('_', ' ').toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Score
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildPlayerColumn(myUsername, myLegsWon, true, didWin),
                            Column(
                              children: [
                                const Text(
                                  'FINAL',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$myLegsWon - $opponentLegsWon',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Best of $bestOf',
                                  style: const TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            _buildPlayerColumn(opponentUsername, opponentLegsWon, false, !didWin),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Spacer(flex: 2),

                  // Return to home
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        HapticService.mediumImpact();
                        final provider = context.read<TournamentGameProvider>();
                        Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false)
                            .then((_) { try { provider.reset(); } catch (_) {} });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: didWin ? AppTheme.success : AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        didWin ? 'CONTINUE' : 'RETURN HOME',
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
        ),
      ),
    );
  }

  Widget _buildPlayerColumn(String username, int legsWon, bool isMe, bool isWinner) {
    return Column(
      children: [
        if (isWinner)
          const Icon(Icons.emoji_events, color: AppTheme.accent, size: 20)
        else
          const SizedBox(height: 20),
        const SizedBox(height: 4),
        Text(
          isMe ? 'You' : username,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

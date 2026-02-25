import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../services/socket_service.dart';
import '../../services/tournament_service.dart';
import '../../providers/tournament_game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';
import 'tournament_game_screen.dart';

class TournamentReadyScreen extends StatefulWidget {
  final String matchId;
  final String tournamentId;
  final String tournamentName;
  final String roundName;
  final String opponentUsername;
  final String opponentId;
  final String player1Id;
  final String player2Id;
  final int bestOf;

  const TournamentReadyScreen({
    super.key,
    required this.matchId,
    required this.tournamentId,
    required this.tournamentName,
    required this.roundName,
    required this.opponentUsername,
    required this.opponentId,
    required this.player1Id,
    required this.player2Id,
    required this.bestOf,
  });

  @override
  State<TournamentReadyScreen> createState() => _TournamentReadyScreenState();
}

class _TournamentReadyScreenState extends State<TournamentReadyScreen>
    with SingleTickerProviderStateMixin {
  bool _myReady = false;
  bool _opponentReady = false;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _setupListeners();
  }

  Future<void> _setupListeners() async {
    await SocketService.ensureConnected();
    if (!mounted) return;

    // Listen for ready status updates
    SocketService.on('matchReadyUpdate', (data) {
      if (data['matchId'] != widget.matchId) return;
      final p1Ready = data['player1Ready'] as bool? ?? false;
      final p2Ready = data['player2Ready'] as bool? ?? false;

      setState(() {
        final user = context.read<AuthProvider>().currentUser;
        if (user?.id == widget.player1Id) {
          _myReady = p1Ready;
          _opponentReady = p2Ready;
        } else {
          _myReady = p2Ready;
          _opponentReady = p1Ready;
        }
      });
    });

    // Listen for match start (both ready, backend created the game)
    SocketService.on('tournamentMatchStart', (data) {
      if (data['matchId'] != widget.matchId) return;
      final gameMatchId = data['gameMatchId'] as String?;
      if (gameMatchId != null) {
        _navigateToGame(
          gameMatchId,
          agoraAppId: data['agoraAppId'] as String?,
          agoraToken: data['agoraToken'] as String?,
          agoraChannelName: data['agoraChannelName'] as String?,
        );
      }
    });

    // NOW send the ready call, after listeners are in place
    try {
      await TournamentService.setMatchReady(widget.matchId);
    } catch (e) {
      debugPrint('Error setting match ready: $e');
    }
  }

  void _navigateToGame(String gameMatchId, {String? agoraAppId, String? agoraToken, String? agoraChannelName}) {
    if (!mounted) return;

    HapticService.heavyImpact();

    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;

    // Initialize the tournament game provider
    final tournamentGame = context.read<TournamentGameProvider>();
    tournamentGame.ensureListenersSetup();
    tournamentGame.initTournamentGame(
      tournamentMatchId: widget.matchId,
      gameMatchId: gameMatchId,
      tournamentId: widget.tournamentId,
      myUserId: user.id,
      opponentUserId: widget.opponentId,
      bestOf: widget.bestOf,
      roundName: widget.roundName,
      agoraAppId: agoraAppId,
      agoraToken: agoraToken,
      agoraChannelName: agoraChannelName,
    );

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => TournamentGameScreen(
          tournamentMatchId: widget.matchId,
          gameMatchId: gameMatchId,
          tournamentId: widget.tournamentId,
          tournamentName: widget.tournamentName,
          roundName: widget.roundName,
          opponentUsername: widget.opponentUsername,
          opponentId: widget.opponentId,
          bestOf: widget.bestOf,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    SocketService.off('matchReadyUpdate');
    SocketService.off('tournamentMatchStart');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().currentUser;
    final myUsername = user?.username ?? 'You';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            // Tournament info
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    widget.tournamentName,
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.roundName.replaceAll('_', ' ').toUpperCase()} • ${AppLocalizations.of(context).bestOf} ${widget.bestOf}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Player cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                children: [
                  Expanded(child: _buildPlayerCard(myUsername, _myReady, true)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'VS',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  Expanded(child: _buildPlayerCard(widget.opponentUsername, _opponentReady, false)),
                ],
              ),
            ),

            const SizedBox(height: 48),

            // Waiting indicator
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Opacity(
                  opacity: 0.5 + (_pulseController.value * 0.5),
                  child: child,
                );
              },
              child: Column(
                children: [
                  const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      color: AppTheme.primary,
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _opponentReady
                        ? AppLocalizations.of(context).startingMatch
                        : AppLocalizations.of(context).waitingForOpponent,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Back button
            Padding(
              padding: const EdgeInsets.all(24),
              child: TextButton(
                onPressed: () {
                  HapticService.lightImpact();
                  Navigator.of(context).pop();
                },
                child: Text(
                  AppLocalizations.of(context).cancelButton,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerCard(String username, bool isReady, bool isMe) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isReady ? AppTheme.success : AppTheme.surfaceLight,
          width: isReady ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isReady
                  ? AppTheme.success.withValues(alpha: 0.2)
                  : AppTheme.surfaceLight,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isReady ? Icons.check : Icons.hourglass_empty,
              color: isReady ? AppTheme.success : AppTheme.textSecondary,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isMe ? AppLocalizations.of(context).you : username,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            isReady ? AppLocalizations.of(context).ready : AppLocalizations.of(context).waiting2,
            style: TextStyle(
              color: isReady ? AppTheme.success : AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/orientation_utils.dart';
import '../../utils/tournament_round.dart';
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
  final DateTime? inviteSentAt;

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
    this.inviteSentAt,
  });

  @override
  State<TournamentReadyScreen> createState() => _TournamentReadyScreenState();
}

class _TournamentReadyScreenState extends State<TournamentReadyScreen>
    with SingleTickerProviderStateMixin {
  bool _myReady = false;
  bool _opponentReady = false;
  late AnimationController _pulseController;

  // 15-minute join window (mirrors the backend MATCH_INVITE_TIMEOUT).
  static const Duration _joinWindow = Duration(minutes: 15);
  Timer? _windowTimer;
  Duration _remaining = Duration.zero;
  bool _expired = false;

  @override
  void initState() {
    super.initState();
    OrientationUtils.allowAll();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _startWindowCountdown();
    _setupListeners();
  }

  void _startWindowCountdown() {
    final sentAt = widget.inviteSentAt;
    if (sentAt == null) return;
    final deadline = sentAt.add(_joinWindow);

    void tick() {
      final remaining = deadline.difference(DateTime.now());
      if (!mounted) return;
      setState(() {
        if (remaining <= Duration.zero) {
          _remaining = Duration.zero;
          _expired = true;
          _windowTimer?.cancel();
        } else {
          _remaining = remaining;
        }
      });
    }

    tick();
    _windowTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  String _formatRemaining(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
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
          agoraTokenStrict: data['agoraTokenStrict'] as String?,
          agoraChannelName: data['agoraChannelName'] as String?,
          agoraUid: (data['agoraUid'] as num?)?.toInt(),
          opponentAgoraUid: (data['opponentAgoraUid'] as num?)?.toInt(),
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

  void _navigateToGame(String gameMatchId, {String? agoraAppId, String? agoraToken, String? agoraTokenStrict, String? agoraChannelName, int? agoraUid, int? opponentAgoraUid}) {
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
      agoraTokenStrict: agoraTokenStrict,
      agoraChannelName: agoraChannelName,
      agoraUid: agoraUid,
      opponentAgoraUid: opponentAgoraUid,
    );

    AppNavigator.replaceWith(
      context,
      TournamentGameScreen(
        tournamentMatchId: widget.matchId,
        gameMatchId: gameMatchId,
        tournamentId: widget.tournamentId,
        tournamentName: widget.tournamentName,
        roundName: widget.roundName,
        opponentUsername: widget.opponentUsername,
        opponentId: widget.opponentId,
        bestOf: widget.bestOf,
      ),
    );
  }

  @override
  void dispose() {
    _windowTimer?.cancel();
    _pulseController.dispose();
    SocketService.off('matchReadyUpdate');
    SocketService.off('tournamentMatchStart');
    OrientationUtils.portraitOnly();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = context.read<AuthProvider>().currentUser;
    final myUsername = user?.username ?? l10n.you;

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
                    '${localizedRoundName(widget.roundName, l10n).toUpperCase()} • ${l10n.bestOf} ${widget.bestOf}',
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
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      l10n.vs.toUpperCase(),
                      style: const TextStyle(
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

            // Waiting indicator / expired state
            if (_expired)
              Column(
                children: [
                  const Icon(Icons.timer_off_outlined, size: 44, color: AppTheme.error),
                  const SizedBox(height: 12),
                  Text(
                    l10n.matchWindowExpiredTitle,
                    style: const TextStyle(
                      color: AppTheme.error,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      l10n.matchWindowExpiredHint,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                    ),
                  ),
                ],
              )
            else
              Column(
                children: [
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
                          _opponentReady ? l10n.startingMatch : l10n.waitingForOpponent,
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.inviteSentAt != null && !_opponentReady) ...[
                    const SizedBox(height: 16),
                    _buildCountdownPill(),
                  ],
                ],
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

  Widget _buildCountdownPill() {
    final low = _remaining.inSeconds <= 60;
    final color = low ? AppTheme.error : AppTheme.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            _formatRemaining(_remaining),
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
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

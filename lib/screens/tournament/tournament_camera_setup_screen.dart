import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/tournament_game_provider.dart';
import '../../services/socket_service.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/tournament_round.dart';
import '../matchmaking/camera_setup_screen.dart';
import 'tournament_game_screen.dart';
import 'tournament_ready_screen.dart';

/// Tournament entry into the shared [CameraSetupScreen]: same camera gate, AI
/// board detection and button behavior as ranked/friendly — this wrapper only
/// contributes the match-info banner and what happens after the tap.
class TournamentCameraSetupScreen extends StatelessWidget {
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

  /// When set, this is a RESUME of a live leg (app killed mid-match): after
  /// camera setup we go straight back into the game — the server re-syncs
  /// state (and Agora tokens) when the socket rejoins the match room.
  final String? rejoinGameMatchId;

  const TournamentCameraSetupScreen({
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
    this.rejoinGameMatchId,
  });

  /// A tournament match is entirely socket-driven once it starts
  /// (matchReadyUpdate, tournamentMatchStart, game_started). Walking in with
  /// a dead socket — or one still authenticated as a previously signed-in
  /// account — used to succeed: the HTTP ready-poll carried the lobby all the
  /// way into the game screen, which then spun on "initialising match"
  /// forever because no socket event could reach this device. Refuse to
  /// proceed instead, and say why. Runs before the camera is torn down, so a
  /// refusal leaves a live preview behind it.
  Future<bool> _validateSocket(BuildContext context) async {
    try {
      await SocketService.ensureAuthenticated();
    } catch (_) {}
    if (!context.mounted) return false;
    if (!SocketService.belongsToSession) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(AppLocalizations.of(context).connectionLostReconnecting),
          backgroundColor: AppTheme.error,
        ),
      );
      return false;
    }
    return true;
  }

  Future<bool> _navigate(BuildContext context) async {
    // Resume path: the leg is already running — skip the ready screen and
    // re-enter the game. State + Agora tokens arrive via game_state_sync when
    // the socket rejoins the match room.
    final rejoinGameId = rejoinGameMatchId;
    if (rejoinGameId != null) {
      final user = context.read<AuthProvider>().currentUser;
      if (user == null) return false;
      final tournamentGame = context.read<TournamentGameProvider>();
      // Awaited: the reply to the reconnect_to_match below is useless if the
      // handlers aren't attached yet.
      await tournamentGame.ensureListenersSetup();
      if (!context.mounted) return true;
      tournamentGame.initTournamentGame(
        tournamentMatchId: matchId,
        gameMatchId: rejoinGameId,
        tournamentId: tournamentId,
        myUserId: user.id,
        opponentUserId: opponentId,
        bestOf: bestOf,
        roundName: roundName,
      );
      // Ask the server for the state explicitly (mirrors the friendly rejoin
      // in camera_setup_screen.dart): on a cold start the fresh socket is in
      // no room, so without this emit no game_state_sync ever arrives and the
      // game screen spins on "initializing match" forever. The socket is
      // already known good — checked in _validateSocket.
      tournamentGame.reconnectToMatch();
      AppNavigator.replaceWith(
        context,
        TournamentGameScreen(
          tournamentMatchId: matchId,
          gameMatchId: rejoinGameId,
          tournamentId: tournamentId,
          tournamentName: tournamentName,
          roundName: roundName,
          opponentUsername: opponentUsername,
          opponentId: opponentId,
          bestOf: bestOf,
        ),
      );
      return true;
    }

    AppNavigator.replaceWith(
      context,
      TournamentReadyScreen(
        matchId: matchId,
        tournamentId: tournamentId,
        tournamentName: tournamentName,
        roundName: roundName,
        opponentUsername: opponentUsername,
        opponentId: opponentId,
        player1Id: player1Id,
        player2Id: player2Id,
        bestOf: bestOf,
        inviteSentAt: inviteSentAt,
      ),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CameraSetupScreen(
      matchInfo: CameraSetupMatchInfo(
        pill: localizedRoundName(roundName, l10n).toUpperCase(),
        title: tournamentName,
        subtitle: 'vs $opponentUsername • ${l10n.bestOf} $bestOf',
      ),
      actionLabel: l10n.ready,
      onValidate: _validateSocket,
      onConfirm: _navigate,
    );
  }
}

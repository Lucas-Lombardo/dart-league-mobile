import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import '../models/tournament.dart';
import '../services/tournament_service.dart';
import '../services/socket_service.dart';
import '../services/payment_service.dart';
import '../services/push_notification_service.dart';
import '../screens/tournament/tournament_camera_setup_screen.dart';
import '../utils/app_navigator.dart';

class TournamentProvider extends ChangeNotifier {
  List<Tournament> _allTournaments = [];
  List<Tournament> _upcomingTournaments = [];
  List<Tournament> _registeredTournaments = [];
  List<Tournament> _activeTournaments = [];
  List<TournamentMatch> _pendingMatches = [];
  List<TournamentHistory> _tournamentHistory = [];
  TournamentMatch? _activeMatch;
  Tournament? _currentTournament;
  List<TournamentMatch> _currentBracket = [];
  bool _isLoading = false;
  String? _error;

  bool _realtimeStarted = false;
  Timer? _pollTimer;
  static const Duration _pollInterval = Duration(seconds: 30);

  // Known after startRealtime — used to compute opponent info when deep-linking
  // from a push tap into the match flow.
  String? _myUserId;

  // The provider is the SINGLE owner of the tournament socket events (the
  // SocketService handler slots are one-per-event; screens registering their
  // own handlers used to clobber these on reconnect and vice versa). Screens
  // that need the raw events subscribe to these rebroadcast streams instead.
  final StreamController<Map<String, dynamic>> _readyUpdates =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _matchStarts =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _matchResults =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get readyUpdates => _readyUpdates.stream;
  Stream<Map<String, dynamic>> get matchStarts => _matchStarts.stream;
  Stream<Map<String, dynamic>> get matchResults => _matchResults.stream;

  List<Tournament> get allTournaments => _allTournaments;
  List<Tournament> get upcomingTournaments => _upcomingTournaments;
  List<Tournament> get registeredTournaments => _registeredTournaments;
  List<Tournament> get activeTournaments => _activeTournaments;
  List<TournamentMatch> get pendingMatches => _pendingMatches;
  List<TournamentHistory> get tournamentHistory => _tournamentHistory;
  TournamentMatch? get activeMatch => _activeMatch;
  Tournament? get currentTournament => _currentTournament;
  List<TournamentMatch> get currentBracket => _currentBracket;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool get hasPendingInvite => _pendingMatches.isNotEmpty;

  Future<void> loadAllTournaments() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _allTournaments = await TournamentService.getAllTournaments();
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading all tournaments: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadUpcomingTournaments() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _upcomingTournaments = await TournamentService.getUpcomingTournaments();
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading upcoming tournaments: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMyTournaments() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await TournamentService.getMyTournaments();
      _registeredTournaments = result['registered'] ?? [];
      _activeTournaments = result['active'] ?? [];
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading my tournaments: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadTournament(String id) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentTournament = await TournamentService.getTournament(id);
      _currentBracket = await TournamentService.getBracket(id);
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading tournament: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadBracket(String tournamentId) async {
    try {
      _currentBracket = await TournamentService.getBracket(tournamentId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading bracket: $e');
    }
  }

  Future<void> loadPendingMatches() async {
    try {
      _pendingMatches = await TournamentService.getPendingMatches();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading pending matches: $e');
    }
  }

  Future<void> loadActiveMatch() async {
    try {
      _activeMatch = await TournamentService.getActiveMatch();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading active match: $e');
    }
  }

  Future<void> loadTournamentHistory() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _tournamentHistory = await TournamentService.getTournamentHistory();
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading tournament history: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> registerForTournament(String tournamentId, {Tournament? tournament}) async {
    try {
      String? paymentIntentId;

      // If tournament is paid, process payment first
      if (tournament != null && !tournament.isFree) {
        final paymentData = await TournamentService.createPaymentIntent(tournamentId);
        final clientSecret = paymentData['clientSecret'] as String;
        paymentIntentId = paymentData['paymentIntentId'] as String;

        await PaymentService.processPayment(
          clientSecret: clientSecret,
          merchantDisplayName: 'Dart Rivals',
        );
      }

      // Retry registration up to 2 times if it fails after successful payment
      int retries = 0;
      while (true) {
        try {
          await TournamentService.registerForTournament(tournamentId, paymentIntentId: paymentIntentId);
          break;
        } catch (regError) {
          retries++;
          if (retries >= 3 || paymentIntentId == null) rethrow;
          debugPrint('Registration failed after payment (attempt $retries/3), retrying: $regError');
          await Future.delayed(Duration(seconds: retries));
        }
      }
      await loadMyTournaments();
      await loadUpcomingTournaments();
      return true;
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        _error = 'Payment cancelled';
      } else {
        _error = e.error.localizedMessage ?? 'Payment failed';
      }
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> unregisterFromTournament(String tournamentId) async {
    try {
      await TournamentService.unregisterFromTournament(tournamentId);
      await loadMyTournaments();
      await loadUpcomingTournaments();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> setMatchReady(String matchId) async {
    try {
      await TournamentService.setMatchReady(matchId);
      await loadPendingMatches();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> isRegisteredForTournament(String tournamentId) async {
    try {
      final result = await TournamentService.getMyRegistration(tournamentId);
      return result['registered'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Wire up real-time tournament events AND a polling fallback. Idempotent —
  /// safe to call on every HomeScreen mount.
  ///
  /// Why a poll fallback: push-notification receiving is unreliable on this
  /// app and websocket events only arrive while the socket is connected, so
  /// without a periodic refresh a user could silently miss the 15-minute
  /// window to join their tournament match (= automatic forfeit). The poll is
  /// the safety net; the socket is the fast path.
  Future<void> startRealtime({String? myUserId}) async {
    if (myUserId != null) _myUserId = myUserId;
    if (_realtimeStarted) return;
    _realtimeStarted = true;

    // Re-bind listeners after a socket reconnect. Uses the additive listener
    // API so we don't clobber matchmaking's single-slot reconnect handler.
    SocketService.addReconnectListener(_handleReconnect);

    // Tournament push taps (tournament_match, tournament_started, …) refresh
    // state and deep-link into the match flow. Additive listener — the friend
    // match_invite handler keeps its legacy slot.
    PushNotificationService.addOpenedListener(_handlePushOpened);

    try {
      await SocketService.ensureConnected();
      setupSocketListeners();
    } catch (e) {
      debugPrint('Tournament realtime: socket unavailable, relying on polling: $e');
    }

    await _pollOnce();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollOnce());
  }

  void stopRealtime() {
    _pollTimer?.cancel();
    _pollTimer = null;
    SocketService.removeReconnectListener(_handleReconnect);
    PushNotificationService.removeOpenedListener(_handlePushOpened);
    clearSocketListeners();
    _realtimeStarted = false;
  }

  // A tapped push brought the app forward. Refresh, and for a match invite
  // take the player straight to the camera-setup step of their match.
  void _handlePushOpened(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    if (!type.startsWith('tournament')) return;

    _pollOnce();

    if (type == 'tournament_match') {
      _openPendingMatchFromPush(data['matchId']?.toString());
    }
  }

  Future<void> _openPendingMatchFromPush(String? matchId) async {
    try {
      await loadPendingMatches();
      if (_pendingMatches.isEmpty) return;

      final match = _pendingMatches.firstWhere(
        (m) => m.id == matchId,
        orElse: () => _pendingMatches.first,
      );

      final myId = _myUserId;
      if (myId == null) return;
      final isPlayer1 = match.player1Id == myId;
      final opponentId = isPlayer1 ? match.player2Id : match.player1Id;
      final opponentUsername =
          isPlayer1 ? match.player2Username : match.player1Username;
      if (match.player1Id == null || match.player2Id == null) return;

      AppNavigator.pushFromRoot(
        TournamentCameraSetupScreen(
          matchId: match.id,
          tournamentId: match.tournamentId,
          tournamentName: match.tournamentName ?? 'Tournament',
          roundName: match.roundName,
          opponentUsername: opponentUsername ?? '',
          opponentId: opponentId ?? '',
          player1Id: match.player1Id!,
          player2Id: match.player2Id!,
          bestOf: match.bestOf,
          inviteSentAt: match.inviteSentAt,
        ),
      );
    } catch (e) {
      debugPrint('Tournament push deep-link failed: $e');
    }
  }

  void _handleReconnect() {
    // The socket may have been disposed/recreated (handlers cleared), so
    // re-register and refresh to catch anything missed while offline.
    setupSocketListeners();
    _pollOnce();
  }

  // Lightweight refresh used by the poll + reconnect. Deliberately avoids
  // loadMyTournaments() here because that toggles the loading spinner.
  Future<void> _pollOnce() async {
    await loadPendingMatches();
    await loadActiveMatch();
  }

  void setupSocketListeners() {
    clearSocketListeners();
    try {
      SocketService.on('tournamentRegistrationOpen', (data) {
        debugPrint('Tournament registration open: $data');
        loadUpcomingTournaments();
      });

      SocketService.on('tournamentMatchInvite', (data) {
        debugPrint('Tournament match invite: $data');
        loadPendingMatches();
      });

      SocketService.on('tournamentMatchStart', (data) {
        debugPrint('Tournament match start: $data');
        if (data is Map) {
          _matchStarts.add(Map<String, dynamic>.from(data));
        }
        loadActiveMatch();
        loadPendingMatches();
      });

      SocketService.on('tournamentMatchResult', (data) {
        debugPrint('Tournament match result: $data');
        if (data is Map) {
          _matchResults.add(Map<String, dynamic>.from(data));
        }
        loadMyTournaments();
        loadActiveMatch();
        loadPendingMatches();
      });

      SocketService.on('tournamentNextMatch', (data) {
        debugPrint('Tournament next match: $data');
        loadPendingMatches();
      });

      SocketService.on('tournamentEliminated', (data) {
        debugPrint('Tournament eliminated: $data');
        loadMyTournaments();
      });

      SocketService.on('tournamentComplete', (data) {
        debugPrint('Tournament complete: $data');
        loadMyTournaments();
        loadAllTournaments();
      });

      SocketService.on('matchReadyUpdate', (data) {
        debugPrint('Match ready update: $data');
        if (data is Map) {
          _readyUpdates.add(Map<String, dynamic>.from(data));
        }
        loadPendingMatches();
      });
    } catch (e) {
      debugPrint('Error setting up tournament socket listeners: $e');
    }
  }

  void clearSocketListeners() {
    try {
      SocketService.off('tournamentRegistrationOpen');
      SocketService.off('tournamentMatchInvite');
      SocketService.off('tournamentMatchStart');
      SocketService.off('tournamentMatchResult');
      SocketService.off('tournamentNextMatch');
      SocketService.off('tournamentEliminated');
      SocketService.off('tournamentComplete');
      SocketService.off('matchReadyUpdate');
    } catch (e) {
      debugPrint('Error clearing tournament socket listeners: $e');
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearCurrentTournament() {
    _currentTournament = null;
    _currentBracket = [];
    notifyListeners();
  }

  @override
  void dispose() {
    stopRealtime();
    _readyUpdates.close();
    _matchStarts.close();
    _matchResults.close();
    super.dispose();
  }
}

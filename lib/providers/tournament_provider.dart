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
  List<Tournament> _organizedTournaments = [];
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
  String? get myUserId => _myUserId;

  /// Test seam for the invite gate: stands in for startRealtime +
  /// loadPendingMatches, which both need a live backend.
  @visibleForTesting
  void debugSeedPendingMatches(List<TournamentMatch> matches,
      {String? myUserId}) {
    if (myUserId != null) _myUserId = myUserId;
    _pendingMatches = matches;
    notifyListeners();
  }

  /// Test seam: stands in for the tournamentMatchReminder socket event.
  @visibleForTesting
  void debugEmitInviteReminder(Map<String, dynamic> data) {
    _inviteReminders.add(data);
  }

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
  // Half-window nudge from the backend (tournamentMatchReminder): the invite
  // gate re-raises its prompt for that match. Consumed by the gate only.
  final StreamController<Map<String, dynamic>> _inviteReminders =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get readyUpdates => _readyUpdates.stream;
  Stream<Map<String, dynamic>> get matchStarts => _matchStarts.stream;
  Stream<Map<String, dynamic>> get matchResults => _matchResults.stream;
  Stream<Map<String, dynamic>> get inviteReminders => _inviteReminders.stream;

  List<Tournament> get allTournaments => _allTournaments;
  List<Tournament> get upcomingTournaments => _upcomingTournaments;
  List<Tournament> get registeredTournaments => _registeredTournaments;
  List<Tournament> get activeTournaments => _activeTournaments;

  /// Community tournaments the user organises and that aren't over — they
  /// stay in the agenda even when the organiser doesn't play.
  List<Tournament> get organizedTournaments => _organizedTournaments;
  List<TournamentMatch> get pendingMatches => _pendingMatches;
  List<TournamentHistory> get tournamentHistory => _tournamentHistory;
  TournamentMatch? get activeMatch => _activeMatch;
  Tournament? get currentTournament => _currentTournament;
  List<TournamentMatch> get currentBracket => _currentBracket;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool get hasPendingInvite => _pendingMatches.isNotEmpty;

  /// The join window a player has after `inviteSentAt` (mirrors the backend's
  /// TournamentService.MATCH_INVITE_TIMEOUT_MS).
  static const Duration joinWindow = Duration(minutes: 7);

  // ---- Unmissable invite prompt (TournamentInviteGate) -------------------
  //
  // Tournoi #4 (2026-08-22): 7 of the 11 forfeits were players who were IN
  // the app, socket connected, invite delivered — spectating a match or
  // chatting while they waited for the previous round to finish. The only
  // in-app signals were the Play button recolouring and a dot on the
  // Tournament tab, both invisible from those screens (and Android shows no
  // push at all while the app is foregrounded). So the provider now flags
  // every invite it sees for the first time; the gate turns that into a
  // full-screen prompt whatever screen the player is on.

  // Invite ids the player has already been prompted for (or that the app
  // opened directly, e.g. from a push tap / the "you advance" chain), so the
  // same invite never prompts twice — including after an unready, which puts
  // the match back in `pendingMatches`.
  final Set<String> _handledInviteIds = {};

  // Tournament match id whose lobby / camera-setup screen is currently open.
  // The gate holds its prompt while this is set: the lobby owns the
  // "you advance" dialog and chains into the next match itself.
  String? _openMatchScreenId;
  String? get openMatchScreenId => _openMatchScreenId;

  void setMatchScreenOpen(String matchId) {
    _openMatchScreenId = matchId;
  }

  void setMatchScreenClosed(String matchId) {
    if (_openMatchScreenId != matchId) return;
    _openMatchScreenId = null;
    // The gate re-evaluates once the lobby is gone: an invite that arrived
    // while it was open (and wasn't chained into) gets its prompt now. The
    // notify is deferred — this is called from dispose().
    scheduleMicrotask(notifyListeners);
  }

  void markInviteHandled(String matchId) {
    _handledInviteIds.add(matchId);
  }

  /// Lets the gate prompt again for an invite it already showed — used by
  /// the half-window reminder.
  void unmarkInviteHandled(String matchId) {
    _handledInviteIds.remove(matchId);
  }

  /// The pending invite the player has NOT been prompted for yet, if any.
  /// `excludeMatchId` lets the lobby of match A look for "the next match"
  /// without matching A itself.
  ///
  /// No client-side expiry check on purpose: the server list is the truth
  /// (its sweep forfeits expired invites within 10 s and the next refresh
  /// drops them), and a phone clock that is off would otherwise silence the
  /// prompt for an invite that is perfectly joinable.
  TournamentMatch? nextUnhandledInvite({String? excludeMatchId}) {
    for (final m in _pendingMatches) {
      if (m.id == excludeMatchId) continue;
      if (_handledInviteIds.contains(m.id)) continue;
      if (m.player1Id == null || m.player2Id == null) continue;
      return m;
    }
    return null;
  }

  /// Tournaments currently open for registration — drives the count bubble on
  /// the Tournament tab of the bottom bar.
  /// Official ones only: the players' own tournaments would keep it lit.
  int get openRegistrationCount => _upcomingTournaments
      .where((t) => t.isRegistrationOpen && t.isOfficial)
      .length;

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
      _organizedTournaments = result['organized'] ?? [];
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

  // ---- Live bracket on the tournament detail screen ----------------------
  //
  // `currentTournament` / `currentBracket` were a snapshot taken when the
  // detail screen opened. Nothing refreshed them afterwards (socket events
  // only touched pendingMatches; the 30 s poll never looked at the bracket),
  // so a player waiting on their bracket saw their match stuck on "À venir":
  // the hero card's Join button needs BOTH the invite in pendingMatches and
  // the match's status flipped to waiting_for_players in the bracket, and the
  // second half never arrived. Tournoi #4 (2026-08-22): the spectate entry
  // point lives on that very screen, so the players who went to watch a match
  // came back to a frozen bracket. The detail screen now registers itself and
  // every tournament socket event + poll tick refreshes what it shows.
  String? _watchedTournamentId;

  void watchTournament(String tournamentId) {
    _watchedTournamentId = tournamentId;
  }

  void unwatchTournament(String tournamentId) {
    if (_watchedTournamentId == tournamentId) _watchedTournamentId = null;
  }

  // Coalesces bursts (a walkover fires result + nextMatch + invite in the
  // same tick) into one in-flight refresh, with at most one follow-up.
  Future<void>? _watchedRefresh;
  bool _watchedRefreshAgain = false;

  Future<void> refreshWatchedTournament() {
    final id = _watchedTournamentId;
    if (id == null) return Future.value();
    final inFlight = _watchedRefresh;
    if (inFlight != null) {
      _watchedRefreshAgain = true;
      return inFlight;
    }
    final run = _refreshTournamentQuietly(id).whenComplete(() {
      _watchedRefresh = null;
      if (_watchedRefreshAgain) {
        _watchedRefreshAgain = false;
        refreshWatchedTournament();
      }
    });
    _watchedRefresh = run;
    return run;
  }

  // Same data as loadTournament() but without touching _isLoading / _error:
  // the detail screen must not flash its spinner on every tick.
  Future<void> _refreshTournamentQuietly(String tournamentId) async {
    try {
      final tournament = await TournamentService.getTournament(tournamentId);
      final bracket = await TournamentService.getBracket(tournamentId);
      // The user may have navigated to another tournament meanwhile.
      if (_watchedTournamentId != tournamentId) return;
      _currentTournament = tournament;
      _currentBracket = bracket;
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing watched tournament: $e');
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

  // ── Community tournaments (organised by a player) ──────────────────────

  /// Creates a tournament organised by the signed-in player and refreshes the
  /// agenda. Returns the new id, or null with [error] set.
  Future<String?> createCommunityTournament({
    required String name,
    required DateTime scheduledDate,
    required int maxParticipants,
    required int bestOf,
    required bool organizerPlays,
  }) async {
    try {
      final id = await TournamentService.createCommunityTournament(
        name: name,
        scheduledDate: scheduledDate,
        maxParticipants: maxParticipants,
        bestOf: bestOf,
        organizerPlays: organizerPlays,
      );
      await loadMyTournaments();
      await loadUpcomingTournaments();
      return id;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Runs one organiser action, then refreshes the open tournament and the
  /// agenda. False with [error] set on failure.
  Future<bool> _organizerAction(
    String tournamentId,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      await _refreshTournamentQuietly(tournamentId);
      await loadMyTournaments();
      await loadUpcomingTournaments();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateCommunityTournament(
    String tournamentId, {
    String? name,
    DateTime? scheduledDate,
    int? maxParticipants,
    int? bestOf,
  }) =>
      _organizerAction(
        tournamentId,
        () => TournamentService.updateCommunityTournament(
          tournamentId,
          name: name,
          scheduledDate: scheduledDate,
          maxParticipants: maxParticipants,
          bestOf: bestOf,
        ),
      );

  Future<bool> cancelCommunityTournament(String tournamentId) => _organizerAction(
        tournamentId,
        () => TournamentService.cancelCommunityTournament(tournamentId),
      );

  Future<bool> startCommunityTournament(String tournamentId) => _organizerAction(
        tournamentId,
        () => TournamentService.startCommunityTournament(tournamentId),
      );

  Future<bool> removeParticipant(String tournamentId, String userId) =>
      _organizerAction(
        tournamentId,
        () => TournamentService.removeParticipant(tournamentId, userId),
      );

  /// How many friends got the invitation, or null with [error] set.
  Future<int?> inviteFriends(String tournamentId, List<String> userIds) async {
    try {
      return await TournamentService.inviteFriends(tournamentId, userIds);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
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
    // Claim the invite BEFORE the refresh lands: the refresh notifies the
    // gate, which would otherwise raise its prompt under the camera-setup
    // screen pushed below.
    if (matchId != null) markInviteHandled(matchId);
    try {
      await loadPendingMatches();
      if (_pendingMatches.isEmpty) return;

      final match = _pendingMatches.firstWhere(
        (m) => m.id == matchId,
        orElse: () => _pendingMatches.first,
      );
      markInviteHandled(match.id);

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
    await _refreshUpcomingQuietly();
    await refreshWatchedTournament();
  }

  // Same data as loadUpcomingTournaments() but without touching _isLoading —
  // keeps the tab-bar bubble fresh without flashing spinners on open screens.
  Future<void> _refreshUpcomingQuietly() async {
    try {
      _upcomingTournaments = await TournamentService.getUpcomingTournaments();
      notifyListeners();
    } catch (e) {
      debugPrint('Error refreshing upcoming tournaments: $e');
    }
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
        refreshWatchedTournament();
      });

      // Backend nudge at the middle of the join window for a player who
      // hasn't readied. Rebroadcast to the gate BEFORE the refresh so it can
      // clear its "already prompted" mark ahead of the notify.
      SocketService.on('tournamentMatchReminder', (data) {
        debugPrint('Tournament match reminder: $data');
        if (data is Map) {
          _inviteReminders.add(Map<String, dynamic>.from(data));
        }
        loadPendingMatches();
      });

      SocketService.on('tournamentMatchStart', (data) {
        debugPrint('Tournament match start: $data');
        if (data is Map) {
          _matchStarts.add(Map<String, dynamic>.from(data));
        }
        loadActiveMatch();
        loadPendingMatches();
        refreshWatchedTournament();
      });

      SocketService.on('tournamentMatchResult', (data) {
        debugPrint('Tournament match result: $data');
        if (data is Map) {
          _matchResults.add(Map<String, dynamic>.from(data));
        }
        loadMyTournaments();
        loadActiveMatch();
        loadPendingMatches();
        refreshWatchedTournament();
      });

      SocketService.on('tournamentNextMatch', (data) {
        debugPrint('Tournament next match: $data');
        loadPendingMatches();
        refreshWatchedTournament();
      });

      SocketService.on('tournamentEliminated', (data) {
        debugPrint('Tournament eliminated: $data');
        loadMyTournaments();
        // A no-show forfeit removes the invite: refresh so the invite prompt
        // / Join button disappear now rather than at the next 30 s poll.
        loadPendingMatches();
        refreshWatchedTournament();
      });

      SocketService.on('tournamentComplete', (data) {
        debugPrint('Tournament complete: $data');
        loadMyTournaments();
        loadAllTournaments();
        refreshWatchedTournament();
      });

      SocketService.on('matchReadyUpdate', (data) {
        debugPrint('Match ready update: $data');
        if (data is Map) {
          _readyUpdates.add(Map<String, dynamic>.from(data));
        }
        loadPendingMatches();
        refreshWatchedTournament();
      });
    } catch (e) {
      debugPrint('Error setting up tournament socket listeners: $e');
    }
  }

  void clearSocketListeners() {
    try {
      SocketService.off('tournamentRegistrationOpen');
      SocketService.off('tournamentMatchInvite');
      SocketService.off('tournamentMatchReminder');
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

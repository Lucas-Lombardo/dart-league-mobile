import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/matchmaking_service.dart';
import '../services/match_service.dart';
import '../services/socket_service.dart';
import '../utils/haptic_service.dart';
import '../utils/dart_sound_service.dart';
import 'game_provider.dart';

class MatchmakingProvider with ChangeNotifier {
  bool _isSearching = false;
  bool _disposed = false;
  bool _matchFound = false;
  // True from the moment the user asks to leave the queue until that leave
  // completes. Gates match_found/poll handling so a match_found (or active-match
  // poll result) arriving during the leave round-trip can't navigate the user
  // into a match they just cancelled.
  bool _leaving = false;
  String? _matchId;
  String? _opponentId;
  String? _opponentUsername;
  int? _opponentElo;
  int? _playerElo;
  int _eloRange = 250;
  int _searchTime = 0;
  Timer? _searchTimer;
  Timer? _pollTimer;
  
  // Agora video credentials
  String? _agoraAppId;
  String? _agoraToken;
  String? _agoraTokenStrict;
  String? _agoraChannelName;
  int? _agoraUid;
  int? _opponentAgoraUid;
  GameProvider? _gameProvider;
  String? _errorMessage;
  String? _currentUserId; // Store userId for initGame call

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  bool get isSearching => _isSearching;
  int get searchTime => _searchTime;
  int get eloRange => _eloRange;
  bool get matchFound => _matchFound;
  String? get matchId => _matchId;
  String? get opponentId => _opponentId;
  String? get opponentUsername => _opponentUsername;
  int? get opponentElo => _opponentElo;
  int? get playerElo => _playerElo;
  String? get agoraAppId => _agoraAppId;
  String? get agoraToken => _agoraToken;
  String? get agoraTokenStrict => _agoraTokenStrict;
  String? get agoraChannelName => _agoraChannelName;
  int? get agoraUid => _agoraUid;
  int? get opponentAgoraUid => _opponentAgoraUid;
  String? get errorMessage => _errorMessage;

  void setGameProvider(GameProvider provider) {
    _gameProvider = provider;
  }

  Future<void> joinQueue(String userId) async {
    debugPrint('QUEUE DEBUG: joinQueue called - userId=$userId');
    debugPrint('QUEUE DEBUG: gameProvider state - gameStarted=${_gameProvider?.gameStarted}, gameEnded=${_gameProvider?.gameEnded}, winnerId=${_gameProvider?.winnerId}, matchId=${_gameProvider?.matchId}');

    // Reset ALL state from the previous match/search BEFORE any await. Doing the
    // reset (especially the search timer) up front means a failure below can
    // never leave a stale "0:30" from the previous search frozen on screen.
    _leaving = false;
    _matchFound = false;
    _matchId = null;
    _opponentId = null;
    _opponentUsername = null;
    _opponentElo = null;
    _agoraAppId = null;
    _agoraToken = null;
    _agoraTokenStrict = null;
    _agoraChannelName = null;
    _agoraUid = null;
    _opponentAgoraUid = null;
    _errorMessage = null;
    _currentUserId = userId;
    _eloRange = 250;

    // Reset game provider if it still has stale state from the previous match
    if (_gameProvider != null && (_gameProvider!.gameStarted || _gameProvider!.gameEnded)) {
      debugPrint('QUEUE DEBUG: Resetting stale game provider state before queuing');
      _gameProvider!.reset();
    }

    // Enter the searching state immediately at 0:00 and start ticking, so the UI
    // is always coherent regardless of what happens with the socket below.
    _isSearching = true;
    _startSearchTimer();

    // Register recovery handlers BEFORE connecting. If the socket is down right
    // now (e.g. it bounced after the previous game) the reconnect handler will
    // re-drive the queue join once it comes back, instead of us silently giving
    // up and leaving the player "disconnected" and not actually queued.
    SocketService.clearReconnectHandler();
    SocketService.setReconnectHandler(() {
      // Queue recovery ONLY. This handler stays registered long after the
      // search ends, so it must not touch the game providers outside the
      // searching phase: driving GameProvider.ensureListenersSetup() from a
      // stale handler used to re-register its listeners over a running
      // tournament's (the event registry is single-slot per event) and freeze
      // that tournament match. Mid-match reconnection is owned by each game
      // provider's own reconnect listener.
      if (!_isSearching || _matchFound || _leaving) return;
      _setupSocketListeners();
      _gameProvider?.ensureListenersSetup();
      _rejoinQueueAfterReconnect();
    });

    notifyListeners();

    try {
      // Wait for the capability handshake, not just the transport: the join
      // body only declares supportsRankedBo3 once `authenticated` has landed,
      // and a join POSTed in the gap queues this player as BO1-only — even a
      // rejoin can then only upgrade the entry until it gets matched.
      await SocketService.ensureAuthenticated();
    } catch (e) {
      // Socket not ready yet. Keep the searching UI up (the connection banner
      // already reflects "disconnected"); SocketService retries the connection
      // unboundedly and the reconnect handler above will POST the join then.
      debugPrint('QUEUE DEBUG: socket not ready, will join on reconnect: $e');
      return;
    }

    // The waits above can take seconds — the user may have cancelled (or a
    // match_found may have landed) in the meantime. POSTing anyway would
    // re-queue a player whose UI already left the search.
    if (!_isSearching || _matchFound || _leaving) return;

    // Socket is connected — wire listeners and actually join the queue.
    _gameProvider?.ensureListenersSetup();
    _setupSocketListeners();

    try {
      final response = await MatchmakingService.joinQueue(userId);
      _playerElo = response['playerElo'] as int?;
      notifyListeners();
    } catch (e) {
      // A business error (daily limit, active tournament, already in a match…) —
      // surface it and stop searching. Connection errors are handled above.
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isSearching = false;
      _stopSearchTimer();
      notifyListeners();
    }
  }

  /// Re-issue the queue join after the socket reconnects mid-search. The server
  /// join is idempotent (already-queued → no-op), so this safely recovers a
  /// search that was interrupted by a dropped socket. No-op if we're no longer
  /// searching, already matched, or leaving.
  Future<void> _rejoinQueueAfterReconnect() async {
    if (!_isSearching || _matchFound || _leaving || _currentUserId == null) {
      return;
    }
    try {
      // This runs from onConnect, which always fires BEFORE the server's
      // `authenticated` event is processed — POSTing right away would build
      // the join body with supportsRankedBo3 still false (it resets on every
      // disconnect) and queue this player as BO1-only. Wait for the handshake.
      await SocketService.ensureAuthenticated();
      if (!_isSearching || _matchFound || _leaving) return;
      final response = await MatchmakingService.joinQueue(_currentUserId!);
      if (!_isSearching || _matchFound || _leaving) return;
      _playerElo = response['playerElo'] as int?;
      notifyListeners();
    } catch (e) {
      // If we were matched while offline the server may reject the re-join; the
      // 5s active-match poll recovers us into that match. Anything else: leave
      // the search running so a later reconnect retries.
      debugPrint('QUEUE DEBUG: rejoin after reconnect failed: $e');
    }
  }

  void _setupSocketListeners() {
    _cleanupSocketListeners();

    SocketService.on('match_found', (data) {
      _handleMatchFound(data);
    });

    SocketService.on('searching_expanded', (data) {
      _handleSearchingExpanded(data);
    });

    SocketService.on('queue_error', (data) {
      _handleQueueError(data);
    });

  }

  void _startSearchTimer() {
    _searchTimer?.cancel();
    _searchTime = 0;
    _searchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _searchTime++;
      notifyListeners();
    });
    _startActiveMatchPolling();
  }

  void _stopSearchTimer() {
    _searchTimer?.cancel();
    _searchTimer = null;
    _stopPolling();
  }

  void _startActiveMatchPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!_isSearching || _matchFound || _leaving || _currentUserId == null) return;
      try {
        final result = await MatchService.getActiveMatch(_currentUserId!);
        // Re-check state after await to avoid acting on stale conditions
        if (!_isSearching || _matchFound || _leaving || _currentUserId == null) return;
        if (result['active'] == true) {
          debugPrint('QUEUE DEBUG: active match detected via poll - matchId=${result['matchId']}');
          _handleMatchFound({
            'matchId': result['matchId'],
            'opponentId': result['opponentId'],
            'opponentUsername': result['opponentUsername'] ?? 'Opponent',
            'opponentElo': result['opponentElo'],
            'playerElo': result['playerElo'],
          });
        }
      } catch (_) {
        // ignore poll errors silently
      }
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _handleMatchFound(dynamic data) {
    // Ignore any match landing while we're leaving the queue. Without this, a
    // match_found (or active-match poll) arriving during the leave round-trip
    // would flip _matchFound and the global navigation gate would drag the user
    // into a match they just cancelled — which then instantly forfeited.
    if (_leaving) {
      debugPrint('QUEUE DEBUG: match_found ignored (leaving queue)');
      return;
    }
    debugPrint('QUEUE DEBUG: match_found received - matchId=${data['matchId']}, opponentId=${data['opponentId']}');
    debugPrint('QUEUE DEBUG: gameProvider state at match_found - gameStarted=${_gameProvider?.gameStarted}, gameEnded=${_gameProvider?.gameEnded}');

    HapticService.heavyImpact();
    DartSoundService.playMatchFound();

    _stopSearchTimer();
    _matchFound = true;
    _matchId = data['matchId'] as String?;
    _opponentId = data['opponentId'] as String?;
    _opponentUsername = data['opponentUsername'] as String?;
    _opponentElo = data['opponentElo'] as int?;
    _playerElo = data['playerElo'] as int?;
    
    // Only update Agora credentials if they're provided in this data
    // This prevents HTTP responses from overwriting socket credentials with null
    final newAgoraAppId = data['agoraAppId'] as String?;
    final newAgoraToken = data['agoraToken'] as String?;
    final newAgoraTokenStrict = data['agoraTokenStrict'] as String?;
    final newAgoraChannelName = data['agoraChannelName'] as String?;
    final newAgoraUid = (data['agoraUid'] as num?)?.toInt();
    final newOpponentAgoraUid = (data['opponentAgoraUid'] as num?)?.toInt();

    if (newAgoraAppId != null && newAgoraToken != null && newAgoraChannelName != null) {
      _agoraAppId = newAgoraAppId;
      _agoraToken = newAgoraToken;
      _agoraChannelName = newAgoraChannelName;
    }
    if (newAgoraTokenStrict != null && newAgoraTokenStrict.isNotEmpty) {
      _agoraTokenStrict = newAgoraTokenStrict;
    }
    if (newAgoraUid != null) _agoraUid = newAgoraUid;
    if (newOpponentAgoraUid != null) _opponentAgoraUid = newOpponentAgoraUid;
    
    _isSearching = false;
    
    // Debug opponent data
    
    // Initialize game IMMEDIATELY so myUserId is set before game_started arrives
    // This fixes the race condition where game_started arrives before navigation
    if (_gameProvider != null && _currentUserId != null && _matchId != null && _opponentId != null) {
      debugPrint('DEBUG: initGame called with userId=$_currentUserId');
      _gameProvider!.initGame(
        _matchId!,
        _currentUserId!,
        _opponentId!,
        agoraAppId: _agoraAppId,
        agoraToken: _agoraToken,
        agoraTokenStrict: _agoraTokenStrict,
        agoraChannelName: _agoraChannelName,
        agoraUid: _agoraUid,
        opponentAgoraUid: _opponentAgoraUid,
      );
    } else {
      debugPrint('DEBUG: initGame SKIPPED - gameProvider=$_gameProvider, userId=$_currentUserId, matchId=$_matchId, opponentId=$_opponentId');
    }
    
    
    notifyListeners();
  }

  void _handleSearchingExpanded(dynamic data) {
    
    if (data is Map && data['range'] != null) {
      _eloRange = data['range'] as int;
      notifyListeners();
    }
  }

  void _handleQueueError(dynamic data) {

    _errorMessage = data['message'] as String? ?? 'Queue error occurred';
    _isSearching = false;
    _stopSearchTimer();
    notifyListeners();
  }

  Future<void> leaveQueue(String userId) async {
    // Enter the leaving state and tear down listeners/timers BEFORE the network
    // call. A match_found can arrive during the round-trip; if we waited until
    // after the await to remove listeners, that event would still navigate the
    // user into the cancelled match. Order matters here.
    _leaving = true;
    _cleanupSocketListeners();
    _stopSearchTimer();
    _isSearching = false;
    _matchFound = false;
    notifyListeners();
    try {
      await MatchmakingService.leaveQueue(userId);

      _isSearching = false;
      _searchTime = 0;
      _eloRange = 250;
      _matchFound = false;
      _matchId = null;
      _opponentId = null;
      _opponentUsername = null;
      _opponentElo = null;
      _playerElo = null;
      _agoraAppId = null;
      _agoraToken = null;
      _agoraTokenStrict = null;
      _agoraChannelName = null;
      _agoraUid = null;
      _opponentAgoraUid = null;
      _errorMessage = null;
      notifyListeners();
    } catch (_) {
      // Leave queue failed
    }
  }

  void _cleanupSocketListeners() {
    SocketService.off('match_found');
    SocketService.off('searching_expanded');
    SocketService.off('queue_error');
    SocketService.off('queue_timeout');
  }

  void resetMatch() {
    _matchFound = false;
    _matchId = null;
    _opponentId = null;
    _opponentUsername = null;
    _opponentElo = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopSearchTimer();
    _stopPolling();
    SocketService.clearReconnectHandler();
    _cleanupSocketListeners();
    super.dispose();
  }
}

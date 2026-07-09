import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/socket_service.dart';
import 'game_provider.dart' show ScoreMultiplier;

enum TournamentGameState {
  waiting,
  playing,
  legEnded,
  seriesEnded,
}

class TournamentGameProvider with ChangeNotifier {
  // Match identifiers
  String? _tournamentMatchId;
  String? _currentGameMatchId;
  String? _tournamentId;
  String? _roundName;
  int _bestOf = 1;

  // Player info
  String? _myUserId;
  String? _opponentUserId;
  String? _player1Id;
  String? _firstThrowerId; // Whoever threw first in the match (set once)

  // Current leg game state (same as GameProvider)
  int _myScore = 501;
  int _opponentScore = 501;
  String? _currentPlayerId;
  int _dartsThrown = 0;
  bool _gameStarted = false;
  bool _gameEnded = false;
  String? _winnerId;
  String? _lastThrow;
  List<String> _currentRoundThrows = [];
  List<String> _opponentRoundThrows = [];
  int _dartsEmittedThisRound = 0; // Local guard for rapid throws before server ack
  // Per-dart delivery tracking — see GameProvider for the full rationale.
  // Every throw_dart carries a dartId; the server acks and dedups, so lost
  // darts are re-sent instead of silently disappearing.
  final Map<String, Map<String, dynamic>> _pendingDartAcks = {};
  Timer? _dartRetryTimer;
  int _dartIdSeq = 0;
  int _ackedDartsThisRound = 0;
  int _confirmAttempts = 0;
  int _confirmRejectedRetries = 0;
  bool _pendingConfirmation = false;
  String? _pendingType;
  String? _pendingReason;
  Map<String, dynamic>? _pendingData;
  bool _opponentDisconnected = false;
  int _disconnectGraceSeconds = 0;
  Timer? _disconnectCountdownTimer;

  // Our OWN connection state — mirrors the server's 5-minute disconnect grace
  // period (see GameProvider for rationale).
  static const int _selfGracePeriodSeconds = 300;
  bool _selfDisconnected = false;
  int _selfDisconnectGraceSeconds = 0;
  Timer? _selfDisconnectCountdownTimer;
  bool _connectionListenersRegistered = false;

  // Tournament series state
  int _player1LegsWon = 0;
  int _player2LegsWon = 0;
  int _currentLeg = 1;
  int _legsNeeded = 1;
  String? _legWinnerId;
  String? _seriesWinnerId;
  String? _seriesLoserId;
  TournamentGameState _tournamentState = TournamentGameState.waiting;

  // Agora video calling
  String? _agoraAppId;
  String? _agoraToken;
  String? _agoraTokenStrict;
  String? _agoraChannelName;
  int? _agoraUid;
  int? _opponentAgoraUid;
  int? _remoteUid;
  bool _localUserJoined = false;
  bool _needsAgoraReconnect = false;

  bool _listenersSetUp = false;
  bool _disposed = false;

  TournamentGameProvider();

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  // Getters — match identifiers
  String? get tournamentMatchId => _tournamentMatchId;
  String? get currentGameMatchId => _currentGameMatchId;
  String? get tournamentId => _tournamentId;
  String? get roundName => _roundName;
  int get bestOf => _bestOf;

  // Getters — current leg game state
  int get myScore => _myScore;
  int get opponentScore => _opponentScore;
  String? get currentPlayerId => _currentPlayerId;
  String? get myUserId => _myUserId;
  String? get opponentUserId => _opponentUserId;
  int get dartsThrown => _dartsThrown;
  bool get gameStarted => _gameStarted;
  bool get gameEnded => _gameEnded;
  String? get winnerId => _winnerId;
  String? get lastThrow => _lastThrow;
  List<String> get currentRoundThrows => _currentRoundThrows;
  List<String> get opponentRoundThrows => _opponentRoundThrows;
  bool get pendingConfirmation => _pendingConfirmation;
  String? get pendingType => _pendingType;
  String? get pendingReason => _pendingReason;
  Map<String, dynamic>? get pendingData => _pendingData;
  bool get opponentDisconnected => _opponentDisconnected;
  int get disconnectGraceSeconds => _disconnectGraceSeconds;
  bool get selfDisconnected => _selfDisconnected;
  int get selfDisconnectGraceSeconds => _selfDisconnectGraceSeconds;
  /// Darts emitted but not yet confirmed applied by the server. The AI
  /// auto-confirm must not end the turn while this is non-zero.
  int get unackedDartCount => _pendingDartAcks.length;

  /// Darts the server has confirmed applied this round.
  int get ackedDartsThisRound => _ackedDartsThisRound;

  bool get isMyTurn => _currentPlayerId == _myUserId;
  // True when this user was the second to throw in the match (captured from
  // the first game_started event). Used to render the current user on the
  // right side of the scoreboard. Derived from currentPlayerId so both clients
  // agree regardless of whether the server sends a player1Id field.
  bool get iAmPlayer2 => _firstThrowerId != null && _myUserId != null && _firstThrowerId != _myUserId;

  // Getters — series state
  int get player1LegsWon => _player1LegsWon;
  int get player2LegsWon => _player2LegsWon;
  int get currentLeg => _currentLeg;
  int get legsNeeded => _legsNeeded;
  String? get legWinnerId => _legWinnerId;
  String? get seriesWinnerId => _seriesWinnerId;
  String? get seriesLoserId => _seriesLoserId;
  TournamentGameState get tournamentState => _tournamentState;
  int get myLegsWon => _myUserId == _player1Id ? _player1LegsWon : _player2LegsWon;
  int get opponentLegsWon => _myUserId == _player1Id ? _player2LegsWon : _player1LegsWon;
  bool get iSeriesWinner => _seriesWinnerId == _myUserId;

  // Getters — Agora
  String? get agoraAppId => _agoraAppId;
  String? get agoraToken => _agoraToken;
  String? get agoraTokenStrict => _agoraTokenStrict;
  String? get agoraChannelName => _agoraChannelName;
  int? get agoraUid => _agoraUid;
  int? get opponentAgoraUid => _opponentAgoraUid;
  int? get remoteUid => _remoteUid;
  bool get localUserJoined => _localUserJoined;
  bool get needsAgoraReconnect => _needsAgoraReconnect;

  bool get hasStrictAgoraCredentials =>
      _agoraTokenStrict != null && _agoraTokenStrict!.isNotEmpty && _agoraUid != null && _agoraUid != 0;

  int get currentRoundScore {
    int score = 0;
    for (final dart in _currentRoundThrows) {
      if (dart.startsWith('S')) {
        score += int.parse(dart.substring(1));
      } else if (dart.startsWith('D')) {
        score += int.parse(dart.substring(1)) * 2;
      } else if (dart.startsWith('T')) {
        score += int.parse(dart.substring(1)) * 3;
      }
    }
    return score;
  }

  Future<void> ensureListenersSetup() async {
    if (_listenersSetUp) return;
    await SocketService.ensureConnected();
    _setupSocketListeners();
    _listenersSetUp = true;
  }

  void initTournamentGame({
    required String tournamentMatchId,
    required String gameMatchId,
    required String tournamentId,
    required String myUserId,
    required String opponentUserId,
    required int bestOf,
    required String roundName,
    String? agoraAppId,
    String? agoraToken,
    String? agoraTokenStrict,
    String? agoraChannelName,
    int? agoraUid,
    int? opponentAgoraUid,
  }) {
    _tournamentMatchId = tournamentMatchId;
    _currentGameMatchId = gameMatchId;
    _tournamentId = tournamentId;
    _myUserId = myUserId;
    _opponentUserId = opponentUserId;
    _bestOf = bestOf;
    _roundName = roundName;
    _legsNeeded = (bestOf / 2).ceil();
    _player1LegsWon = 0;
    _player2LegsWon = 0;
    _currentLeg = 1;
    _tournamentState = TournamentGameState.waiting;
    _seriesWinnerId = null;
    _seriesLoserId = null;
    _player1Id = null;
    _firstThrowerId = null;

    if (agoraAppId != null) _agoraAppId = agoraAppId;
    if (agoraToken != null) _agoraToken = agoraToken;
    if (agoraTokenStrict != null) _agoraTokenStrict = agoraTokenStrict;
    if (agoraChannelName != null) _agoraChannelName = agoraChannelName;
    if (agoraUid != null) _agoraUid = agoraUid;
    if (opponentAgoraUid != null) {
      _opponentAgoraUid = opponentAgoraUid;
      // Pre-seed remote view only when we'll join via the strict path
      // (same reasoning as GameProvider.initGame).
      if (agoraTokenStrict != null && agoraTokenStrict.isNotEmpty && agoraUid != null && agoraUid != 0) {
        _remoteUid = opponentAgoraUid;
      }
    }

    _resetLegState();
    notifyListeners();
  }

  void _resetLegState() {
    _myScore = 501;
    _opponentScore = 501;
    _dartsThrown = 0;
    _gameEnded = false;
    _gameStarted = false;
    _winnerId = null;
    _lastThrow = null;
    _currentRoundThrows = [];
    _dartsEmittedThisRound = 0;
    _clearPendingDarts();
    _ackedDartsThisRound = 0;
    _confirmAttempts = 0;
    _confirmRejectedRetries = 0;
    _pendingConfirmation = false;
    _pendingType = null;
    _pendingReason = null;
    _pendingData = null;
    _legWinnerId = null;
  }

  // --- Socket listeners ---

  void _setupSocketListeners() {
    SocketService.on('game_started', _handleGameStarted);
    SocketService.on('score_updated', _handleScoreUpdated);
    SocketService.on('round_ready_confirm', _handleRoundReadyConfirm);
    SocketService.on('round_complete', _handleRoundComplete);
    SocketService.on('game_won', _handleGameWon);
    SocketService.on('match_ended', _handleMatchEnded);
    SocketService.on('invalid_throw', _handleInvalidThrow);
    SocketService.on('must_finish_double', _handleMustFinishDouble);
    SocketService.on('pending_win', _handlePendingWin);
    SocketService.on('pending_bust', _handlePendingBust);
    SocketService.on('opponent_disconnected', _handleOpponentDisconnected);
    SocketService.on('opponent_reconnected', _handleOpponentReconnected);
    SocketService.on('game_state_sync', _handleGameStateSync);
    SocketService.on('player_forfeited', _handlePlayerForfeited);
    SocketService.on('dart_undone', _handleDartUndone);
    SocketService.on('throw_dart_ack', _handleThrowDartAck);
    SocketService.on('confirm_round_rejected', _handleConfirmRoundRejected);

    // Tournament-specific events
    SocketService.on('tournament_leg_won', _handleTournamentLegWon);
    SocketService.on('tournament_next_leg', _handleTournamentNextLeg);
    SocketService.on('tournament_match_won', _handleTournamentMatchWon);

    // Observe our OWN connection (see GameProvider for rationale).
    if (!_connectionListenersRegistered) {
      _connectionListenersRegistered = true;
      SocketService.addDisconnectListener(_handleSelfDisconnected);
      SocketService.addReconnectListener(_handleSelfReconnected);
    }
  }

  void _handleSelfDisconnected() {
    if (_currentGameMatchId == null || !_gameStarted || _gameEnded) return;

    _selfDisconnected = true;
    _selfDisconnectGraceSeconds = _selfGracePeriodSeconds;
    _selfDisconnectCountdownTimer?.cancel();
    _selfDisconnectCountdownTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      _selfDisconnectGraceSeconds--;
      if (_selfDisconnectGraceSeconds <= 0) {
        timer.cancel();
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void _handleSelfReconnected() {
    final wasDisconnected = _selfDisconnected;
    _cancelSelfDisconnectCountdown();
    if (wasDisconnected && _currentGameMatchId != null && !_gameEnded) {
      reconnectToMatch();
    }
    notifyListeners();
  }

  void _cancelSelfDisconnectCountdown() {
    _selfDisconnected = false;
    _selfDisconnectGraceSeconds = 0;
    _selfDisconnectCountdownTimer?.cancel();
    _selfDisconnectCountdownTimer = null;
  }

  // --- Standard game event handlers (same as GameProvider) ---

  void _handleGameStarted(dynamic data) {
    debugPrint('TOURNAMENT: game_started received');
    _gameStarted = true;
    _currentPlayerId = data['currentPlayerId'] as String?;

    // Capture the first thrower for the match (stable for scoreboard
    // positioning across legs). Set once; never overwritten.
    _firstThrowerId ??= _currentPlayerId;

    // Use server-provided player1Id for correct score mapping.
    // player1Id is fixed for the entire series — it does NOT change between legs.
    // Who throws first (currentPlayerId) alternates between legs, so it must NOT
    // be used for score mapping.
    final serverPlayer1Id = data['player1Id'] as String?;
    if (serverPlayer1Id != null) {
      _player1Id = serverPlayer1Id;
    } else {
      // Why: the previous fallback (`_player1Id ??= _myUserId`) caused both
      // clients to self-identify as player1, which made score mapping disagree
      // between devices and surfaced as reversed scores in the scoreboard.
      // currentPlayerId is the same value on both devices, so deriving from it
      // keeps them in sync. Only valid for leg 1 (where the first thrower is
      // player1); subsequent legs already have _player1Id set, so the ??= is a
      // no-op. Server MUST send player1Id; this fallback is just defensive.
      debugPrint('TOURNAMENT WARNING: game_started missing player1Id; falling back to currentPlayerId');
      _player1Id ??= _currentPlayerId;
    }
    debugPrint('TOURNAMENT: game_started - player1Id=$_player1Id, currentPlayerId=$_currentPlayerId, firstThrowerId=$_firstThrowerId');

    _myScore = 501;
    _opponentScore = 501;
    _tournamentState = TournamentGameState.playing;
    notifyListeners();
  }

  /// True when an event belongs to a different match (previous leg, other
  /// match) than the leg currently being played.
  bool _isForeignMatch(dynamic data) {
    if (data is! Map) return false;
    final eventMatchId = data['matchId'] as String?;
    return eventMatchId != null &&
        _currentGameMatchId != null &&
        eventMatchId != _currentGameMatchId;
  }

  void _handleScoreUpdated(dynamic data) {
    if (_isForeignMatch(data)) return;
    // Why: auto-resync the turn when round_complete was missed (e.g. brief
    // socket disconnect that left the client out of the room). The server
    // always includes currentPlayerId in score_updated payloads.
    final serverCurrentPlayerId = data['currentPlayerId'] as String?;
    if (serverCurrentPlayerId != null && serverCurrentPlayerId != _currentPlayerId) {
      _currentPlayerId = serverCurrentPlayerId;
    }

    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    if (player1Score != null && player2Score != null) {
      _updateScoresFromPlayerScores(player1Score, player2Score);
    }
    _lastThrow = data['notation'] as String?;
    _dartsThrown = data['dartsThrown'] as int? ?? _dartsThrown;
    // Server is the single source of truth for currentRoundThrows
    if (data['currentRoundThrows'] != null && isMyTurn) {
      final throws = data['currentRoundThrows'] as List<dynamic>?;
      if (throws != null) {
        _currentRoundThrows = throws.map((t) => t.toString()).toList();
        // Never let a stale echo LOWER the guard below what is delivered or
        // in flight — that used to re-open an occupied slot (dart duplication).
        final claimed = _ackedDartsThisRound + _pendingDartAcks.length;
        final serverCount = _currentRoundThrows.length;
        _dartsEmittedThisRound =
            serverCount > claimed ? serverCount : claimed;
        if (serverCount > _ackedDartsThisRound) {
          _ackedDartsThisRound = serverCount;
        }
      }
    }
    // Track opponent's throws during their turn
    // Only use currentRoundThrows as source of truth — never append _lastThrow
    // separately, as it causes duplicates on reconnect.
    if (!isMyTurn) {
      final throws = data['currentRoundThrows'] as List<dynamic>?;
      if (throws != null) {
        _opponentRoundThrows = throws.map((t) => t.toString()).toList();
      }
    }
    notifyListeners();
  }

  void _handleRoundReadyConfirm(dynamic data) {
    final eventMatchId = data['matchId'] as String?;
    if (eventMatchId != null && eventMatchId != _currentGameMatchId) return;
    // The server broadcasts this to the whole room — without this guard the
    // WAITING player's UI flipped into the confirm state on the opponent's
    // third dart (same guard GameProvider already had).
    if (!isMyTurn) return;
    _pendingConfirmation = true;
    notifyListeners();
  }

  void _handleRoundComplete(dynamic data) {
    final eventMatchId = data['matchId'] as String?;
    if (eventMatchId != null && eventMatchId != _currentGameMatchId) return;
    _dartsThrown = 0;
    _currentRoundThrows = [];
    _opponentRoundThrows = [];
    _dartsEmittedThisRound = 0;
    // Turn committed: settle all per-dart delivery state.
    _clearPendingDarts();
    _ackedDartsThisRound = 0;
    _confirmAttempts = 0;
    _confirmRejectedRetries = 0;
    _currentPlayerId = data['nextPlayerId'] as String?;
    _pendingConfirmation = false;
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    if (player1Score != null && player2Score != null) {
      _updateScoresFromPlayerScores(player1Score, player2Score);
    }
    notifyListeners();
  }

  void _handleGameWon(dynamic data) {
    if (_gameEnded) return;
    _winnerId = data['winnerId'] as String?;
    _gameEnded = true;
    // Don't set tournamentState here — wait for tournament_leg_won
    notifyListeners();
  }

  void _handleMatchEnded(dynamic data) {
    if (_gameEnded) return;
    _winnerId = data['winnerId'] as String?;
    _gameEnded = true;
    notifyListeners();
  }

  void _handleInvalidThrow(dynamic data) {
    if (_isForeignMatch(data)) return;
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    if (player1Score != null && player2Score != null) {
      _updateScoresFromPlayerScores(player1Score, player2Score);
    }
    // Bare invalid_throw ({message}) carries no state — don't null the turn
    // out from under the UI (see GameProvider).
    final serverCurrentPlayerId = data['currentPlayerId'] as String?;
    if (serverCurrentPlayerId != null) _currentPlayerId = serverCurrentPlayerId;
    final serverDartsThrown = data['dartsThrown'] as int?;
    if (serverDartsThrown != null) {
      _dartsThrown = serverDartsThrown;
      _currentRoundThrows = [];
      _dartsEmittedThisRound = 0;
      _ackedDartsThisRound = 0;
    }
    notifyListeners();
  }

  void _handleMustFinishDouble(dynamic data) {
    if (_isForeignMatch(data)) return;
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    if (player1Score != null && player2Score != null) {
      _updateScoresFromPlayerScores(player1Score, player2Score);
    }
    _currentPlayerId = data['currentPlayerId'] as String?;
    _dartsThrown = data['dartsThrown'] as int? ?? 0;
    _currentRoundThrows = [];
    _dartsEmittedThisRound = 0;
    notifyListeners();
  }

  void _handlePendingWin(dynamic data) {
    final playerId = data['playerId'] as String?;
    if (playerId != _myUserId) return;
    _pendingConfirmation = true;
    _pendingType = 'win';
    _pendingData = Map<String, dynamic>.from(data);
    notifyListeners();
  }

  void _handlePendingBust(dynamic data) {
    final playerId = data['playerId'] as String?;
    if (playerId != _myUserId) return;
    _pendingConfirmation = true;
    _pendingType = 'bust';
    _pendingReason = data['reason'] as String?;
    _pendingData = Map<String, dynamic>.from(data);
    notifyListeners();
  }

  void _handlePlayerForfeited(dynamic data) {
    final eventMatchId = data['matchId'] as String?;
    if (eventMatchId != _currentGameMatchId) return;
    _gameEnded = true;
    _winnerId = data['winnerId'] as String?;
    _pendingType = 'forfeit';
    _pendingData = Map<String, dynamic>.from(data);
    // If it's a tournament forfeit, the series ends
    if (data['isTournament'] == true) {
      _seriesWinnerId = _winnerId;
      _seriesLoserId = _winnerId == _myUserId ? _opponentUserId : _myUserId;
      _tournamentState = TournamentGameState.seriesEnded;
    }
    notifyListeners();
  }

  void _handleOpponentDisconnected(dynamic data) {
    final eventMatchId = data['matchId'] as String?;
    if (eventMatchId != _currentGameMatchId) return;
    // Ignore the event when it describes OUR OWN disconnection (server
    // broadcasts to the whole room; our reconnected socket receives it about
    // ourselves after a flap). See game_provider for the full rationale.
    final disconnectedPlayerId = data['disconnectedPlayerId'] as String?;
    if (disconnectedPlayerId != null && disconnectedPlayerId == _myUserId) {
      return;
    }
    _opponentDisconnected = true;
    final gracePeriodMs = data['gracePeriodMs'] as int? ?? 300000;
    _disconnectGraceSeconds = (gracePeriodMs / 1000).round();
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _disconnectGraceSeconds--;
      if (_disconnectGraceSeconds <= 0) timer.cancel();
      notifyListeners();
    });
    notifyListeners();
  }

  void _handleOpponentReconnected(dynamic data) {
    final eventMatchId = data['matchId'] as String?;
    if (eventMatchId != _currentGameMatchId) return;
    _opponentDisconnected = false;
    _disconnectGraceSeconds = 0;
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = null;
    notifyListeners();
  }

  void _handleGameStateSync(dynamic data) {
    final eventMatchId = data['matchId'] as String?;
    if (eventMatchId != _currentGameMatchId && _currentGameMatchId != null) return;
    final player1Id = data['player1Id'] as String?;
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    final currentPlayerId = data['currentPlayerId'] as String?;
    final dartsThrown = data['dartsThrown'] as int?;
    final currentRoundThrows = data['currentRoundThrows'] as List<dynamic>?;

    if (player1Id != null) _player1Id = player1Id;
    if (currentPlayerId != null) _currentPlayerId = currentPlayerId;
    if (dartsThrown != null) _dartsThrown = dartsThrown;

    // Settle the pending-dart queue against the server's applied dart IDs
    // (see GameProvider).
    final serverDartIds = (data['currentRoundDartIds'] as List<dynamic>?)
        ?.map((e) => e?.toString())
        .toList();
    if (serverDartIds != null && _pendingDartAcks.isNotEmpty) {
      _pendingDartAcks.removeWhere((id, _) => serverDartIds.contains(id));
      if (_pendingDartAcks.isEmpty) {
        _dartRetryTimer?.cancel();
        _dartRetryTimer = null;
      }
    }

    if (currentRoundThrows != null) {
      // Why: see GameProvider._handleGameStateSync. Don't wipe locally-detected
      // darts when our throw_dart is still in flight to the server.
      final serverThrows = currentRoundThrows.map((t) => t.toString()).toList();
      if (!isMyTurn || serverThrows.length >= _currentRoundThrows.length) {
        _currentRoundThrows = serverThrows;
        _dartsEmittedThisRound = _currentRoundThrows.length;
        _ackedDartsThisRound = isMyTurn ? serverThrows.length : 0;
      } else {
        // Server holds FEWER darts than us: ours never arrived. They are
        // still un-acked in _pendingDartAcks — re-deliver instead of keeping
        // an unhealable phantom view (see GameProvider).
        _ackedDartsThisRound = serverThrows.length;
        final claimed = _ackedDartsThisRound + _pendingDartAcks.length;
        if (_dartsEmittedThisRound > claimed) {
          _dartsEmittedThisRound = claimed;
        }
      }
      if (_pendingDartAcks.isNotEmpty && isMyTurn) {
        _flushPendingDarts();
      }
    }
    if (player1Score != null && player2Score != null) {
      _updateScoresFromPlayerScores(player1Score, player2Score);
    }

    // Restore pending win/bust confirmation after a reconnect/heal (see
    // GameProvider for the full rationale).
    if (data is Map && data.containsKey('pendingState')) {
      final pendingState = data['pendingState'] as String?;
      final pendingPlayerId = data['pendingPlayerId'] as String?;
      if (pendingState != null && pendingPlayerId == _myUserId) {
        _pendingConfirmation = true;
        _pendingType = pendingState == 'pending_win' ? 'win' : 'bust';
        _pendingReason = data['pendingReason'] as String?;
        _pendingData ??= <String, dynamic>{};
      } else if (pendingState == null &&
          isMyTurn &&
          _dartsThrown >= 3 &&
          _pendingType == null) {
        _pendingConfirmation = true;
      }
    }

    final newAgoraAppId = data['agoraAppId'] as String?;
    final newAgoraToken = data['agoraToken'] as String?;
    final newAgoraTokenStrict = data['agoraTokenStrict'] as String?;
    final newAgoraChannelName = data['agoraChannelName'] as String?;
    final newAgoraUid = (data['agoraUid'] as num?)?.toInt();
    final newOpponentAgoraUid = (data['opponentAgoraUid'] as num?)?.toInt();
    if (newAgoraAppId != null && newAgoraAppId.isNotEmpty &&
        newAgoraToken != null && newAgoraToken.isNotEmpty &&
        newAgoraChannelName != null && newAgoraChannelName.isNotEmpty) {
      _agoraAppId = newAgoraAppId;
      _agoraToken = newAgoraToken;
      _agoraChannelName = newAgoraChannelName;
      _needsAgoraReconnect = true;
    }
    if (newAgoraTokenStrict != null && newAgoraTokenStrict.isNotEmpty) {
      _agoraTokenStrict = newAgoraTokenStrict;
    }
    if (newAgoraUid != null) _agoraUid = newAgoraUid;
    if (newOpponentAgoraUid != null) {
      _opponentAgoraUid = newOpponentAgoraUid;
      if (hasStrictAgoraCredentials) {
        _remoteUid = newOpponentAgoraUid;
      }
    }

    _gameStarted = true;
    _tournamentState = TournamentGameState.playing;
    notifyListeners();
  }

  void _handleDartUndone(dynamic data) {
    if (_isForeignMatch(data)) return;
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    if (player1Score != null && player2Score != null) {
      _updateScoresFromPlayerScores(player1Score, player2Score);
    }
    _dartsThrown = data['dartsThrown'] as int? ?? _dartsThrown;
    final throws = data['currentRoundThrows'] as List<dynamic>?;
    if (throws != null) {
      _currentRoundThrows = throws.map((t) => t.toString()).toList();
      _ackedDartsThisRound = _currentRoundThrows.length;
      _dartsEmittedThisRound = _ackedDartsThisRound + _pendingDartAcks.length;
    }
    _pendingConfirmation = false;
    _pendingType = null;
    _pendingReason = null;
    _pendingData = null;
    notifyListeners();
  }

  // --- Tournament-specific event handlers ---

  void _handleTournamentLegWon(dynamic data) {
    debugPrint('TOURNAMENT: tournament_leg_won received: $data');
    _player1LegsWon = data['player1LegsWon'] as int? ?? _player1LegsWon;
    _player2LegsWon = data['player2LegsWon'] as int? ?? _player2LegsWon;
    _legsNeeded = data['legsNeeded'] as int? ?? _legsNeeded;
    _legWinnerId = data['legWinnerId'] as String?;
    _tournamentState = TournamentGameState.legEnded;
    notifyListeners();
  }

  void _handleTournamentNextLeg(dynamic data) {
    debugPrint('TOURNAMENT: tournament_next_leg received: $data');
    final newMatchId = data['newMatchId'] as String?;
    _currentLeg = data['legNumber'] as int? ?? _currentLeg + 1;
    _player1LegsWon = data['player1LegsWon'] as int? ?? _player1LegsWon;
    _player2LegsWon = data['player2LegsWon'] as int? ?? _player2LegsWon;

    // Keep player1Id in sync if server sends it (should stay the same across legs)
    final serverPlayer1Id = data['player1Id'] as String?;
    if (serverPlayer1Id != null) _player1Id = serverPlayer1Id;

    if (newMatchId != null) {
      _currentGameMatchId = newMatchId;
    }

    // Update Agora tokens for next leg video call
    final newAgoraAppId = data['agoraAppId'] as String?;
    final newAgoraToken = data['agoraToken'] as String?;
    final newAgoraTokenStrict = data['agoraTokenStrict'] as String?;
    final newAgoraChannelName = data['agoraChannelName'] as String?;
    final newAgoraUid = (data['agoraUid'] as num?)?.toInt();
    final newOpponentAgoraUid = (data['opponentAgoraUid'] as num?)?.toInt();
    if (newAgoraAppId != null && newAgoraAppId.isNotEmpty &&
        newAgoraToken != null && newAgoraToken.isNotEmpty &&
        newAgoraChannelName != null && newAgoraChannelName.isNotEmpty) {
      _agoraAppId = newAgoraAppId;
      _agoraToken = newAgoraToken;
      _agoraChannelName = newAgoraChannelName;
      _needsAgoraReconnect = true;
    }
    if (newAgoraTokenStrict != null && newAgoraTokenStrict.isNotEmpty) {
      _agoraTokenStrict = newAgoraTokenStrict;
    }
    if (newAgoraUid != null) _agoraUid = newAgoraUid;
    if (newOpponentAgoraUid != null) {
      _opponentAgoraUid = newOpponentAgoraUid;
      if (hasStrictAgoraCredentials) {
        _remoteUid = newOpponentAgoraUid;
      }
    }

    // Reset leg state for next leg
    _resetLegState();
    _tournamentState = TournamentGameState.playing;
    notifyListeners();
  }

  void _handleTournamentMatchWon(dynamic data) {
    debugPrint('TOURNAMENT: tournament_match_won received: $data');
    _seriesWinnerId = data['winnerId'] as String?;
    _seriesLoserId = data['loserId'] as String?;
    _player1LegsWon = data['player1LegsWon'] as int? ?? _player1LegsWon;
    _player2LegsWon = data['player2LegsWon'] as int? ?? _player2LegsWon;
    _tournamentState = TournamentGameState.seriesEnded;
    notifyListeners();
  }

  // --- Actions ---

  void confirmRound() {
    if (_gameEnded || _currentGameMatchId == null) return;

    final tracked = SocketService.supportsDartAck;

    // Never commit a turn while a dart is still in flight (see GameProvider).
    // Pointless against a legacy backend, which never acks.
    if (tracked && _pendingDartAcks.isNotEmpty && _confirmAttempts < 5) {
      _confirmAttempts++;
      _flushPendingDarts();
      Timer(const Duration(milliseconds: 800), () {
        if (!_disposed && !_gameEnded && isMyTurn) confirmRound();
      });
      return;
    }
    _confirmAttempts = 0;

    final payload = <String, dynamic>{
      'matchId': _currentGameMatchId,
      'playerId': _myUserId,
    };
    if (tracked) {
      payload['dartCount'] =
          _currentRoundThrows.where((t) => t.isNotEmpty).length.clamp(0, 3);
    }
    try {
      SocketService.emit(
        _currentRoundThrows.length < 3 ? 'end_round_early' : 'confirm_round',
        payload,
      );
    } catch (e) {
      debugPrint('TournamentGameProvider: confirmRound failed: $e');
    }
  }

  String _nextDartId() {
    final user = (_myUserId ?? 'u').replaceAll('-', '');
    final prefix = user.length >= 8 ? user.substring(0, 8) : user;
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 't$prefix$stamp${_dartIdSeq++}';
  }

  /// Delivery-tracked throw_dart (see GameProvider._emitDartWithTracking).
  void _emitDartWithTracking(Map<String, dynamic> payload) {
    final dartId = _nextDartId();
    payload['dartId'] = dartId;
    _pendingDartAcks[dartId] = payload;
    try {
      SocketService.emit('throw_dart', payload);
    } catch (e) {
      debugPrint('TournamentGameProvider: throw_dart queued for retry: $e');
    }
    _dartRetryTimer ??=
        Timer.periodic(const Duration(seconds: 2), (_) => _flushPendingDarts());
  }

  void _flushPendingDarts() {
    if (!SocketService.supportsDartAck) {
      // A server that can't dedup would score the re-sent dart again.
      _dartRetryTimer?.cancel();
      _dartRetryTimer = null;
      return;
    }
    if (_pendingDartAcks.isEmpty) {
      _dartRetryTimer?.cancel();
      _dartRetryTimer = null;
      return;
    }
    final entries = _pendingDartAcks.values.toList()
      ..sort((a, b) =>
          ((a['dartIndex'] as int?) ?? 0).compareTo((b['dartIndex'] as int?) ?? 0));
    for (final payload in entries) {
      try {
        SocketService.emit('throw_dart', payload);
      } catch (_) {
        break;
      }
    }
  }

  void _clearPendingDarts() {
    _pendingDartAcks.clear();
    _dartRetryTimer?.cancel();
    _dartRetryTimer = null;
  }

  void _handleThrowDartAck(dynamic data) {
    if (data is! Map) return;
    final eventMatchId = data['matchId'] as String?;
    if (eventMatchId != null &&
        _currentGameMatchId != null &&
        eventMatchId != _currentGameMatchId) {
      return;
    }
    final dartId = data['dartId'] as String?;
    if (dartId == null) return;
    final wasPending = _pendingDartAcks.remove(dartId) != null;

    if (data['applied'] == true) {
      final appliedIndex = data['appliedIndex'] as int?;
      if (appliedIndex != null && appliedIndex + 1 > _ackedDartsThisRound) {
        _ackedDartsThisRound = appliedIndex + 1;
      }
    } else if (wasPending) {
      final claimed = _ackedDartsThisRound + _pendingDartAcks.length;
      if (_dartsEmittedThisRound > claimed) {
        _dartsEmittedThisRound = claimed;
      }
      debugPrint(
          'TournamentGameProvider: dart $dartId rejected (${data['reason']})');
    }

    if (_pendingDartAcks.isEmpty) {
      _dartRetryTimer?.cancel();
      _dartRetryTimer = null;
    }
    notifyListeners();
  }

  void _handleConfirmRoundRejected(dynamic data) {
    if (data is! Map) return;
    final eventMatchId = data['matchId'] as String?;
    if (eventMatchId != null &&
        _currentGameMatchId != null &&
        eventMatchId != _currentGameMatchId) {
      return;
    }
    debugPrint(
        'TournamentGameProvider: confirm rejected — server=${data['serverDartsThrown']} client=${data['clientDartCount']}');
    _flushPendingDarts();
    if (_confirmRejectedRetries < 3) {
      _confirmRejectedRetries++;
      Timer(const Duration(milliseconds: 900), () {
        if (!_disposed && !_gameEnded && isMyTurn) confirmRound();
      });
    }
    notifyListeners();
  }

  void cancelConfirmation() {
    if (_pendingConfirmation) {
      _pendingConfirmation = false;
      notifyListeners();
    }
  }

  void confirmWin() {
    if (_pendingType != 'win') return;
    try {
      SocketService.emit('confirm_win', {
        'matchId': _currentGameMatchId,
        'playerId': _myUserId,
      });
    } catch (e) {
      debugPrint('TournamentGameProvider: confirmWin failed: $e');
    }
    _clearPendingState();
  }

  void confirmBust() {
    if (_pendingType != 'bust') return;
    try {
      SocketService.emit('confirm_bust', {
        'matchId': _currentGameMatchId,
        'playerId': _myUserId,
      });
    } catch (e) {
      debugPrint('TournamentGameProvider: confirmBust failed: $e');
    }
    _clearPendingState();
  }

  void _clearPendingState() {
    _pendingConfirmation = false;
    _pendingType = null;
    _pendingReason = null;
    _pendingData = null;
    notifyListeners();
  }

  Future<void> throwDart({
    required int baseScore,
    required ScoreMultiplier multiplier,
    // 'ai' when proposed by on-device auto-scoring, 'manual' when typed. Feeds
    // the backend trust factor. Optional field; old backends just ignore it.
    String source = 'manual',
  }) async {
    if (!isMyTurn || _dartsEmittedThisRound >= 3 || _gameEnded) return;

    final isDouble = multiplier == ScoreMultiplier.double;
    final isTriple = multiplier == ScoreMultiplier.triple;
    final payload = <String, dynamic>{
      'matchId': _currentGameMatchId,
      'playerId': _myUserId,
      'baseScore': baseScore,
      'isDouble': isDouble,
      'isTriple': isTriple,
      'source': source,
    };

    if (!SocketService.supportsDartAck) {
      // Legacy backend: never track or retry — it would score the dart twice.
      _dartsEmittedThisRound++;
      try {
        SocketService.emit('throw_dart', payload);
      } catch (_) {
        _dartsEmittedThisRound--;
      }
      return;
    }

    payload['dartIndex'] = _dartsEmittedThisRound;
    _emitDartWithTracking(payload);
    _dartsEmittedThisRound++;
  }

  void editDartThrow(int index, int baseScore, ScoreMultiplier multiplier) {
    if (index < 0 || index > 2) return;
    final notation = _getScoreNotation(baseScore, multiplier);
    // Grow list if server hasn't echoed back yet (race between AI detection and score_updated)
    while (_currentRoundThrows.length <= index) {
      _currentRoundThrows.add('');
    }
    _currentRoundThrows[index] = notation;
    final isDouble = multiplier == ScoreMultiplier.double;
    final isTriple = multiplier == ScoreMultiplier.triple;
    // If this slot was never thrown to the backend, emit throw_dart instead of edit_dart
    try {
      if (index >= _dartsEmittedThisRound) {
        // Delivery-tracked; the server verifies dartIndex so a gap-fill can't
        // silently record the dart at the wrong position (see GameProvider).
        final payload = <String, dynamic>{
          'matchId': _currentGameMatchId,
          'playerId': _myUserId,
          'baseScore': baseScore,
          'isDouble': isDouble,
          'isTriple': isTriple,
          'source': 'manual',
        };
        if (SocketService.supportsDartAck) {
          payload['dartIndex'] = index;
          _emitDartWithTracking(payload);
        } else {
          SocketService.emit('throw_dart', payload);
        }
        _dartsEmittedThisRound = index + 1;
      } else {
        SocketService.emit('edit_dart', {
          'matchId': _currentGameMatchId,
          'playerId': _myUserId,
          'dartIndex': index,
          'baseScore': baseScore,
          'isDouble': isDouble,
          'isTriple': isTriple,
        });
      }
    } catch (e) {
      // A dead socket used to throw out of this UI callback with the guard
      // already inflated; now it's logged and the tracked dart is retried.
      debugPrint('TournamentGameProvider: editDartThrow emit failed: $e');
    }
    notifyListeners();
  }

  void undoLastDart() {
    // Cancel an in-flight dart instead of undoing an applied one — the server
    // hasn't applied it yet, so undo_last_dart would pop the wrong dart (see
    // GameProvider for the reconciliation story).
    if (_pendingDartAcks.isNotEmpty) {
      String? newestId;
      var newestIndex = -1;
      _pendingDartAcks.forEach((id, payload) {
        final idx = (payload['dartIndex'] as int?) ?? 0;
        if (idx > newestIndex) {
          newestIndex = idx;
          newestId = id;
        }
      });
      if (newestId != null) _pendingDartAcks.remove(newestId);
      if (_pendingDartAcks.isEmpty) {
        _dartRetryTimer?.cancel();
        _dartRetryTimer = null;
      }
    } else {
      try {
        SocketService.emit('undo_last_dart', {
          'matchId': _currentGameMatchId,
          'playerId': _myUserId,
        });
      } catch (e) {
        debugPrint('TournamentGameProvider: undoLastDart failed: $e');
      }
    }
    // Decrement local guard (server will sync actual state via dart_undone)
    if (_dartsEmittedThisRound > 0) {
      _dartsEmittedThisRound--;
    }
    _pendingConfirmation = false;
    _pendingType = null;
    _pendingReason = null;
    _pendingData = null;
    notifyListeners();
  }

  /// Undo all darts thrown this round (used when editing to avoid negative scores)
  void undoAllDarts() {
    // Only server-applied darts need an undo each; in-flight darts are simply
    // cancelled (see GameProvider).
    _clearPendingDarts();
    var applied = _ackedDartsThisRound > _currentRoundThrows.length
        ? _ackedDartsThisRound
        : _currentRoundThrows.where((t) => t.isNotEmpty).length;
    while (applied > 0) {
      try {
        SocketService.emit('undo_last_dart', {
          'matchId': _currentGameMatchId,
          'playerId': _myUserId,
        });
      } catch (e) {
        debugPrint('TournamentGameProvider: undoAllDarts failed: $e');
      }
      applied--;
    }
    _dartsEmittedThisRound = 0;
    _ackedDartsThisRound = 0;
    _currentRoundThrows.clear();
    _pendingConfirmation = false;
    _pendingType = null;
    _pendingReason = null;
    _pendingData = null;
    notifyListeners();
  }

  void reconnectToMatch() {
    if (_currentGameMatchId != null && _myUserId != null) {
      try {
        SocketService.emit('reconnect_to_match', {
          'matchId': _currentGameMatchId,
          'userId': _myUserId,
        });
      } catch (_) {}
    }
  }

  // --- Helpers ---

  String _getScoreNotation(int baseScore, ScoreMultiplier multiplier) {
    final prefix = multiplier == ScoreMultiplier.single
        ? 'S'
        : multiplier == ScoreMultiplier.double
            ? 'D'
            : 'T';
    return '$prefix$baseScore';
  }

  void _updateScoresFromPlayerScores(int player1Score, int player2Score) {
    final isPlayer1 = _myUserId == _player1Id;
    if (isPlayer1) {
      _myScore = player1Score;
      _opponentScore = player2Score;
    } else {
      _myScore = player2Score;
      _opponentScore = player1Score;
    }
  }

  // Agora helpers
  void setRemoteUser(int? uid) {
    _remoteUid = uid;
    notifyListeners();
  }

  void setLocalUserJoined(bool joined) {
    _localUserJoined = joined;
    notifyListeners();
  }

  void clearAgoraReconnectFlag() {
    _needsAgoraReconnect = false;
  }

  // --- Cleanup ---

  void _cleanupSocketListeners() {
    if (_connectionListenersRegistered) {
      _connectionListenersRegistered = false;
      SocketService.removeDisconnectListener(_handleSelfDisconnected);
      SocketService.removeReconnectListener(_handleSelfReconnected);
    }
    SocketService.off('game_started');
    SocketService.off('score_updated');
    SocketService.off('round_ready_confirm');
    SocketService.off('round_complete');
    SocketService.off('game_won');
    SocketService.off('match_ended');
    SocketService.off('invalid_throw');
    SocketService.off('must_finish_double');
    SocketService.off('pending_win');
    SocketService.off('pending_bust');
    SocketService.off('player_forfeited');
    SocketService.off('dart_undone');
    SocketService.off('opponent_disconnected');
    SocketService.off('opponent_reconnected');
    SocketService.off('game_state_sync');
    SocketService.off('tournament_leg_won');
    SocketService.off('tournament_next_leg');
    SocketService.off('tournament_match_won');
    SocketService.off('throw_dart_ack');
    SocketService.off('confirm_round_rejected');
  }

  void reset() {
    _cleanupSocketListeners();
    _tournamentMatchId = null;
    _currentGameMatchId = null;
    _tournamentId = null;
    _roundName = null;
    _bestOf = 1;
    _myUserId = null;
    _opponentUserId = null;
    _player1Id = null;
    _myScore = 501;
    _opponentScore = 501;
    _currentPlayerId = null;
    _dartsThrown = 0;
    _gameStarted = false;
    _gameEnded = false;
    _winnerId = null;
    _lastThrow = null;
    _currentRoundThrows = [];
    _clearPendingDarts();
    _ackedDartsThisRound = 0;
    _confirmAttempts = 0;
    _confirmRejectedRetries = 0;
    _listenersSetUp = false;
    _pendingConfirmation = false;
    _pendingType = null;
    _pendingReason = null;
    _pendingData = null;
    _opponentDisconnected = false;
    _disconnectGraceSeconds = 0;
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = null;
    _cancelSelfDisconnectCountdown();
    _player1LegsWon = 0;
    _player2LegsWon = 0;
    _currentLeg = 1;
    _legsNeeded = 1;
    _legWinnerId = null;
    _seriesWinnerId = null;
    _seriesLoserId = null;
    _tournamentState = TournamentGameState.waiting;
    _agoraAppId = null;
    _agoraToken = null;
    _agoraTokenStrict = null;
    _agoraChannelName = null;
    _agoraUid = null;
    _opponentAgoraUid = null;
    _remoteUid = null;
    _localUserJoined = false;
    _needsAgoraReconnect = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cleanupSocketListeners();
    _clearPendingDarts();
    _disconnectCountdownTimer?.cancel();
    _selfDisconnectCountdownTimer?.cancel();
    super.dispose();
  }
}

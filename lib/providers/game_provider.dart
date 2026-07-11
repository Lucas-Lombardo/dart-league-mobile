import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/socket_service.dart';

enum ScoreMultiplier { single, double, triple }

class GameProvider with ChangeNotifier {
  String? _matchId;
  int _myScore = 501;
  int _opponentScore = 501;
  String? _currentPlayerId;
  String? _myUserId;
  String? _opponentUserId;
  String? _player1Id; // Track which userId is player1 for score mapping
  String? _firstThrowerId; // Whoever threw first in the match (set once)
  int _dartsThrown = 0;
  bool _gameStarted = false;
  bool _gameEnded = false;
  String? _winnerId;
  String? _lastThrow;
  List<String> _currentRoundThrows = [];
  List<String> _opponentRoundThrows = [];
  List<int> _myRounds = [];
  List<int> _opponentRounds = [];
  int _dartsEmittedThisRound = 0; // Local guard for rapid throws before server ack
  // Per-dart delivery tracking. Every throw_dart carries a client-generated
  // dartId; the server acks it with throw_dart_ack and dedups retries, so a
  // dart lost on a dying socket is re-sent instead of silently disappearing
  // (the "threw 26, scored 21" bug). Keyed by dartId → the exact payload to
  // re-emit. A dart leaves the map only when acked or the round ends.
  final Map<String, Map<String, dynamic>> _pendingDartAcks = {};
  Timer? _dartRetryTimer;
  int _dartIdSeq = 0;
  int _ackedDartsThisRound = 0; // darts the server confirmed applied this round
  int _confirmAttempts = 0;
  int _confirmRejectedRetries = 0;
  bool _listenersSetUp = false;
  bool _pendingConfirmation = false;
  String? _pendingType; // 'win' or 'bust'
  String? _pendingReason;
  Map<String, dynamic>? _pendingData;
  bool _opponentDisconnected = false;
  int _disconnectGraceSeconds = 0;
  Timer? _disconnectCountdownTimer;
  bool _reconnectFailed = false;
  String? _reconnectFailedReason;

  // Our OWN connection state. Mirrors the server's 5-minute disconnect grace
  // period so the player sees the same countdown their opponent sees instead
  // of silently playing into a dead socket.
  static const int _selfGracePeriodSeconds = 300;
  bool _selfDisconnected = false;
  int _selfDisconnectGraceSeconds = 0;
  Timer? _selfDisconnectCountdownTimer;
  bool _connectionListenersRegistered = false;

  // Friendly (friend-invite) match + "play again" rematch state.
  bool _isFriendly = false;
  bool _rematchWaiting = false;
  bool _rematchDeclined = false;
  bool _opponentWantsRematch = false;

  // Ranked BO3 series state (mirrors TournamentGameProvider's legs/series
  // machinery). All defaults describe a classic BO1 match: _seriesId stays
  // null, so isRankedSeries == false and nothing below is consulted. The
  // fields are fed by game_started / game_state_sync (seriesId, legNumber,
  // legs won…) and by the ranked_leg_won / ranked_next_leg / ranked_match_won
  // events. In a series, _gameEnded means "the LEG ended"; only _seriesEnded
  // means the match is truly over (ELO applied, accept-result available).
  String? _seriesId;
  int _bestOf = 1;
  int _player1LegsWon = 0;
  int _player2LegsWon = 0;
  int _currentLeg = 1;
  int _legsNeeded = 1;
  String? _legWinnerId;
  String? _seriesWinnerId;
  bool _seriesEnded = false;
  Map<String, dynamic>? _seriesResultData;
  
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

  bool _disposed = false;

  GameProvider();

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void ensureListenersSetup() {
    if (_listenersSetUp) {
      return;
    }
    
    _setupSocketListeners();
    _listenersSetUp = true;
  }

  String? get matchId => _matchId;
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
  List<String> get currentRoundThrows => List.unmodifiable(_currentRoundThrows);
  List<String> get opponentRoundThrows => List.unmodifiable(_opponentRoundThrows);
  List<int> get myRounds => List.unmodifiable(_myRounds);
  List<int> get opponentRounds => List.unmodifiable(_opponentRounds);
  double get myAveragePerRound => _myRounds.isEmpty ? 0.0 : _myRounds.reduce((a, b) => a + b) / _myRounds.length;
  double get opponentAveragePerRound => _opponentRounds.isEmpty ? 0.0 : _opponentRounds.reduce((a, b) => a + b) / _opponentRounds.length;
  bool get pendingConfirmation => _pendingConfirmation;
  String? get pendingType => _pendingType;
  String? get pendingReason => _pendingReason;
  Map<String, dynamic>? get pendingData => _pendingData;
  bool get opponentDisconnected => _opponentDisconnected;
  int get disconnectGraceSeconds => _disconnectGraceSeconds;
  bool get selfDisconnected => _selfDisconnected;
  int get selfDisconnectGraceSeconds => _selfDisconnectGraceSeconds;
  bool get reconnectFailed => _reconnectFailed;
  String? get reconnectFailedReason => _reconnectFailedReason;

  // Friendly match + rematch getters.
  bool get isFriendly => _isFriendly;
  bool get rematchWaiting => _rematchWaiting;
  bool get rematchDeclined => _rematchDeclined;
  bool get opponentWantsRematch => _opponentWantsRematch;

  // Ranked BO3 series getters.
  bool get isRankedSeries => _seriesId != null;
  String? get seriesId => _seriesId;
  int get bestOf => _bestOf;
  int get player1LegsWon => _player1LegsWon;
  int get player2LegsWon => _player2LegsWon;
  int get currentLeg => _currentLeg;
  int get legsNeeded => _legsNeeded;
  String? get legWinnerId => _legWinnerId;
  String? get seriesWinnerId => _seriesWinnerId;
  bool get seriesEnded => _seriesEnded;
  Map<String, dynamic>? get seriesResultData => _seriesResultData;
  int get myLegsWon =>
      _myUserId == _player1Id ? _player1LegsWon : _player2LegsWon;
  int get opponentLegsWon =>
      _myUserId == _player1Id ? _player2LegsWon : _player1LegsWon;

  /// The match is truly over: for BO1 that's the (only) leg ending, for a BO3
  /// series it's the series being decided (checkout, forfeit or timeout).
  bool get matchOver => isRankedSeries ? _seriesEnded : _gameEnded;
  
  // Agora getters
  String? get agoraAppId => _agoraAppId;
  String? get agoraToken => _agoraToken;
  String? get agoraTokenStrict => _agoraTokenStrict;
  String? get agoraChannelName => _agoraChannelName;
  int? get agoraUid => _agoraUid;
  int? get opponentAgoraUid => _opponentAgoraUid;
  int? get remoteUid => _remoteUid;
  bool get localUserJoined => _localUserJoined;
  bool get needsAgoraReconnect => _needsAgoraReconnect;

  /// Whether we have everything needed to use the strict (uid-bound) token.
  /// When false, callers should fall back to the legacy token + uid=0 so we
  /// stay compatible with backends that don't yet emit agoraTokenStrict.
  bool get hasStrictAgoraCredentials =>
      _agoraTokenStrict != null && _agoraTokenStrict!.isNotEmpty && _agoraUid != null && _agoraUid != 0;

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
  
  void setScore(int newScore) {
    _myScore = newScore;
    notifyListeners();
  }

  void updatePlacementScores(int myScore, int opponentScore) {
    _myScore = myScore;
    _opponentScore = opponentScore;
    notifyListeners();
  }
  
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

  void initGame(String matchId, String myUserId, String opponentUserId, {
    String? agoraAppId,
    String? agoraToken,
    String? agoraTokenStrict,
    String? agoraChannelName,
    int? agoraUid,
    int? opponentAgoraUid,
  }) {
    debugPrint('GAME DEBUG: initGame called - matchId=$matchId, myUserId=$myUserId, currentMatchId=$_matchId');

    // If this is a NEW match (different matchId), always do a full reset
    // Only preserve state if same matchId (reconnection scenario)
    final isNewMatch = _matchId != matchId;

    _matchId = matchId;
    _myUserId = myUserId;
    _opponentUserId = opponentUserId;

    // Store Agora credentials if provided
    if (agoraAppId != null) _agoraAppId = agoraAppId;
    if (agoraToken != null) _agoraToken = agoraToken;
    if (agoraTokenStrict != null) _agoraTokenStrict = agoraTokenStrict;
    if (agoraChannelName != null) _agoraChannelName = agoraChannelName;
    if (agoraUid != null) _agoraUid = agoraUid;
    if (opponentAgoraUid != null) {
      _opponentAgoraUid = opponentAgoraUid;
      // Pre-set remoteUid ONLY when we'll be joining with the strict
      // (deterministic) UID ourselves. Otherwise we're on the legacy path
      // (uid=0 → Agora-assigned uid) and the opponent's runtime uid will
      // also be Agora-assigned, so pre-setting the deterministic value here
      // would create a black tile until onUserJoined corrects it. We let
      // onUserJoined drive it in that case.
      if (agoraTokenStrict != null && agoraTokenStrict.isNotEmpty && agoraUid != null && agoraUid != 0) {
        _remoteUid = opponentAgoraUid;
      }
    }
    
    if (isNewMatch || !_gameStarted) {
      debugPrint('GAME DEBUG: initGame - resetting scores (isNewMatch=$isNewMatch, gameStarted=$_gameStarted)');
      _myScore = 501;
      _opponentScore = 501;
      _dartsThrown = 0;
      _gameEnded = false;
      _winnerId = null;
      _lastThrow = null;
      _currentRoundThrows = [];
      _opponentRoundThrows = [];
      _myRounds = [];
      _opponentRounds = [];
      _dartsEmittedThisRound = 0;
      _clearPendingDarts();
      _ackedDartsThisRound = 0;
      _confirmAttempts = 0;
      _confirmRejectedRetries = 0;
      _pendingConfirmation = false;
      _pendingType = null;
      _pendingReason = null;
      _pendingData = null;
      _player1Id = null; // Reset so game_started sets it correctly for the new match
      _firstThrowerId = null; // Reset so the first thrower is captured anew for this match
      _rematchWaiting = false;
      _rematchDeclined = false;
      _opponentWantsRematch = false;
      // Series state belongs to the previous series; a BO3 context for THIS
      // match is re-established by game_started/game_state_sync. Same race as
      // _gameStarted below: game_started may have ALREADY fired for this match
      // (and set the series fields) before initGame runs — don't wipe them.
      if (!_gameStarted) _resetSeriesState();
      // Don't reset _gameStarted — game_started event may have already fired for this match
    } else {
      debugPrint('GAME DEBUG: initGame - preserving state (same match reconnection)');
    }
    
    debugPrint('GAME DEBUG: initGame state AFTER - gameStarted=$_gameStarted, gameEnded=$_gameEnded, winnerId=$_winnerId, myScore=$_myScore');
    notifyListeners();
  }

  void _setupSocketListeners() {
    SocketService.on('game_started', (data) {
      _handleGameStarted(data);
    });

    SocketService.on('score_updated', (data) {
      _handleScoreUpdated(data);
    });

    SocketService.on('round_ready_confirm', (data) {
      _handleRoundReadyConfirm(data);
    });

    SocketService.on('round_complete', (data) {
      _handleRoundComplete(data);
    });

    SocketService.on('game_won', (data) {
      _handleGameWon(data);
    });

    SocketService.on('match_ended', (data) {
      _handleMatchEnded(data);
    });

    SocketService.on('invalid_throw', (data) {
      _handleInvalidThrow(data);
    });

    SocketService.on('must_finish_double', (data) {
      _handleMustFinishDouble(data);
    });

    SocketService.on('pending_win', (data) {
      _handlePendingWin(data);
    });

    SocketService.on('pending_bust', (data) {
      _handlePendingBust(data);
    });

    SocketService.on('opponent_disconnected', (data) {
      _handleOpponentDisconnected(data);
    });

    SocketService.on('opponent_reconnected', (data) {
      _handleOpponentReconnected(data);
    });

    SocketService.on('game_state_sync', (data) {
      _handleGameStateSync(data);
    });

    SocketService.on('player_forfeited', (data) {
      _handlePlayerForfeited(data);
    });

    SocketService.on('dart_undone', (data) {
      _handleDartUndone(data);
    });

    SocketService.on('reconnect_failed', (data) {
      _handleReconnectFailed(data);
    });

    SocketService.on('rematch_requested', (data) {
      _handleRematchRequested(data);
    });

    SocketService.on('rematch_declined', (data) {
      _handleRematchDeclined(data);
    });

    SocketService.on('throw_dart_ack', (data) {
      _handleThrowDartAck(data);
    });

    SocketService.on('confirm_round_rejected', (data) {
      _handleConfirmRoundRejected(data);
    });

    // Ranked BO3 series events (mirrors tournament_leg_won/next_leg/match_won).
    SocketService.on('ranked_leg_won', (data) {
      _handleRankedLegWon(data);
    });

    SocketService.on('ranked_next_leg', (data) {
      _handleRankedNextLeg(data);
    });

    SocketService.on('ranked_match_won', (data) {
      _handleRankedMatchWon(data);
    });

    // Observe our OWN connection so the player learns about a drop instead of
    // throwing darts into a dead socket. Uses the additive listener API so
    // matchmaking's single-slot reconnect handler is not clobbered.
    if (!_connectionListenersRegistered) {
      _connectionListenersRegistered = true;
      SocketService.addDisconnectListener(_handleSelfDisconnected);
      SocketService.addReconnectListener(_handleSelfReconnected);
    }
  }

  void _handleSelfDisconnected() {
    // Only meaningful mid-match; queue/lobby disconnects are handled elsewhere.
    if (_matchId == null || !_gameStarted || _gameEnded) return;

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
    _selfDisconnected = false;
    _selfDisconnectGraceSeconds = 0;
    _selfDisconnectCountdownTimer?.cancel();
    _selfDisconnectCountdownTimer = null;

    if (wasDisconnected && _matchId != null && !_gameEnded) {
      // Rejoin the match room and pull a fresh game_state_sync. The server
      // also does this automatically for brand-new connections, but after an
      // in-place socket.io reconnect this explicit message is what restores us.
      reconnectToMatch();
    }
    notifyListeners();
  }

  void _handleRematchRequested(dynamic data) {
    // The opponent tapped "play again" first — nudge this player.
    _opponentWantsRematch = true;
    notifyListeners();
  }

  void _handleRematchDeclined(dynamic data) {
    _rematchWaiting = false;
    _rematchDeclined = true;
    notifyListeners();
  }

  void _handleReconnectFailed(dynamic data) {
    // Why: previously the mobile had no handler for this server event, leaving
    // the player stuck on the game screen if they reconnected after the match
    // had already ended. We surface a flag so the screen can pop back to home
    // and the user knows what happened.
    final eventMatchId = data is Map ? data['matchId'] as String? : null;
    if (eventMatchId != null && _matchId != null && eventMatchId != _matchId) {
      return;
    }
    _reconnectFailed = true;
    _reconnectFailedReason = data is Map
        ? data['reason'] as String?
        : null;
    _gameEnded = true;
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = null;
    _cancelSelfDisconnectCountdown();
    notifyListeners();
  }

  void clearReconnectFailedFlag() {
    _reconnectFailed = false;
    _reconnectFailedReason = null;
  }

  void _handleGameStarted(dynamic data) {
    debugPrint('DEBUG: game_started received, myUserId=$_myUserId');
    // Heal a missed ranked_next_leg: game_started for the NEXT leg of OUR
    // series can arrive while _matchId still points at the finished leg
    // (reconnect inside the transition window). Adopt it — same series,
    // fresh leg — otherwise every throw targets the dead leg. Any other
    // matchId mismatch keeps the old behavior: game_started may legitimately
    // arrive before initGame in the new-match race, so no foreign guard here.
    if (data is Map) {
      final startedMatchId = data['matchId'] as String?;
      final startedSeriesId = data['seriesId'] as String?;
      if (startedMatchId != null &&
          _matchId != null &&
          startedMatchId != _matchId &&
          _seriesId != null &&
          startedSeriesId == _seriesId) {
        debugPrint('GAME DEBUG: game_started for next leg $startedMatchId of our series — adopting');
        _matchId = startedMatchId;
        _resetLegState();
      }
    }
    // The previous leg's winner is only useful on the between-legs screen;
    // clear it when the next leg actually starts (not in _resetLegState —
    // the between-legs screen still reads it after ranked_next_leg).
    _legWinnerId = null;
    _gameStarted = true;
    _currentPlayerId = data['currentPlayerId'] as String?;

    // Capture the first thrower for the match (stable for scoreboard
    // positioning across legs). Set once; never overwritten.
    _firstThrowerId ??= _currentPlayerId;

    // Use server-provided player1Id for correct score mapping.
    // player1Id is NOT necessarily whoever goes first — the server assigns
    // it based on join order and may alternate who starts between tournament legs.
    final serverPlayer1Id = data['player1Id'] as String?;
    if (serverPlayer1Id != null) {
      _player1Id = serverPlayer1Id;
    } else {
      // Why: the previous fallback (`_player1Id ??= _myUserId`) caused both
      // clients to self-identify as player1, which made score mapping disagree
      // between devices and surfaced as reversed scores in the scoreboard.
      // currentPlayerId is the same value on both devices, so deriving from it
      // keeps them in sync. It only matches player1Id for the first leg of a
      // match — in alternating tournament legs this can still be wrong, so the
      // server MUST send player1Id; this fallback is just defensive.
      debugPrint('WARNING: game_started missing player1Id; falling back to currentPlayerId');
      _player1Id ??= _currentPlayerId;
    }
    debugPrint('DEBUG: game_started - player1Id=$_player1Id, currentPlayerId=$_currentPlayerId, firstThrowerId=$_firstThrowerId');

    // Both players start at 501
    _myScore = 501;
    _opponentScore = 501;

    _applySeriesFields(data);

    notifyListeners();
  }

  /// Adopt the BO3 legs context the server attaches to game_started /
  /// game_state_sync payloads (absent for BO1 — every field is optional so an
  /// older backend changes nothing).
  void _applySeriesFields(dynamic data) {
    if (data is! Map) return;
    final seriesId = data['seriesId'] as String?;
    if (seriesId == null) return;
    // A NEW series must never inherit the previous one's end-state: the
    // game_started-before-initGame race skips initGame's guarded reset, and
    // a stale _seriesEnded=true would replace leg 1's between-legs screen
    // with the final accept-result screen.
    if (_seriesId != null && seriesId != _seriesId) {
      _resetSeriesState();
    }
    _seriesId = seriesId;
    _bestOf = data['bestOf'] as int? ?? _bestOf;
    _currentLeg = data['legNumber'] as int? ?? _currentLeg;
    _player1LegsWon = data['player1LegsWon'] as int? ?? _player1LegsWon;
    _player2LegsWon = data['player2LegsWon'] as int? ?? _player2LegsWon;
    _legsNeeded = data['legsNeeded'] as int? ?? _legsNeeded;
  }

  /// True when a series event carries a seriesId that isn't ours (late event
  /// from a previous series after a rematch/reset).
  bool _isForeignSeries(dynamic data) {
    if (data is! Map) return false;
    final eventSeriesId = data['seriesId'] as String?;
    return eventSeriesId != null &&
        _seriesId != null &&
        eventSeriesId != _seriesId;
  }

  /// True when an event belongs to a different match than the one we're in.
  /// Leg transitions and rematches reuse this provider, so a late event from
  /// the previous match would otherwise mutate the new match's scores/turn.
  bool _isForeignMatch(dynamic data) {
    if (data is! Map) return false;
    final eventMatchId = data['matchId'] as String?;
    return eventMatchId != null && _matchId != null && eventMatchId != _matchId;
  }

  void _handleScoreUpdated(dynamic data) {
    if (_isForeignMatch(data)) return;

    // Why: auto-resync the turn when round_complete was missed (e.g. brief
    // socket disconnect that left the client out of the room). The server
    // always includes currentPlayerId in score_updated payloads, so reading
    // it here gives us a self-healing path back to the authoritative turn.
    final serverCurrentPlayerId = data['currentPlayerId'] as String?;
    if (serverCurrentPlayerId != null && serverCurrentPlayerId != _currentPlayerId) {
      _currentPlayerId = serverCurrentPlayerId;
    }

    // Backend sends player1Score and player2Score directly
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;

    // Map scores correctly based on whether I'm player1 or player2
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
        // Keep the slot guard in sync with the server — but never let a
        // stale echo LOWER it below what is delivered or still in flight:
        // that used to free an occupied slot and let the same dart be
        // emitted twice (the dart-duplication bug).
        final claimed = _ackedDartsThisRound + _pendingDartAcks.length;
        final serverCount = _currentRoundThrows.length;
        _dartsEmittedThisRound =
            serverCount > claimed ? serverCount : claimed;
        if (serverCount > _ackedDartsThisRound) {
          // The echo proves these darts were applied even if an ack was lost.
          _ackedDartsThisRound = serverCount;
        }
      }
    }
    
    // Track opponent's throws during their turn
    // Only use currentRoundThrows as source of truth — never append _lastThrow
    // separately, as it causes duplicates when the server already sent
    // currentRoundThrows in the same or a previous score_updated payload.
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
    if (eventMatchId != null && eventMatchId != _matchId) return;
    // Only set pending confirmation when it's my turn — the server broadcasts
    // this event to all match participants, so we must ignore it when the
    // opponent is the one who just finished throwing.
    if (!isMyTurn) return;
    _pendingConfirmation = true;
    notifyListeners();
  }

  void _handleRoundComplete(dynamic data) {
    final eventMatchId = data['matchId'] as String?;
    if (eventMatchId != null && eventMatchId != _matchId) return;
    _dartsThrown = 0;
    _currentRoundThrows = [];
    _opponentRoundThrows = [];
    _dartsEmittedThisRound = 0;
    // The turn is committed: settle all per-dart delivery state. A dart still
    // pending here can no longer be applied (turn switched) — retrying it
    // would only produce rejections.
    _clearPendingDarts();
    _ackedDartsThisRound = 0;
    _confirmAttempts = 0;
    _confirmRejectedRetries = 0;
    _currentPlayerId = data['nextPlayerId'] as String?;
    _pendingConfirmation = false;
    
    // Backend sends player1Score and player2Score directly
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    
    if (player1Score != null && player2Score != null) {
      _updateScoresFromPlayerScores(player1Score, player2Score);
    }

    _updateRoundsFromData(data);

    notifyListeners();
  }

  void confirmRound() {
    if (_gameEnded || _matchId == null) return;

    final tracked = SocketService.supportsDartAck;

    // Never commit a turn while a dart is still in flight: flush the pending
    // queue and come back shortly. Without this, retrieving the darts used to
    // end the round with whatever subset the server had received. Meaningless
    // against a legacy backend, which never acks — waiting there would just
    // stall every turn by four seconds.
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
      'matchId': _matchId,
      'playerId': _myUserId,
    };
    if (tracked) {
      // Tell the server how many darts we believe this round holds; it refuses
      // to commit on a mismatch (confirm_round_rejected) instead of silently
      // recording a short visit.
      payload['dartCount'] =
          _currentRoundThrows.where((t) => t.isNotEmpty).length.clamp(0, 3);
    }
    try {
      SocketService.emit(
        _currentRoundThrows.length < 3 ? 'end_round_early' : 'confirm_round',
        payload,
      );
    } catch (e) {
      debugPrint('GameProvider: confirmRound failed: $e');
    }
  }
  
  /// Request a "play again" rematch for the just-finished friendly match.
  /// When the opponent also requests, the server starts a new friendly match
  /// (with the starter swapped) and a friendly_match_found event arrives.
  void requestRematch() {
    if (!_isFriendly || _matchId == null) return;
    _rematchWaiting = true;
    _rematchDeclined = false;
    notifyListeners();
    try {
      SocketService.emit('rematch_request', {'matchId': _matchId});
    } catch (e) {
      debugPrint('GameProvider: requestRematch failed: $e');
    }
  }

  /// Decline the rematch (releasing the opponent if they were waiting).
  void declineRematch() {
    if (_matchId == null) return;
    _rematchWaiting = false;
    try {
      SocketService.emit('rematch_decline', {'matchId': _matchId});
    } catch (e) {
      debugPrint('GameProvider: declineRematch failed: $e');
    }
  }

  void confirmWin() {
    if (_pendingType != 'win') return;
    try {
      SocketService.emit('confirm_win', {
        'matchId': _matchId,
        'playerId': _myUserId,
      });
    } catch (e) {
      debugPrint('GameProvider: confirmWin failed: $e');
    }
    // Clear pending state - backend will emit game_won
    _clearPendingState();
  }

  void confirmBust() {
    if (_pendingType != 'bust') return;
    try {
      SocketService.emit('confirm_bust', {
        'matchId': _matchId,
        'playerId': _myUserId,
      });
    } catch (e) {
      debugPrint('GameProvider: confirmBust failed: $e');
    }
    // Clear pending state - backend will emit round_complete
    _clearPendingState();
  }

  void _clearPendingState() {
    _pendingConfirmation = false;
    _pendingType = null;
    _pendingReason = null;
    _pendingData = null;
    notifyListeners();
  }

  void _handleGameWon(dynamic data) {
    debugPrint('GAME DEBUG: game_won received - winnerId=${data['winnerId']}, currentMatchId=$_matchId');

    // Prevent duplicate processing if game already ended
    if (_gameEnded) {
      debugPrint('GAME DEBUG: game_won IGNORED (already ended)');
      return;
    }

    _winnerId = data['winnerId'] as String?;
    _gameEnded = true;
    // Friendly matches end with a "play again" prompt instead of the ranked
    // accept-result / ELO flow.
    _isFriendly = data is Map && data['isFriendly'] == true;
    // BO3 leg win: the series goes on — ranked_leg_won updates the counts and
    // either ranked_next_leg or ranked_match_won decides what happens next.
    if (data is Map && data['isRankedSeries'] == true) {
      _seriesId ??= data['seriesId'] as String?;
      _legWinnerId = _winnerId;
    }
    _rematchWaiting = false;
    _rematchDeclined = false;
    _opponentWantsRematch = false;
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = null;
    _cancelSelfDisconnectCountdown();

    debugPrint('GAME DEBUG: game_won processed - gameEnded=$_gameEnded, winnerId=$_winnerId, isFriendly=$_isFriendly, isRankedSeries=$isRankedSeries');
    notifyListeners();
  }

  void _handleRankedLegWon(dynamic data) {
    if (data is! Map || _isForeignSeries(data)) return;
    debugPrint('GAME DEBUG: ranked_leg_won received: $data');
    _seriesId ??= data['seriesId'] as String?;
    _player1LegsWon = data['player1LegsWon'] as int? ?? _player1LegsWon;
    _player2LegsWon = data['player2LegsWon'] as int? ?? _player2LegsWon;
    _legsNeeded = data['legsNeeded'] as int? ?? _legsNeeded;
    _bestOf = data['bestOf'] as int? ?? _bestOf;
    _legWinnerId = data['legWinnerId'] as String? ?? _legWinnerId;
    notifyListeners();
  }

  void _handleRankedNextLeg(dynamic data) {
    if (data is! Map || _isForeignSeries(data)) return;
    debugPrint('GAME DEBUG: ranked_next_leg received: $data');
    final newMatchId = data['newMatchId'] as String?;
    _currentLeg = data['legNumber'] as int? ?? _currentLeg + 1;
    _player1LegsWon = data['player1LegsWon'] as int? ?? _player1LegsWon;
    _player2LegsWon = data['player2LegsWon'] as int? ?? _player2LegsWon;
    _legsNeeded = data['legsNeeded'] as int? ?? _legsNeeded;
    _bestOf = data['bestOf'] as int? ?? _bestOf;

    // player1Id is stable across legs, but keep in sync if the server sends it.
    final serverPlayer1Id = data['player1Id'] as String?;
    if (serverPlayer1Id != null) _player1Id = serverPlayer1Id;

    if (newMatchId != null) {
      _matchId = newMatchId;
    }

    // Each leg is a new Agora channel (channel name == leg matchId): adopt the
    // fresh tokens and ask the screen to re-key the call, exactly like the
    // tournament next-leg flow.
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

    _resetLegState();
    notifyListeners();
  }

  void _handleRankedMatchWon(dynamic data) {
    if (data is! Map || _isForeignSeries(data)) return;
    debugPrint('GAME DEBUG: ranked_match_won received: $data');
    _seriesId ??= data['seriesId'] as String?;
    _seriesWinnerId = data['winnerId'] as String? ?? _seriesWinnerId;
    _winnerId = _seriesWinnerId ?? _winnerId;
    _player1LegsWon = data['player1LegsWon'] as int? ?? _player1LegsWon;
    _player2LegsWon = data['player2LegsWon'] as int? ?? _player2LegsWon;
    _bestOf = data['bestOf'] as int? ?? _bestOf;
    _seriesResultData = Map<String, dynamic>.from(data);
    _seriesEnded = true;
    _gameEnded = true;
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = null;
    _cancelSelfDisconnectCountdown();
    notifyListeners();
  }

  /// Reset the per-leg state between BO3 legs, keeping identities, series
  /// counts and Agora bookkeeping (adapted from TournamentGameProvider —
  /// which has neither a rounds UI nor a disconnect banner, hence the extra
  /// fields here). _legWinnerId deliberately survives: the between-legs
  /// screen reads it; game_started clears it when the next leg begins.
  void _resetLegState() {
    _myScore = 501;
    _opponentScore = 501;
    _dartsThrown = 0;
    _gameEnded = false;
    _gameStarted = false;
    _winnerId = null;
    _lastThrow = null;
    _currentRoundThrows = [];
    _opponentRoundThrows = [];
    // Per-leg round history: without this, leg N+1 opened at "Round N+12"
    // with the previous leg's averages until the first round_complete.
    _myRounds = [];
    _opponentRounds = [];
    _dartsEmittedThisRound = 0;
    _clearPendingDarts();
    _ackedDartsThisRound = 0;
    _confirmAttempts = 0;
    _confirmRejectedRetries = 0;
    _pendingConfirmation = false;
    _pendingType = null;
    _pendingReason = null;
    _pendingData = null;
    // The opponent-disconnect banner is per-leg: opponent_reconnected for the
    // OLD leg's matchId is dropped by its guard, so a banner active at the
    // leg boundary would otherwise stay frozen for the rest of the series.
    _opponentDisconnected = false;
    _disconnectGraceSeconds = 0;
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = null;
  }

  void _resetSeriesState() {
    _seriesId = null;
    _bestOf = 1;
    _player1LegsWon = 0;
    _player2LegsWon = 0;
    _currentLeg = 1;
    _legsNeeded = 1;
    _legWinnerId = null;
    _seriesWinnerId = null;
    _seriesEnded = false;
    _seriesResultData = null;
  }

  void _handleMatchEnded(dynamic data) {
    // A series-ending match_ended may carry the NEXT leg's matchId (we missed
    // ranked_next_leg) — accept it when the seriesId is ours. Everything else
    // from a different match is foreign: a late match_ended from a previous
    // match must not pollute a freshly initialized provider.
    final isOurSeriesEnd = data is Map &&
        data['isRankedSeries'] == true &&
        _seriesId != null &&
        data['seriesId'] == _seriesId;
    if (_isForeignMatch(data) && !isOurSeriesEnd) return;

    // A BO3 timeout/disconnect/decision ends the whole series server-side;
    // the payload says so. Handle it even if the leg already ended locally
    // (_gameEnded), otherwise the client would wait forever for a next leg.
    if (isOurSeriesEnd) {
      _player1LegsWon = data['player1LegsWon'] as int? ?? _player1LegsWon;
      _player2LegsWon = data['player2LegsWon'] as int? ?? _player2LegsWon;
      _seriesWinnerId = data['winnerId'] as String? ?? _seriesWinnerId;
      // The end screen's verdict reads _winnerId. Without this, a client
      // whose last local event was losing a LEG showed DEFEAT to the actual
      // series winner (the _gameEnded guard below returns early).
      if (_seriesWinnerId != null) _winnerId = _seriesWinnerId;
      _seriesEnded = true;
      _disconnectCountdownTimer?.cancel();
      _disconnectCountdownTimer = null;
      _cancelSelfDisconnectCountdown();
    }

    // Prevent duplicate processing if game already ended
    if (_gameEnded) {
      notifyListeners();
      return;
    }

    _winnerId = data['winnerId'] as String?;
    _gameEnded = true;
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = null;
    _cancelSelfDisconnectCountdown();

    notifyListeners();
  }

  void _cancelSelfDisconnectCountdown() {
    _selfDisconnected = false;
    _selfDisconnectGraceSeconds = 0;
    _selfDisconnectCountdownTimer?.cancel();
    _selfDisconnectCountdownTimer = null;
  }

  void _handleInvalidThrow(dynamic data) {
    if (_isForeignMatch(data)) return;

    // Update scores and state
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    if (player1Score != null && player2Score != null) {
      _updateScoresFromPlayerScores(player1Score, player2Score);
    }

    // The server also sends a bare invalid_throw ({message}) when the throw
    // wasn't ours to make. Blindly assigning the absent fields nulled
    // currentPlayerId (isMyTurn → false) and wiped the round until the
    // corrective game_state_sync landed. Only apply what's present.
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

    // Update scores and state
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
    if (_isForeignMatch(data)) return;

    // Only show dialog if this is MY pending win, not opponent's
    final playerId = data['playerId'] as String?;
    if (playerId != _myUserId) {
      return;
    }
    
    _pendingConfirmation = true;
    _pendingType = 'win';
    _pendingData = Map<String, dynamic>.from(data);
    
    notifyListeners();
  }

  void _handlePendingBust(dynamic data) {
    if (_isForeignMatch(data)) return;

    // Only show dialog if this is MY pending bust, not opponent's
    final playerId = data['playerId'] as String?;
    if (playerId != _myUserId) {
      return;
    }
    
    _pendingConfirmation = true;
    _pendingType = 'bust';
    _pendingReason = data['reason'] as String?;
    _pendingData = Map<String, dynamic>.from(data);
    
    notifyListeners();
  }

  void _handlePlayerForfeited(dynamic data) {

    final eventMatchId = data['matchId'] as String?;
    final winnerId = data['winnerId'] as String?;

    // Validate this event is for the current match — EXCEPT a series-ending
    // forfeit for OUR series carried by a different leg's matchId (we missed
    // ranked_next_leg while disconnected); dropping that one left the client
    // waiting forever for a series that was already over.
    final isOurSeriesEnd = data is Map &&
        data['isRankedSeries'] == true &&
        _seriesId != null &&
        data['seriesId'] == _seriesId;
    if (eventMatchId != _matchId && !isOurSeriesEnd) {
      return;
    }

    // Mark game as ended
    _gameEnded = true;
    _winnerId = winnerId;
    // A forfeit on a BO3 leg loses the whole series (server policy).
    if (data is Map && data['isRankedSeries'] == true) {
      _seriesId ??= data['seriesId'] as String?;
      _player1LegsWon = data['player1LegsWon'] as int? ?? _player1LegsWon;
      _player2LegsWon = data['player2LegsWon'] as int? ?? _player2LegsWon;
      _seriesWinnerId = winnerId;
      _seriesEnded = true;
    }
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = null;
    _cancelSelfDisconnectCountdown();

    // Store forfeit data for UI
    _pendingType = 'forfeit';
    _pendingData = Map<String, dynamic>.from(data);


    notifyListeners();
  }

  void _handleOpponentDisconnected(dynamic data) {
    final eventMatchId = data['matchId'] as String?;
    if (eventMatchId != _matchId) return;

    // Ignore the event when it describes OUR OWN disconnection. The server
    // broadcasts opponent_disconnected to the whole room; after a quick socket
    // flap our reconnected socket has already rejoined the room and receives
    // this event about ourselves. Without this guard the player wrongly sees
    // "opponent disconnected" (alongside the self "connection lost" banner).
    final disconnectedPlayerId = data['disconnectedPlayerId'] as String?;
    if (disconnectedPlayerId != null && disconnectedPlayerId == _myUserId) {
      return;
    }

    _opponentDisconnected = true;
    
    // Start countdown timer from grace period
    final gracePeriodMs = data['gracePeriodMs'] as int? ?? 300000;
    _disconnectGraceSeconds = (gracePeriodMs / 1000).round();
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _disconnectGraceSeconds--;
      if (_disconnectGraceSeconds <= 0) {
        timer.cancel();
      }
      notifyListeners();
    });

    notifyListeners();
  }

  void _handleOpponentReconnected(dynamic data) {
    final eventMatchId = data['matchId'] as String?;
    if (eventMatchId != _matchId) return;

    _opponentDisconnected = false;
    _disconnectGraceSeconds = 0;
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = null;

    notifyListeners();
  }

  void clearAgoraReconnectFlag() {
    _needsAgoraReconnect = false;
  }

  void _handleGameStateSync(dynamic data) {
    final eventMatchId = data['matchId'] as String?;
    if (eventMatchId != _matchId && _matchId != null) {
      // One legitimate mismatch: we missed ranked_next_leg (disconnected
      // during the leg transition) and the server now syncs the NEXT leg of
      // OUR series. Adopt it — same series, fresh leg — instead of dropping
      // the only event that can heal us. Anything else stays rejected.
      final syncSeriesId = data is Map ? data['seriesId'] as String? : null;
      if (eventMatchId != null &&
          _seriesId != null &&
          syncSeriesId == _seriesId) {
        // Direction guard: only adopt FORWARD. A stale periodic sync of the
        // just-finished leg can be emitted after ranked_next_leg (its status
        // check precedes two awaits server-side); adopting it regressed
        // _matchId to the dead leg and killed the board until the next sync.
        final syncLeg = data is Map ? data['legNumber'] as int? : null;
        if (syncLeg != null && syncLeg < _currentLeg) {
          debugPrint('GAME DEBUG: stale sync for leg $syncLeg (< $_currentLeg) — ignoring');
          return;
        }
        debugPrint('GAME DEBUG: sync for next leg $eventMatchId of our series — adopting');
        _matchId = eventMatchId;
        _resetLegState();
      } else {
        return;
      }
    }
    // A reset provider (_matchId == null) must not adopt a foreign match's
    // state: that let another provider's sync populate this one and take over
    // its event handlers.
    if (_matchId == null) return;

    final player1Id = data['player1Id'] as String?;
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    final currentPlayerId = data['currentPlayerId'] as String?;
    final dartsThrown = data['dartsThrown'] as int?;
    final currentRoundThrows = data['currentRoundThrows'] as List<dynamic>?;

    if (player1Id != null) _player1Id = player1Id;
    if (currentPlayerId != null) _currentPlayerId = currentPlayerId;
    if (dartsThrown != null) _dartsThrown = dartsThrown;

    // Settle the pending-dart queue against the server's applied dart IDs:
    // a dart whose ack was lost but that IS in the server's round no longer
    // needs re-delivery.
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
      // Why: when it's my turn and the AI has already detected darts locally
      // (added to _currentRoundThrows + emitted throw_dart to server), a
      // game_state_sync arriving before the server processed those throws
      // would wipe the local detections. We only accept the server version
      // if it's not my turn, or if the server has at least as many darts as
      // us (meaning our throws were processed).
      final serverThrows = currentRoundThrows.map((t) => t.toString()).toList();
      if (!isMyTurn || serverThrows.length >= _currentRoundThrows.length) {
        _currentRoundThrows = serverThrows;
        _dartsEmittedThisRound = _currentRoundThrows.length;
        _ackedDartsThisRound = isMyTurn ? serverThrows.length : 0;
      } else {
        // The server holds FEWER darts than we do — some of ours never
        // arrived. They are still in _pendingDartAcks (un-acked), so
        // re-deliver them now instead of keeping a phantom-only local view
        // that could never heal. Idempotent server-side via dartId.
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

    _updateRoundsFromData(data);

    // Restore the BO3 series context (mid-series reconnects would otherwise
    // lose the legs scoreboard — legs counts only travel on the ranked_*
    // events, which a reconnecting client has missed by definition).
    _applySeriesFields(data);

    // Restore pending win/bust confirmation. A client that missed the
    // pending_win/pending_bust emit used to reconnect to a board stuck at
    // "reste 0" with no dialog and every throw rejected. Only act when the
    // backend actually sends the field (older backends don't).
    if (data is Map && data.containsKey('pendingState')) {
      final pendingState = data['pendingState'] as String?;
      final pendingPlayerId = data['pendingPlayerId'] as String?;
      if (pendingState != null && pendingPlayerId == _myUserId) {
        _pendingConfirmation = true;
        _pendingType = pendingState == 'pending_win' ? 'win' : 'bust';
        _pendingReason = data['pendingReason'] as String?;
        _pendingData = _restoredPendingData(pendingState);
      } else if (pendingState == null &&
          isMyTurn &&
          _dartsThrown >= 3 &&
          _pendingType == null) {
        // Full non-pending round awaiting confirm: re-show the CONFIRM pill
        // (round_ready_confirm is fire-and-forget and may have been missed).
        _pendingConfirmation = true;
      }
    }

    // Update Agora credentials if provided (reconnection scenario)
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
      // Only pre-render the remote view when we're on the strict path
      // ourselves (same reasoning as initGame).
      if (hasStrictAgoraCredentials) {
        _remoteUid = newOpponentAgoraUid;
      }
    }

    _gameStarted = true;
    notifyListeners();
  }

  /// Rebuild the [pendingData] the win/bust dialogs read, for a pending state
  /// recovered from game_state_sync rather than from the original
  /// pending_win/pending_bust event.
  ///
  /// The checkout dialog shows which dart finished the leg. A checkout never
  /// switches the turn, so the finishing dart is simply the last throw of the
  /// round the server just sent us — no extra field needed from the backend.
  /// Without this the dialog rendered "You hit Unknown to finish!".
  Map<String, dynamic> _restoredPendingData(String pendingState) {
    final restored = <String, dynamic>{
      'matchId': _matchId,
      'playerId': _myUserId,
      'reason': _pendingReason,
      'restoredFromSync': true,
    };
    if (pendingState == 'pending_win') {
      String? finishingDart;
      for (final notation in _currentRoundThrows) {
        if (notation.isNotEmpty) finishingDart = notation;
      }
      if (finishingDart != null) {
        restored['finalDart'] = {'notation': finishingDart};
      }
    }
    // Keep a finalDart we already had from the live pending_win event: it is
    // first-hand, this one is reconstructed.
    final existing = _pendingData?['finalDart'];
    if (existing != null) restored['finalDart'] = existing;
    return restored;
  }

  void reconnectToMatch() {
    if (_matchId != null && _myUserId != null) {
      try {
        SocketService.emit('reconnect_to_match', {
          'matchId': _matchId,
          'userId': _myUserId,
        });
      } catch (_) {}
    }
  }

  void _handleDartUndone(dynamic data) {
    if (_isForeignMatch(data)) return;
    // Update scores
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    if (player1Score != null && player2Score != null) {
      _updateScoresFromPlayerScores(player1Score, player2Score);
    }
    
    _dartsThrown = data['dartsThrown'] as int? ?? _dartsThrown;

    // Sync currentRoundThrows from backend
    final throws = data['currentRoundThrows'] as List<dynamic>?;
    if (throws != null) {
      _currentRoundThrows = throws.map((t) => t.toString()).toList();
      // Re-derive the slot guards from the authoritative post-undo count so a
      // later edit can't mistake an applied dart for a never-sent slot.
      _ackedDartsThisRound = _currentRoundThrows.length;
      final claimed = _ackedDartsThisRound + _pendingDartAcks.length;
      if (_dartsEmittedThisRound != claimed) {
        _dartsEmittedThisRound = claimed;
      }
    }

    // Clear pending state since dart was undone
    _pendingConfirmation = false;
    _pendingType = null;
    _pendingReason = null;
    _pendingData = null;
    
    notifyListeners();
  }

  void undoLastDart() {
    // If the newest dart is still in flight (un-acked), cancel its delivery
    // instead of emitting undo — the server hasn't applied it, so undo would
    // pop an OLDER, applied dart. In the rare case it was applied with the
    // ack in flight, the dartCount check on confirm surfaces the mismatch and
    // the corrective sync heals it.
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
          'matchId': _matchId,
          'playerId': _myUserId,
        });
      } catch (e) {
        debugPrint('GameProvider: undoLastDart failed: $e');
      }
    }
    // Decrement local guard (server will sync actual state via dart_undone)
    if (_dartsEmittedThisRound > 0) {
      _dartsEmittedThisRound--;
    }
    // Clear pending state
    _pendingConfirmation = false;
    _pendingType = null;
    _pendingReason = null;
    _pendingData = null;
    notifyListeners();
  }

  /// Undo all darts thrown this round (used when editing to avoid negative scores)
  void undoAllDarts() {
    // In-flight darts are cancelled, not undone: the server never applied
    // them. Only server-applied darts need an undo_last_dart each — counting
    // the local guard here used to desync the round when the two disagreed.
    _clearPendingDarts();
    var applied = _ackedDartsThisRound > _currentRoundThrows.length
        ? _ackedDartsThisRound
        : _currentRoundThrows.where((t) => t.isNotEmpty).length;
    while (applied > 0) {
      try {
        SocketService.emit('undo_last_dart', {
          'matchId': _matchId,
          'playerId': _myUserId,
        });
      } catch (e) {
        debugPrint('GameProvider: undoAllDarts failed: $e');
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

  String _nextDartId() {
    final user = (_myUserId ?? 'u').replaceAll('-', '');
    final prefix = user.length >= 8 ? user.substring(0, 8) : user;
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'd$prefix$stamp${_dartIdSeq++}';
  }

  Future<void> throwDart({
    required int baseScore,
    required ScoreMultiplier multiplier,
    // 'ai' when proposed by on-device auto-scoring, 'manual' when typed. Feeds
    // the backend trust factor. Optional field; old backends just ignore it.
    String source = 'manual',
  }) async {
    if (!isMyTurn || _dartsEmittedThisRound >= 3 || _gameEnded) {
      return;
    }

    final isDouble = multiplier == ScoreMultiplier.double;
    final isTriple = multiplier == ScoreMultiplier.triple;
    final payload = <String, dynamic>{
      'matchId': _matchId,
      'playerId': _myUserId,
      'baseScore': baseScore,
      'isDouble': isDouble,
      'isTriple': isTriple,
      'source': source,
    };

    if (!SocketService.supportsDartAck) {
      // Legacy backend: it would strip dartId, score the dart, and never ack —
      // so tracking it would make us re-send a dart that already counted.
      // Fire-and-forget, exactly as before the ack protocol existed.
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

  /// Send a throw_dart with a delivery guarantee: the payload stays in
  /// _pendingDartAcks (and is periodically re-sent, idempotent server-side via
  /// dartId) until the server acks it or the round ends. An emit that throws
  /// (socket down) is NOT rolled back — the retry pump delivers it when the
  /// socket returns, which is exactly the case that used to lose the dart.
  void _emitDartWithTracking(Map<String, dynamic> payload) {
    final dartId = _nextDartId();
    payload['dartId'] = dartId;
    _pendingDartAcks[dartId] = payload;
    try {
      SocketService.emit('throw_dart', payload);
    } catch (e) {
      debugPrint('GameProvider: throw_dart emit failed, queued for retry: $e');
    }
    _ensureDartRetryPump();
  }

  void _ensureDartRetryPump() {
    _dartRetryTimer ??=
        Timer.periodic(const Duration(seconds: 2), (_) => _flushPendingDarts());
  }

  /// Re-send every un-acked dart, lowest turn-index first. Safe to call any
  /// time: the server dedups by dartId, so a dart whose ack was merely lost is
  /// confirmed as duplicate instead of scoring twice.
  void _flushPendingDarts() {
    if (!SocketService.supportsDartAck) {
      // The server we're now talking to can't deduplicate (backend rollback,
      // or a reconnect that hasn't been authenticated yet). Re-sending would
      // score the dart a second time. Stop retrying; round_complete clears the
      // queue, and a genuinely lost dart is surfaced by the score echo.
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
        // Socket still down — the pump retries on the next tick.
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
    if (eventMatchId != null && _matchId != null && eventMatchId != _matchId) {
      return;
    }
    final dartId = data['dartId'] as String?;
    if (dartId == null) return;
    final wasPending = _pendingDartAcks.remove(dartId) != null;

    if (data['applied'] == true) {
      final appliedIndex = data['appliedIndex'] as int?;
      if (appliedIndex != null && appliedIndex + 1 > _ackedDartsThisRound) {
        _ackedDartsThisRound = appliedIndex + 1;
      } else if (appliedIndex == null && data['duplicate'] == true) {
        // Retry of an already-applied dart: the original ack (or echo) already
        // counted it; nothing to update beyond settling the pending queue.
      }
    } else if (wasPending) {
      // The server refused this dart (invalid / not our turn / sequence
      // mismatch) and sent a corrective game_state_sync alongside. Re-derive
      // the slot guard from what is actually delivered or still in flight so
      // the freed slot can be reused.
      final claimed = _ackedDartsThisRound + _pendingDartAcks.length;
      if (_dartsEmittedThisRound > claimed) {
        _dartsEmittedThisRound = claimed;
      }
      debugPrint(
          'GameProvider: dart $dartId rejected (${data['reason']}) — slot released');
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
    if (eventMatchId != null && _matchId != null && eventMatchId != _matchId) {
      return;
    }
    // The server holds a different dart count than we claimed and refused to
    // commit the round — the exact spot where a lost 3rd dart used to become a
    // silent 2-dart visit. Re-send anything still un-acked (idempotent) and
    // retry the confirm; the corrective sync sent with the rejection heals our
    // view meanwhile.
    debugPrint(
        'GameProvider: confirm rejected — server=${data['serverDartsThrown']} client=${data['clientDartCount']}');
    _flushPendingDarts();
    if (_confirmRejectedRetries < 3) {
      _confirmRejectedRetries++;
      Timer(const Duration(milliseconds: 900), () {
        if (!_disposed && !_gameEnded && isMyTurn) confirmRound();
      });
    }
    notifyListeners();
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
        // Delivery-tracked like throwDart. dartIndex is what the server will
        // verify against its own count, so a gap (editing slot 3 while slot 2
        // was never sent) is rejected with sequence_mismatch + a corrective
        // sync instead of silently recording the dart at the wrong position.
        final payload = <String, dynamic>{
          'matchId': _matchId,
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
          'matchId': _matchId,
          'playerId': _myUserId,
          'dartIndex': index,
          'baseScore': baseScore,
          'isDouble': isDouble,
          'isTriple': isTriple,
        });
      }
    } catch (e) {
      debugPrint('GameProvider: editDartThrow emit failed: $e');
    }

    notifyListeners();
  }

  String _getScoreNotation(int baseScore, ScoreMultiplier multiplier) {
    final prefix = multiplier == ScoreMultiplier.single 
        ? 'S' 
        : multiplier == ScoreMultiplier.double 
            ? 'D' 
            : 'T';
    return '$prefix$baseScore';
  }

  /// Helper to correctly map player1Rounds/player2Rounds to myRounds/opponentRounds
  void _updateRoundsFromData(dynamic data) {
    final p1Rounds = data['player1Rounds'] as List<dynamic>?;
    final p2Rounds = data['player2Rounds'] as List<dynamic>?;
    if (p1Rounds == null && p2Rounds == null) return;
    final isPlayer1 = _myUserId == _player1Id;
    if (isPlayer1) {
      if (p1Rounds != null) _myRounds = p1Rounds.map((e) => (e as num).toInt()).toList();
      if (p2Rounds != null) _opponentRounds = p2Rounds.map((e) => (e as num).toInt()).toList();
    } else {
      if (p2Rounds != null) _myRounds = p2Rounds.map((e) => (e as num).toInt()).toList();
      if (p1Rounds != null) _opponentRounds = p1Rounds.map((e) => (e as num).toInt()).toList();
    }
  }

  /// Helper to correctly map player1Score/player2Score to myScore/opponentScore
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
    SocketService.off('reconnect_failed');
    SocketService.off('rematch_requested');
    SocketService.off('rematch_declined');
    SocketService.off('throw_dart_ack');
    SocketService.off('confirm_round_rejected');
    SocketService.off('ranked_leg_won');
    SocketService.off('ranked_next_leg');
    SocketService.off('ranked_match_won');
  }

  void setRemoteUser(int? uid) {
    _remoteUid = uid;
    notifyListeners();
  }
  
  void setLocalUserJoined(bool joined) {
    _localUserJoined = joined;
    notifyListeners();
  }

  void reset() {
    debugPrint('GAME DEBUG: reset() called - CLEARING all state. Was: gameStarted=$_gameStarted, gameEnded=$_gameEnded, winnerId=$_winnerId, matchId=$_matchId');
    _cleanupSocketListeners();
    _matchId = null;
    _myScore = 501;
    _opponentScore = 501;
    _currentPlayerId = null;
    _myUserId = null;
    _opponentUserId = null;
    _player1Id = null;
    _dartsThrown = 0;
    _gameStarted = false;
    _gameEnded = false;
    _winnerId = null;
    _lastThrow = null;
    _currentRoundThrows = [];
    _myRounds = [];
    _opponentRounds = [];
    _clearPendingDarts();
    _ackedDartsThisRound = 0;
    _confirmAttempts = 0;
    _confirmRejectedRetries = 0;
    _listenersSetUp = false; // Reset so listeners can be set up for next game
    _pendingConfirmation = false;
    _pendingType = null;
    _pendingReason = null;
    _pendingData = null;
    _opponentDisconnected = false;
    _disconnectGraceSeconds = 0;
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = null;
    _selfDisconnected = false;
    _selfDisconnectGraceSeconds = 0;
    _selfDisconnectCountdownTimer?.cancel();
    _selfDisconnectCountdownTimer = null;
    _agoraAppId = null;
    _agoraToken = null;
    _agoraTokenStrict = null;
    _agoraChannelName = null;
    _agoraUid = null;
    _opponentAgoraUid = null;
    _remoteUid = null;
    _localUserJoined = false;
    _needsAgoraReconnect = false;
    _reconnectFailed = false;
    _reconnectFailedReason = null;
    _isFriendly = false;
    _rematchWaiting = false;
    _rematchDeclined = false;
    _opponentWantsRematch = false;
    _resetSeriesState();
    debugPrint('GAME DEBUG: reset() done - gameStarted=$_gameStarted, gameEnded=$_gameEnded');
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = null;
    _selfDisconnectCountdownTimer?.cancel();
    _selfDisconnectCountdownTimer = null;
    _clearPendingDarts();
    _cleanupSocketListeners();
    super.dispose();
  }
}

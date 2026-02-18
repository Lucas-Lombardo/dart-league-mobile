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
  bool _pendingConfirmation = false;
  String? _pendingType;
  String? _pendingReason;
  Map<String, dynamic>? _pendingData;
  bool _opponentDisconnected = false;
  int _disconnectGraceSeconds = 0;
  Timer? _disconnectCountdownTimer;

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
  String? _agoraChannelName;
  int? _remoteUid;
  bool _localUserJoined = false;
  bool _needsAgoraReconnect = false;

  bool _listenersSetUp = false;

  TournamentGameProvider();

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
  bool get isMyTurn => _currentPlayerId == _myUserId;

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
  String? get agoraChannelName => _agoraChannelName;
  int? get remoteUid => _remoteUid;
  bool get localUserJoined => _localUserJoined;
  bool get needsAgoraReconnect => _needsAgoraReconnect;

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
    String? agoraChannelName,
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

    if (agoraAppId != null) _agoraAppId = agoraAppId;
    if (agoraToken != null) _agoraToken = agoraToken;
    if (agoraChannelName != null) _agoraChannelName = agoraChannelName;

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

    // Tournament-specific events
    SocketService.on('tournament_leg_won', _handleTournamentLegWon);
    SocketService.on('tournament_next_leg', _handleTournamentNextLeg);
    SocketService.on('tournament_match_won', _handleTournamentMatchWon);
  }

  // --- Standard game event handlers (same as GameProvider) ---

  void _handleGameStarted(dynamic data) {
    debugPrint('TOURNAMENT: game_started received');
    _gameStarted = true;
    _currentPlayerId = data['currentPlayerId'] as String?;
    _player1Id = _currentPlayerId;
    _myScore = 501;
    _opponentScore = 501;
    _tournamentState = TournamentGameState.playing;
    notifyListeners();
  }

  void _handleScoreUpdated(dynamic data) {
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
        // Keep guard in sync with server
        _dartsEmittedThisRound = _currentRoundThrows.length;
      }
    }
    // Track opponent's throws during their turn
    if (!isMyTurn && _lastThrow != null) {
      _opponentRoundThrows.add(_lastThrow!);
    }
    notifyListeners();
  }

  void _handleRoundReadyConfirm(dynamic data) {
    _pendingConfirmation = true;
    notifyListeners();
  }

  void _handleRoundComplete(dynamic data) {
    _dartsThrown = 0;
    _currentRoundThrows = [];
    _opponentRoundThrows = [];
    _dartsEmittedThisRound = 0;
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

  void _handleMustFinishDouble(dynamic data) {
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
    if (currentRoundThrows != null) {
      _currentRoundThrows = currentRoundThrows.map((t) => t.toString()).toList();
    }
    if (player1Score != null && player2Score != null) {
      _updateScoresFromPlayerScores(player1Score, player2Score);
    }

    final newAgoraAppId = data['agoraAppId'] as String?;
    final newAgoraToken = data['agoraToken'] as String?;
    final newAgoraChannelName = data['agoraChannelName'] as String?;
    if (newAgoraAppId != null && newAgoraAppId.isNotEmpty &&
        newAgoraToken != null && newAgoraToken.isNotEmpty &&
        newAgoraChannelName != null && newAgoraChannelName.isNotEmpty) {
      _agoraAppId = newAgoraAppId;
      _agoraToken = newAgoraToken;
      _agoraChannelName = newAgoraChannelName;
      _needsAgoraReconnect = true;
    }

    _gameStarted = true;
    _tournamentState = TournamentGameState.playing;
    notifyListeners();
  }

  void _handleDartUndone(dynamic data) {
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    if (player1Score != null && player2Score != null) {
      _updateScoresFromPlayerScores(player1Score, player2Score);
    }
    _dartsThrown = data['dartsThrown'] as int? ?? _dartsThrown;
    final throws = data['currentRoundThrows'] as List<dynamic>?;
    if (throws != null) {
      _currentRoundThrows = throws.map((t) => t.toString()).toList();
      _dartsEmittedThisRound = _currentRoundThrows.length;
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

    if (newMatchId != null) {
      _currentGameMatchId = newMatchId;
    }

    // Update Agora tokens for next leg video call
    final newAgoraAppId = data['agoraAppId'] as String?;
    final newAgoraToken = data['agoraToken'] as String?;
    final newAgoraChannelName = data['agoraChannelName'] as String?;
    if (newAgoraAppId != null && newAgoraAppId.isNotEmpty &&
        newAgoraToken != null && newAgoraToken.isNotEmpty &&
        newAgoraChannelName != null && newAgoraChannelName.isNotEmpty) {
      _agoraAppId = newAgoraAppId;
      _agoraToken = newAgoraToken;
      _agoraChannelName = newAgoraChannelName;
      _needsAgoraReconnect = true;
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
    if (_currentRoundThrows.length < 3) {
      SocketService.emit('end_round_early', {
        'matchId': _currentGameMatchId,
        'playerId': _myUserId,
      });
    } else {
      SocketService.emit('confirm_round', {
        'matchId': _currentGameMatchId,
        'playerId': _myUserId,
      });
    }
  }

  void cancelConfirmation() {
    if (_pendingConfirmation) {
      _pendingConfirmation = false;
      notifyListeners();
    }
  }

  void confirmWin() {
    if (_pendingType != 'win') return;
    SocketService.emit('confirm_win', {
      'matchId': _currentGameMatchId,
      'playerId': _myUserId,
    });
    _clearPendingState();
  }

  void confirmBust() {
    if (_pendingType != 'bust') return;
    SocketService.emit('confirm_bust', {
      'matchId': _currentGameMatchId,
      'playerId': _myUserId,
    });
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
  }) async {
    if (!isMyTurn || _dartsEmittedThisRound >= 3 || _gameEnded) return;

    try {
      final isDouble = multiplier == ScoreMultiplier.double;
      final isTriple = multiplier == ScoreMultiplier.triple;

      _dartsEmittedThisRound++;

      SocketService.emit('throw_dart', {
        'matchId': _currentGameMatchId,
        'playerId': _myUserId,
        'baseScore': baseScore,
        'isDouble': isDouble,
        'isTriple': isTriple,
      });
    } catch (_) {
      // Socket emit failed — roll back guard
      _dartsEmittedThisRound--;
    }
  }

  void editDartThrow(int index, int baseScore, ScoreMultiplier multiplier) {
    if (index < 0 || index >= _currentRoundThrows.length) return;
    final notation = _getScoreNotation(baseScore, multiplier);
    _currentRoundThrows[index] = notation;
    final isDouble = multiplier == ScoreMultiplier.double;
    final isTriple = multiplier == ScoreMultiplier.triple;
    SocketService.emit('edit_dart', {
      'matchId': _currentGameMatchId,
      'playerId': _myUserId,
      'dartIndex': index,
      'baseScore': baseScore,
      'isDouble': isDouble,
      'isTriple': isTriple,
    });
    notifyListeners();
  }

  void undoLastDart() {
    SocketService.emit('undo_last_dart', {
      'matchId': _currentGameMatchId,
      'playerId': _myUserId,
    });
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
    _listenersSetUp = false;
    _pendingConfirmation = false;
    _pendingType = null;
    _pendingReason = null;
    _pendingData = null;
    _opponentDisconnected = false;
    _disconnectGraceSeconds = 0;
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = null;
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
    _agoraChannelName = null;
    _remoteUid = null;
    _localUserJoined = false;
    _needsAgoraReconnect = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _cleanupSocketListeners();
    _disconnectCountdownTimer?.cancel();
    super.dispose();
  }
}

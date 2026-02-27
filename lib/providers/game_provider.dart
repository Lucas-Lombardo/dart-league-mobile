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
  int _dartsThrown = 0;
  bool _gameStarted = false;
  bool _gameEnded = false;
  String? _winnerId;
  String? _lastThrow;
  List<String> _currentRoundThrows = [];
  List<String> _opponentRoundThrows = [];
  int _dartsEmittedThisRound = 0; // Local guard for rapid throws before server ack
  bool _listenersSetUp = false;
  bool _pendingConfirmation = false;
  String? _pendingType; // 'win' or 'bust'
  String? _pendingReason;
  Map<String, dynamic>? _pendingData;
  bool _opponentDisconnected = false;
  int _disconnectGraceSeconds = 0;
  Timer? _disconnectCountdownTimer;
  
  // Agora video calling
  String? _agoraAppId;
  String? _agoraToken;
  String? _agoraChannelName;
  int? _remoteUid;
  bool _localUserJoined = false;
  bool _needsAgoraReconnect = false;

  GameProvider();

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
  List<String> get currentRoundThrows => _currentRoundThrows;
  List<String> get opponentRoundThrows => _opponentRoundThrows;
  bool get pendingConfirmation => _pendingConfirmation;
  String? get pendingType => _pendingType;
  String? get pendingReason => _pendingReason;
  Map<String, dynamic>? get pendingData => _pendingData;
  bool get opponentDisconnected => _opponentDisconnected;
  int get disconnectGraceSeconds => _disconnectGraceSeconds;
  
  // Agora getters
  String? get agoraAppId => _agoraAppId;
  String? get agoraToken => _agoraToken;
  String? get agoraChannelName => _agoraChannelName;
  int? get remoteUid => _remoteUid;
  bool get localUserJoined => _localUserJoined;
  bool get needsAgoraReconnect => _needsAgoraReconnect;

  bool get isMyTurn => _currentPlayerId == _myUserId;
  
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
    String? agoraChannelName,
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
    if (agoraChannelName != null) _agoraChannelName = agoraChannelName;
    
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
      _dartsEmittedThisRound = 0;
      _pendingConfirmation = false;
      _pendingType = null;
      _pendingReason = null;
      _pendingData = null;
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
  }

  void _handleGameStarted(dynamic data) {
    debugPrint('DEBUG: game_started received, myUserId=$_myUserId');
    _gameStarted = true;
    _currentPlayerId = data['currentPlayerId'] as String?;
    
    // Track player1Id for correct score mapping
    // player1Id is whoever has the first turn (currentPlayerId at game start)
    _player1Id = _currentPlayerId;
    
    // Both players start at 501
    _myScore = 501;
    _opponentScore = 501;
    
    notifyListeners();
  }

  void _handleScoreUpdated(dynamic data) {
    
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
        // Keep guard in sync with server
        _dartsEmittedThisRound = _currentRoundThrows.length;
      }
    }
    
    // Track opponent's throws during their turn
    // Use currentRoundThrows as source of truth so edits are reflected (not just appends)
    if (!isMyTurn) {
      final throws = data['currentRoundThrows'] as List<dynamic>?;
      if (throws != null) {
        _opponentRoundThrows = throws.map((t) => t.toString()).toList();
      } else if (_lastThrow != null) {
        _opponentRoundThrows.add(_lastThrow!);
      }
    }
    
    notifyListeners();
  }

  void _handleRoundReadyConfirm(dynamic data) {
    final eventMatchId = data['matchId'] as String?;
    if (eventMatchId != null && eventMatchId != _matchId) return;
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
    _currentPlayerId = data['nextPlayerId'] as String?;
    _pendingConfirmation = false;
    
    // Backend sends player1Score and player2Score directly
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    
    if (player1Score != null && player2Score != null) {
      _updateScoresFromPlayerScores(player1Score, player2Score);
    }
    
    notifyListeners();
  }
  
  void confirmRound() {
    try {
      if (_currentRoundThrows.length < 3) {
        SocketService.emit('end_round_early', {
          'matchId': _matchId,
          'playerId': _myUserId,
        });
      } else {
        SocketService.emit('confirm_round', {
          'matchId': _matchId,
          'playerId': _myUserId,
        });
      }
    } catch (e) {
      debugPrint('GameProvider: confirmRound failed: $e');
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
    
    debugPrint('GAME DEBUG: game_won processed - gameEnded=$_gameEnded, winnerId=$_winnerId');
    notifyListeners();
  }

  void _handleMatchEnded(dynamic data) {
    
    // Prevent duplicate processing if game already ended
    if (_gameEnded) {
      return;
    }
    
    _winnerId = data['winnerId'] as String?;
    _gameEnded = true;
    
    notifyListeners();
  }

  void _handleInvalidThrow(dynamic data) {
    
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

  void _handleMustFinishDouble(dynamic data) {
    
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
    
    // Validate this event is for the current match
    if (eventMatchId != _matchId) {
      return;
    }
    
    // Mark game as ended
    _gameEnded = true;
    _winnerId = winnerId;
    
    // Store forfeit data for UI
    _pendingType = 'forfeit';
    _pendingData = Map<String, dynamic>.from(data);
    
    
    notifyListeners();
  }

  void _handleOpponentDisconnected(dynamic data) {
    final eventMatchId = data['matchId'] as String?;
    if (eventMatchId != _matchId) return;

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
    if (eventMatchId != _matchId && _matchId != null) return;

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

    // Update Agora credentials if provided (reconnection scenario)
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
    notifyListeners();
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
    }
    
    // Clear pending state since dart was undone
    _pendingConfirmation = false;
    _pendingType = null;
    _pendingReason = null;
    _pendingData = null;
    
    notifyListeners();
  }

  void undoLastDart() {
    try {
      SocketService.emit('undo_last_dart', {
        'matchId': _matchId,
        'playerId': _myUserId,
      });
    } catch (e) {
      debugPrint('GameProvider: undoLastDart failed: $e');
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

  Future<void> throwDart({
    required int baseScore,
    required ScoreMultiplier multiplier,
  }) async {
    if (!isMyTurn || _dartsEmittedThisRound >= 3 || _gameEnded) {
      return;
    }

    try {
      final isDouble = multiplier == ScoreMultiplier.double;
      final isTriple = multiplier == ScoreMultiplier.triple;
      
      _dartsEmittedThisRound++;
      
      SocketService.emit('throw_dart', {
        'matchId': _matchId,
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
    if (index >= _dartsEmittedThisRound) {
      _dartsEmittedThisRound = index + 1;
      SocketService.emit('throw_dart', {
        'matchId': _matchId,
        'playerId': _myUserId,
        'baseScore': baseScore,
        'isDouble': isDouble,
        'isTriple': isTriple,
      });
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
    _listenersSetUp = false; // Reset so listeners can be set up for next game
    _pendingConfirmation = false;
    _pendingType = null;
    _pendingReason = null;
    _pendingData = null;
    _opponentDisconnected = false;
    _disconnectGraceSeconds = 0;
    _disconnectCountdownTimer?.cancel();
    _disconnectCountdownTimer = null;
    _agoraAppId = null;
    _agoraToken = null;
    _agoraChannelName = null;
    _remoteUid = null;
    _localUserJoined = false;
    _needsAgoraReconnect = false;
    debugPrint('GAME DEBUG: reset() done - gameStarted=$_gameStarted, gameEnded=$_gameEnded');
    notifyListeners();
  }

  @override
  void dispose() {
    _cleanupSocketListeners();
    super.dispose();
  }
}

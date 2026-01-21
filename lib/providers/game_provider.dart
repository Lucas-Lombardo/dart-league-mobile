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
  bool _listenersSetUp = false;
  bool _pendingConfirmation = false;
  String? _pendingType; // 'win' or 'bust'
  String? _pendingReason;
  Map<String, dynamic>? _pendingData;
  
  // Agora video calling
  String? _agoraAppId;
  String? _agoraToken;
  String? _agoraChannelName;
  int? _remoteUid;
  bool _localUserJoined = false;

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
  bool get pendingConfirmation => _pendingConfirmation;
  String? get pendingType => _pendingType;
  String? get pendingReason => _pendingReason;
  Map<String, dynamic>? get pendingData => _pendingData;
  
  // Agora getters
  String? get agoraAppId => _agoraAppId;
  String? get agoraToken => _agoraToken;
  String? get agoraChannelName => _agoraChannelName;
  int? get remoteUid => _remoteUid;
  bool get localUserJoined => _localUserJoined;

  bool get isMyTurn => _currentPlayerId == _myUserId;
  
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
    
    // Always set these - they're needed for the game to work
    _matchId = matchId;
    _myUserId = myUserId;
    _opponentUserId = opponentUserId;
    
    // Store Agora credentials if provided
    if (agoraAppId != null) _agoraAppId = agoraAppId;
    if (agoraToken != null) _agoraToken = agoraToken;
    if (agoraChannelName != null) _agoraChannelName = agoraChannelName;
    
    
    // Only initialize scores if game hasn't started yet
    // Once gameStarted is true, we keep the state from the game_started event
    if (!_gameStarted) {
      _myScore = 501;
      _opponentScore = 501;
      _dartsThrown = 0;
      _gameEnded = false;
      _winnerId = null;
      _lastThrow = null;
      _currentRoundThrows = [];
    } else {
    }
    
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

    SocketService.on('player_forfeited', (data) {
      _handlePlayerForfeited(data);
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
    
    // If backend sends currentRoundThrows array (e.g., after edit_dart), sync it
    // BUT only if it's MY turn - otherwise we'd get opponent's throws
    if (data['currentRoundThrows'] != null && isMyTurn) {
      final throws = data['currentRoundThrows'] as List<dynamic>?;
      if (throws != null) {
        _currentRoundThrows = throws.map((t) => t.toString()).toList();
      }
    }
    
    // DON'T update currentPlayerId here - it should only change in round_complete
    // This prevents premature turn switching after each dart
    
    
    notifyListeners();
  }

  void _handleRoundReadyConfirm(dynamic data) {
    
    _pendingConfirmation = true;
    notifyListeners();
  }

  void _handleRoundComplete(dynamic data) {
    
    _dartsThrown = 0;
    _currentRoundThrows = [];
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
    // Auto-fill remaining darts with 0s if less than 3
    while (_currentRoundThrows.length < 3) {
      throwDart(baseScore: 0, multiplier: ScoreMultiplier.single);
    }
    
    // Emit confirm event if pending, otherwise force it
    SocketService.emit('confirm_round', {
      'matchId': _matchId,
      'playerId': _myUserId,
    });
  }
  
  void cancelConfirmation() {
    if (_pendingConfirmation) {
      _pendingConfirmation = false;
      notifyListeners();
    }
  }

  void confirmWin() {
    if (_pendingType != 'win') {
      return;
    }
    
    SocketService.emit('confirm_win', {
      'matchId': _matchId,
      'playerId': _myUserId,
    });
    
    // Clear pending state - backend will emit game_won
    _clearPendingState();
  }

  void confirmBust() {
    if (_pendingType != 'bust') {
      return;
    }
    
    SocketService.emit('confirm_bust', {
      'matchId': _matchId,
      'playerId': _myUserId,
    });
    
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
    
    // Prevent duplicate processing if game already ended
    if (_gameEnded) {
      return;
    }
    
    _winnerId = data['winnerId'] as String?;
    _gameEnded = true;
    
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

  Future<void> throwDart({
    required int baseScore,
    required ScoreMultiplier multiplier,
  }) async {
    if (!isMyTurn || _currentRoundThrows.length >= 3 || _gameEnded) {
      return;
    }

    try {
      final isDouble = multiplier == ScoreMultiplier.double;
      final isTriple = multiplier == ScoreMultiplier.triple;
      final notation = _getScoreNotation(baseScore, multiplier);
      
      
      SocketService.emit('throw_dart', {
        'matchId': _matchId,
        'playerId': _myUserId,
        'baseScore': baseScore,
        'isDouble': isDouble,
        'isTriple': isTriple,
      });
      
      // Add to current round throws immediately for UI feedback
      _currentRoundThrows.add(notation);
      _lastThrow = notation;
      
      
      notifyListeners();
    } catch (_) {
      // Socket emit failed
    }
  }

  void editDartThrow(int index, int baseScore, ScoreMultiplier multiplier) {
    if (index < 0 || index >= _currentRoundThrows.length) {
      return;
    }
    
    final notation = _getScoreNotation(baseScore, multiplier);
    _currentRoundThrows[index] = notation;
    
    
    // Emit edit event to backend
    final isDouble = multiplier == ScoreMultiplier.double;
    final isTriple = multiplier == ScoreMultiplier.triple;
    
    SocketService.emit('edit_dart', {
      'matchId': _matchId,
      'playerId': _myUserId,
      'dartIndex': index,
      'baseScore': baseScore,
      'isDouble': isDouble,
      'isTriple': isTriple,
    });
    
    notifyListeners();
  }

  void deleteDartThrow(int index) {
    if (index < 0 || index >= _currentRoundThrows.length) {
      return;
    }
    
    _currentRoundThrows.removeAt(index);
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
    _agoraAppId = null;
    _agoraToken = null;
    _agoraChannelName = null;
    _remoteUid = null;
    _localUserJoined = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _cleanupSocketListeners();
    super.dispose();
  }
}

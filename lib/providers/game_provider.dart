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
  int _dartsThrown = 0;
  bool _gameStarted = false;
  bool _gameEnded = false;
  String? _winnerId;
  String? _lastThrow;
  List<String> _currentRoundThrows = [];
  bool _listenersSetUp = false;
  bool _pendingConfirmation = false;
  
  // Agora video calling
  String? _agoraAppId;
  String? _agoraToken;
  String? _agoraChannelName;
  int? _remoteUid;
  bool _localUserJoined = false;

  GameProvider() {
    debugPrint('🎮 GameProvider created');
  }

  void ensureListenersSetup() {
    if (_listenersSetUp) {
      debugPrint('✅ Socket listeners already set up');
      return;
    }
    
    debugPrint('🎮 Setting up game socket listeners');
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
    debugPrint('🎮 Initializing game: matchId=$matchId, myUserId=$myUserId, opponentUserId=$opponentUserId, currentGameStarted=$_gameStarted');
    
    // Always set these - they're needed for the game to work
    _matchId = matchId;
    _myUserId = myUserId;
    _opponentUserId = opponentUserId;
    
    // Store Agora credentials if provided
    if (agoraAppId != null) _agoraAppId = agoraAppId;
    if (agoraToken != null) _agoraToken = agoraToken;
    if (agoraChannelName != null) _agoraChannelName = agoraChannelName;
    
    debugPrint('📹 Agora credentials: appId=${_agoraAppId != null}, token=${_agoraToken != null}, channel=$_agoraChannelName');
    
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
      debugPrint('✅ Game state initialized - waiting for game_started event');
    } else {
      debugPrint('✅ Game already started - keeping state: myScore=$_myScore, opponentScore=$_opponentScore');
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
  }

  void _handleGameStarted(dynamic data) {
    debugPrint('🎮 Game started: $data');
    _gameStarted = true;
    _currentPlayerId = data['currentPlayerId'] as String?;
    
    // Both players start at 501
    _myScore = 501;
    _opponentScore = 501;
    
    debugPrint('✅ Game initialized - myScore: $_myScore, opponentScore: $_opponentScore, currentPlayer: $_currentPlayerId');
    
    notifyListeners();
  }

  void _handleScoreUpdated(dynamic data) {
    // debugPrint('📊 Score updated: $data');
    
    final oldDartsThrown = _dartsThrown;
    
    // Backend sends player1Score and player2Score directly
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    
    // Determine which score is mine based on currentPlayerId
    if (player1Score != null && player2Score != null) {
      // Check if I'm player1 or player2 by comparing with initial game_started event
      // For now, update both scores - this will work regardless of player order
      if (_myUserId != null && _opponentUserId != null) {
        // We need to figure out which player is which
        // This is tricky without knowing the original player1Id/player2Id mapping
        // For now, just update the scores directly
        _myScore = player1Score;
        _opponentScore = player2Score;
      }
    }
    
    _lastThrow = data['notation'] as String?;
    _dartsThrown = data['dartsThrown'] as int? ?? _dartsThrown;
    
    // DON'T update currentPlayerId here - it should only change in round_complete
    // This prevents premature turn switching after each dart
    
    // debugPrint('   Darts thrown: $oldDartsThrown -> $_dartsThrown');
    // debugPrint('   Current player stays: $_currentPlayerId (not switching until round complete)');
    // debugPrint('   Is my turn: $isMyTurn');
    
    notifyListeners();
  }

  void _handleRoundReadyConfirm(dynamic data) {
    debugPrint('✅ Round ready to confirm: $data');
    debugPrint('   3 darts thrown - waiting for user confirmation');
    
    _pendingConfirmation = true;
    notifyListeners();
  }

  void _handleRoundComplete(dynamic data) {
    debugPrint('🎯 Round complete: $data');
    
    final oldCurrentPlayer = _currentPlayerId;
    
    _dartsThrown = 0;
    _currentRoundThrows = [];
    _currentPlayerId = data['nextPlayerId'] as String?;
    _pendingConfirmation = false;
    
    debugPrint('   🔄 Turn switched: $oldCurrentPlayer -> $_currentPlayerId');
    debugPrint('   🎲 Is my turn now: $isMyTurn');
    
    // Backend sends player1Score and player2Score directly
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    
    if (player1Score != null && player2Score != null) {
      _myScore = player1Score;
      _opponentScore = player2Score;
      debugPrint('   📊 Final scores: player1=$player1Score, player2=$player2Score');
    }
    
    notifyListeners();
  }
  
  void confirmRound() {
    // Auto-fill remaining darts with 0s if less than 3
    while (_currentRoundThrows.length < 3) {
      debugPrint('🔢 Auto-filling dart ${_currentRoundThrows.length + 1} with 0');
      throwDart(baseScore: 0, multiplier: ScoreMultiplier.single);
    }
    
    // Emit confirm event if pending, otherwise force it
    debugPrint('✅ User confirmed round - emitting confirm_round event');
    SocketService.emit('confirm_round', {
      'matchId': _matchId,
      'playerId': _myUserId,
    });
  }
  
  void cancelConfirmation() {
    if (_pendingConfirmation) {
      debugPrint('↩️ User cancelled confirmation - returning to throw editing');
      _pendingConfirmation = false;
      notifyListeners();
    }
  }

  void _handleGameWon(dynamic data) {
    debugPrint('🏆 Game won: $data');
    
    // Prevent duplicate processing if game already ended
    if (_gameEnded) {
      debugPrint('⚠️ Game already ended, ignoring duplicate game_won event');
      return;
    }
    
    _winnerId = data['winnerId'] as String?;
    _gameEnded = true;
    
    notifyListeners();
  }

  void _handleMatchEnded(dynamic data) {
    debugPrint('🏁 Match ended: $data');
    
    // Prevent duplicate processing if game already ended
    if (_gameEnded) {
      debugPrint('⚠️ Game already ended, ignoring duplicate match_ended event');
      return;
    }
    
    _winnerId = data['winnerId'] as String?;
    _gameEnded = true;
    
    notifyListeners();
  }

  void _handleInvalidThrow(dynamic data) {
    debugPrint('❌ Invalid throw: $data');
    
    final message = data['message'] as String? ?? 'Invalid throw';
    
    // Update scores and state
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    if (player1Score != null && player2Score != null) {
      _myScore = player1Score;
      _opponentScore = player2Score;
    }
    
    _currentPlayerId = data['currentPlayerId'] as String?;
    _dartsThrown = data['dartsThrown'] as int? ?? 0;
    _currentRoundThrows = [];
    
    debugPrint('   ⚠️ $message - Turn switched');
    
    notifyListeners();
  }

  void _handleMustFinishDouble(dynamic data) {
    debugPrint('⚠️ Must finish on double: $data');
    
    // Update scores and state
    final player1Score = data['player1Score'] as int?;
    final player2Score = data['player2Score'] as int?;
    if (player1Score != null && player2Score != null) {
      _myScore = player1Score;
      _opponentScore = player2Score;
    }
    
    _currentPlayerId = data['currentPlayerId'] as String?;
    _dartsThrown = data['dartsThrown'] as int? ?? 0;
    _currentRoundThrows = [];
    
    debugPrint('   ⚠️ Score reset - must finish on double');
    
    notifyListeners();
  }

  Future<void> throwDart({
    required int baseScore,
    required ScoreMultiplier multiplier,
  }) async {
    if (!isMyTurn || _currentRoundThrows.length >= 3 || _gameEnded) {
      debugPrint('❌ Cannot throw dart: not your turn or round complete');
      return;
    }

    try {
      final isDouble = multiplier == ScoreMultiplier.double;
      final isTriple = multiplier == ScoreMultiplier.triple;
      final notation = _getScoreNotation(baseScore, multiplier);
      
      debugPrint('🎯 Throwing dart: $notation (baseScore: $baseScore, double: $isDouble, triple: $isTriple)');
      
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
      
      debugPrint('   📍 Dart added to round: ${_currentRoundThrows.length}/3');
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error throwing dart: $e');
    }
  }

  void editDartThrow(int index, int baseScore, ScoreMultiplier multiplier) {
    if (index < 0 || index >= _currentRoundThrows.length) {
      debugPrint('❌ Invalid dart index for editing: $index');
      return;
    }
    
    final notation = _getScoreNotation(baseScore, multiplier);
    _currentRoundThrows[index] = notation;
    
    debugPrint('✏️ Edited dart at index $index to: $notation');
    notifyListeners();
  }

  void deleteDartThrow(int index) {
    if (index < 0 || index >= _currentRoundThrows.length) {
      debugPrint('❌ Invalid dart index for deletion: $index');
      return;
    }
    
    _currentRoundThrows.removeAt(index);
    debugPrint('🗑️ Deleted dart at index $index');
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

  void _cleanupSocketListeners() {
    SocketService.off('game_started');
    SocketService.off('score_updated');
    SocketService.off('round_complete');
    SocketService.off('game_won');
    SocketService.off('match_ended');
  }

  void setRemoteUser(int? uid) {
    _remoteUid = uid;
    debugPrint('📹 Remote user ${uid != null ? "joined: uid=$uid" : "left"}');
    notifyListeners();
  }
  
  void setLocalUserJoined(bool joined) {
    _localUserJoined = joined;
    debugPrint('📹 Local user joined: $joined');
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
    _dartsThrown = 0;
    _gameStarted = false;
    _gameEnded = false;
    _winnerId = null;
    _lastThrow = null;
    _currentRoundThrows = [];
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

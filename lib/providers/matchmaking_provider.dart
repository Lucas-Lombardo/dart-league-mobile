import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/matchmaking_service.dart';
import '../services/socket_service.dart';
import '../utils/haptic_service.dart';
import 'game_provider.dart';

class MatchmakingProvider with ChangeNotifier {
  bool _isSearching = false;
  bool _matchFound = false;
  String? _matchId;
  String? _opponentId;
  String? _opponentUsername;
  int? _opponentElo;
  int? _playerElo;
  int _eloRange = 100;
  int _searchTime = 0;
  Timer? _searchTimer;
  
  // Agora video credentials
  String? _agoraAppId;
  String? _agoraToken;
  String? _agoraChannelName;
  GameProvider? _gameProvider;
  String? _errorMessage;
  String? _currentUserId; // Store userId for initGame call

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
  String? get agoraChannelName => _agoraChannelName;
  String? get errorMessage => _errorMessage;

  void setGameProvider(GameProvider provider) {
    _gameProvider = provider;
  }

  Future<void> joinQueue(String userId) async {
    try {
      // Reset ALL state from previous match before starting new search
      _matchFound = false;
      _matchId = null;
      _opponentId = null;
      _opponentUsername = null;
      _opponentElo = null;
      _agoraAppId = null;
      _agoraToken = null;
      _agoraChannelName = null;
      _errorMessage = null;
      _currentUserId = userId;
      notifyListeners();

      await SocketService.ensureConnected();

      // Ensure game listeners are set up now that socket is connected
      _gameProvider?.ensureListenersSetup();

      // Setup reconnection handler to re-register listeners
      SocketService.setReconnectHandler(() {
        _setupSocketListeners();
        _gameProvider?.ensureListenersSetup();
      });

      _setupSocketListeners();

      final response = await MatchmakingService.joinQueue(userId);

      _playerElo = response['playerElo'] as int?;
      
      // Only update these if match wasn't already found via socket
      // (socket event can arrive before HTTP response)
      if (!_matchFound) {
        _isSearching = true;
        _searchTime = 0;
        _eloRange = 100;
        _matchId = null;
        _opponentId = null;
        _opponentUsername = null;
        _opponentElo = null;
        _agoraAppId = null;
        _agoraToken = null;
        _agoraChannelName = null;
      }
      
      notifyListeners();
      _startSearchTimer();
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _isSearching = false;
      notifyListeners();
    }
  }

  void _setupSocketListeners() {
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
    _searchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _searchTime++;
      notifyListeners();
    });
  }

  void _stopSearchTimer() {
    _searchTimer?.cancel();
    _searchTimer = null;
  }

  void _handleMatchFound(dynamic data) {
    
    HapticService.heavyImpact();
    
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
    final newAgoraChannelName = data['agoraChannelName'] as String?;
    
    if (newAgoraAppId != null && newAgoraToken != null && newAgoraChannelName != null) {
      _agoraAppId = newAgoraAppId;
      _agoraToken = newAgoraToken;
      _agoraChannelName = newAgoraChannelName;
    }
    
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
        agoraChannelName: _agoraChannelName,
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
    try {
      await MatchmakingService.leaveQueue(userId);

      _cleanupSocketListeners();
      _stopSearchTimer();

      _isSearching = false;
      _searchTime = 0;
      _eloRange = 100;
      _matchFound = false;
      _matchId = null;
      _opponentId = null;
      _opponentUsername = null;
      _opponentElo = null;
      _playerElo = null;
      _agoraAppId = null;
      _agoraToken = null;
      _agoraChannelName = null;
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
    _stopSearchTimer();
    SocketService.clearReconnectHandler();
    _cleanupSocketListeners();
    super.dispose();
  }
}

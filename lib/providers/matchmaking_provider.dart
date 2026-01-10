import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/socket_service.dart';
import '../services/matchmaking_service.dart';

class MatchmakingProvider with ChangeNotifier {
  bool _isSearching = false;
  int _searchTime = 0;
  int _eloRange = 100;
  bool _matchFound = false;
  String? _matchId;
  String? _opponentId;
  String? _opponentUsername;
  int? _opponentElo;
  int? _playerElo;
  String? _errorMessage;
  Timer? _searchTimer;

  bool get isSearching => _isSearching;
  int get searchTime => _searchTime;
  int get eloRange => _eloRange;
  bool get matchFound => _matchFound;
  String? get matchId => _matchId;
  String? get opponentId => _opponentId;
  String? get opponentUsername => _opponentUsername;
  int? get opponentElo => _opponentElo;
  int? get playerElo => _playerElo;
  String? get errorMessage => _errorMessage;

  Future<void> joinQueue(String userId) async {
    try {
      debugPrint('🎮 Attempting to join queue via HTTP...');
      _errorMessage = null;
      notifyListeners();

      await SocketService.ensureConnected();
      debugPrint('✅ Socket connection ensured');

      _setupSocketListeners();
      debugPrint('✅ Socket listeners set up');

      final response = await MatchmakingService.joinQueue(userId);
      debugPrint('✅ HTTP join response: $response');

      _isSearching = true;
      _searchTime = 0;
      _eloRange = 100;
      _playerElo = response['playerElo'] as int?;

      if (response['matched'] == true) {
        debugPrint('✅ Immediate match found!');
        _handleMatchFound({
          'matchId': response['matchId'],
          'opponentId': response['opponentId'],
          'playerElo': response['playerElo'],
          'opponentElo': response['opponentElo'],
        });
      } else {
        _matchFound = false;
        _matchId = null;
        _opponentId = null;
        _opponentUsername = null;
        _opponentElo = null;
        notifyListeners();
        _startSearchTimer();
      }
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
    debugPrint('🎮 Match found: $data');
    
    _stopSearchTimer();
    _matchFound = true;
    _matchId = data['matchId'] as String?;
    _opponentId = data['opponentId'] as String?;
    _opponentUsername = data['opponentUsername'] as String?;
    _opponentElo = data['opponentElo'] as int?;
    _playerElo = data['playerElo'] as int?;
    _isSearching = false;
    
    if (_matchId != null) {
      try {
        SocketService.emit('join_room', {'roomId': _matchId});
        debugPrint('✅ Emitted join_room for matchId: $_matchId');
      } catch (e) {
        debugPrint('❌ Failed to emit join_room: $e');
      }
    }
    
    notifyListeners();
  }

  void _handleSearchingExpanded(dynamic data) {
    debugPrint('🔍 Search expanded: $data');
    
    if (data is Map && data['range'] != null) {
      _eloRange = data['range'] as int;
      notifyListeners();
    }
  }

  void _handleQueueError(dynamic data) {
    debugPrint('❌ Queue error: $data');
    
    _errorMessage = data['message'] as String? ?? 'Queue error occurred';
    _isSearching = false;
    _stopSearchTimer();
    notifyListeners();
  }

  Future<void> leaveQueue(String userId) async {
    try {
      debugPrint('🚪 Leaving queue via HTTP...');
      await MatchmakingService.leaveQueue(userId);
      debugPrint('✅ Left queue successfully');

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
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Error leaving queue: $e');
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
    _cleanupSocketListeners();
    super.dispose();
  }
}

import 'package:flutter/foundation.dart';
import '../services/placement_service.dart';

class PlacementStatus {
  final int matchesPlayed;
  final int wins;
  final int losses;
  final bool isComplete;
  final int? nextMatchNumber;
  final int? nextBotDifficulty;
  final String? nextBotName;
  final List<PlacementResult> results;

  PlacementStatus({
    required this.matchesPlayed,
    required this.wins,
    required this.losses,
    required this.isComplete,
    this.nextMatchNumber,
    this.nextBotDifficulty,
    this.nextBotName,
    required this.results,
  });

  factory PlacementStatus.fromJson(Map<String, dynamic> json) {
    return PlacementStatus(
      matchesPlayed: json['matchesPlayed'] as int? ?? 0,
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
      isComplete: json['isComplete'] as bool? ?? false,
      nextMatchNumber: json['nextMatchNumber'] as int?,
      nextBotDifficulty: json['nextBotDifficulty'] as int?,
      nextBotName: json['nextBotName'] as String?,
      results: (json['results'] as List<dynamic>?)
              ?.map((r) => PlacementResult.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class PlacementResult {
  final int matchNumber;
  final int botDifficulty;
  final String botName;
  final bool won;

  PlacementResult({
    required this.matchNumber,
    required this.botDifficulty,
    required this.botName,
    required this.won,
  });

  factory PlacementResult.fromJson(Map<String, dynamic> json) {
    return PlacementResult(
      matchNumber: json['matchNumber'] as int? ?? 0,
      botDifficulty: json['botDifficulty'] as int? ?? 0,
      botName: json['botName'] as String? ?? 'Bot',
      won: json['won'] as bool? ?? false,
    );
  }
}

class BotThrow {
  final int baseScore;
  final bool isDouble;
  final bool isTriple;
  final int score;
  final String notation;

  BotThrow({
    required this.baseScore,
    required this.isDouble,
    required this.isTriple,
    required this.score,
    required this.notation,
  });

  factory BotThrow.fromJson(Map<String, dynamic> json) {
    return BotThrow(
      baseScore: json['baseScore'] as int? ?? 0,
      isDouble: json['isDouble'] as bool? ?? false,
      isTriple: json['isTriple'] as bool? ?? false,
      score: json['score'] as int? ?? 0,
      notation: json['notation'] as String? ?? 'S0',
    );
  }
}

class ActivePlacementMatch {
  final String matchId;
  final int botDifficulty;
  final String botName;
  final int player1Score;
  final int player2Score;
  final List<int> player1Rounds;
  final List<int> player2Rounds;
  final List<List<String>> player1RoundThrows;
  final List<List<String>> player2RoundThrows;

  ActivePlacementMatch({
    required this.matchId,
    required this.botDifficulty,
    required this.botName,
    required this.player1Score,
    required this.player2Score,
    required this.player1Rounds,
    required this.player2Rounds,
    required this.player1RoundThrows,
    required this.player2RoundThrows,
  });

  factory ActivePlacementMatch.fromJson(Map<String, dynamic> json) {
    final gameState = json['gameState'] as Map<String, dynamic>? ?? {};
    return ActivePlacementMatch(
      matchId: json['matchId'] as String? ?? '',
      botDifficulty: json['botDifficulty'] as int? ?? 1,
      botName: json['botName'] as String? ?? 'Bot',
      player1Score: gameState['player1Score'] as int? ?? 501,
      player2Score: gameState['player2Score'] as int? ?? 501,
      player1Rounds: (gameState['player1Rounds'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      player2Rounds: (gameState['player2Rounds'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          [],
      player1RoundThrows: (gameState['player1RoundThrows'] as List<dynamic>?)
              ?.map((r) =>
                  (r as List<dynamic>).map((e) => e.toString()).toList())
              .toList() ??
          [],
      player2RoundThrows: (gameState['player2RoundThrows'] as List<dynamic>?)
              ?.map((r) =>
                  (r as List<dynamic>).map((e) => e.toString()).toList())
              .toList() ??
          [],
    );
  }
}

class PlacementProvider extends ChangeNotifier {
  PlacementStatus? _status;
  ActivePlacementMatch? _activeMatch;
  bool _isLoading = false;
  String? _error;

  // Active match state
  String? _currentMatchId;
  int? _currentBotDifficulty;
  int _player1Score = 501;
  int _player2Score = 501;
  bool _isPlayerTurn = true;
  List<BotThrow> _lastBotThrows = [];
  bool _botIsCheckout = false;
  bool _botIsBust = false;

  PlacementStatus? get status => _status;
  ActivePlacementMatch? get activeMatch => _activeMatch;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get currentMatchId => _currentMatchId;
  int? get currentBotDifficulty => _currentBotDifficulty;
  int get player1Score => _player1Score;
  int get player2Score => _player2Score;
  bool get isPlayerTurn => _isPlayerTurn;
  List<BotThrow> get lastBotThrows => _lastBotThrows;
  bool get botIsCheckout => _botIsCheckout;
  bool get botIsBust => _botIsBust;

  Future<void> loadStatus() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await PlacementService.getStatus();
      _status = PlacementStatus.fromJson(response);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadActiveMatch() async {
    try {
      final response = await PlacementService.getActiveMatch();
      if (response['active'] == true) {
        _activeMatch = ActivePlacementMatch.fromJson(response);
      } else {
        _activeMatch = null;
      }
    } catch (e) {
      _activeMatch = null;
    } finally {
      notifyListeners();
    }
  }

  void clearActiveMatch() {
    _activeMatch = null;
    notifyListeners();
  }

  void resumeFromActiveMatch(ActivePlacementMatch match) {
    _currentMatchId = match.matchId;
    _currentBotDifficulty = match.botDifficulty;
    _player1Score = match.player1Score;
    _player2Score = match.player2Score;
    _isPlayerTurn = true;
    _lastBotThrows = [];
    _botIsCheckout = false;
    _botIsBust = false;
    notifyListeners();
  }

  Future<bool> startMatch() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await PlacementService.startMatch();
      _currentMatchId = response['matchId'] as String?;
      _currentBotDifficulty = response['botDifficulty'] as int?;

      final gameState = response['gameState'] as Map<String, dynamic>?;
      if (gameState != null) {
        _player1Score = gameState['player1Score'] as int? ?? 501;
        _player2Score = gameState['player2Score'] as int? ?? 501;
        _isPlayerTurn = true;
      }

      _lastBotThrows = [];
      _botIsCheckout = false;
      _botIsBust = false;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> triggerBotTurn({int? playerRoundScore, List<String>? playerRoundThrows}) async {
    if (_currentMatchId == null) return false;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await PlacementService.triggerBotTurn(
        _currentMatchId!,
        playerRoundScore: playerRoundScore,
        playerRoundThrows: playerRoundThrows,
      );

      _lastBotThrows = (response['botThrows'] as List<dynamic>?)
              ?.map((t) => BotThrow.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [];
      _botIsCheckout = response['isCheckout'] as bool? ?? false;
      _botIsBust = response['isBust'] as bool? ?? false;

      final gameState = response['gameState'] as Map<String, dynamic>?;
      if (gameState != null) {
        _player1Score = gameState['player1Score'] as int? ?? _player1Score;
        _player2Score = gameState['player2Score'] as int? ?? _player2Score;
        _isPlayerTurn = true;
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> completeMatch(String? winnerId, {int? player1Score}) async {
    if (_currentMatchId == null) return null;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await PlacementService.completeMatch(
        _currentMatchId!,
        winnerId,
        player1Score: player1Score,
      );

      _currentMatchId = null;
      _currentBotDifficulty = null;
      _activeMatch = null;

      if (response['placementStatus'] != null) {
        _status = PlacementStatus.fromJson(
          response['placementStatus'] as Map<String, dynamic>,
        );
      }

      _isLoading = false;
      notifyListeners();
      return response;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  void updateScoresFromGameState(Map<String, dynamic> gameState) {
    _player1Score = gameState['player1Score'] as int? ?? _player1Score;
    _player2Score = gameState['player2Score'] as int? ?? _player2Score;
    notifyListeners();
  }

  void reset() {
    _status = null;
    _activeMatch = null;
    _currentMatchId = null;
    _currentBotDifficulty = null;
    _player1Score = 501;
    _player2Score = 501;
    _isPlayerTurn = true;
    _lastBotThrows = [];
    _botIsCheckout = false;
    _botIsBust = false;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _status = null;
    _currentMatchId = null;
    _currentBotDifficulty = null;
    _error = null;
    _lastBotThrows = [];
    super.dispose();
  }
}

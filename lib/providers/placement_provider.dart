import 'package:flutter/foundation.dart';
import '../models/bot_match_config.dart';
import '../models/bot_rank.dart';
import '../models/training.dart';
import '../services/bot_training_service.dart';
import '../services/placement_service.dart';
import '../services/training_service.dart';

/// The network calls of a placement / bot match. A seam so tests can stand in
/// for the server; the app always uses the default, which forwards to the
/// static services.
class PlacementApi {
  const PlacementApi();

  Future<Map<String, dynamic>> getStatus() => PlacementService.getStatus();

  Future<Map<String, dynamic>> getActiveMatch() =>
      PlacementService.getActiveMatch();

  Future<Map<String, dynamic>> startMatch() => PlacementService.startMatch();

  Future<Map<String, dynamic>> botTurn(
    String matchId, {
    int? playerRoundScore,
    List<String>? playerRoundThrows,
    bool? playerBusted,
    List<Map<String, dynamic>>? playerRoundDarts,
    int? visitIndex,
  }) =>
      PlacementService.triggerBotTurn(
        matchId,
        playerRoundScore: playerRoundScore,
        playerRoundThrows: playerRoundThrows,
        playerBusted: playerBusted,
        playerRoundDarts: playerRoundDarts,
        visitIndex: visitIndex,
      );

  Future<Map<String, dynamic>> completeMatch(
    String matchId,
    String? winnerId, {
    int? player1Score,
  }) =>
      PlacementService.completeMatch(matchId, winnerId,
          player1Score: player1Score);

  Future<Map<String, dynamic>> trainingBotTurn({
    required BotRank rank,
    required int botRemaining,
  }) =>
      BotTrainingService.botTurn(rank: rank, botRemaining: botRemaining);
}

/// True when retrying cannot help: the server refused the call itself (the
/// match was forfeited or cancelled under the player's feet, it is not theirs,
/// it is already over). Timeouts, lost connections and 5xx are worth a retry.
/// ApiService throws plain Exceptions, so the status lives in the message.
bool isPermanentPlacementError(Object error) {
  final m = error.toString();
  return m.contains('Error 400') ||
      m.contains('Error 409') ||
      m.contains('Error 422') ||
      m.contains('Not found') ||
      m.contains('Forbidden') ||
      m.contains('Unauthorized');
}

/// Distinguishes a placement match (counts toward ranking) from a bot-training
/// match (no progression — submitted as a TrainingSession at the end).
enum PlacementMode { placement, botTraining }

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
  PlacementProvider({
    PlacementApi api = const PlacementApi(),
    List<Duration> retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 3),
    ],
  })  : _api = api,
        _retryDelays = retryDelays;

  final PlacementApi _api;

  /// Waits between automatic attempts of a bot turn or a result save: the
  /// first call plus one retry per entry. After that the screen shows the
  /// failure with "Retry" and "Leave" instead of a frozen bot or a dead end.
  final List<Duration> _retryDelays;

  PlacementStatus? _status;
  ActivePlacementMatch? _activeMatch;
  bool _isLoading = false;
  String? _error;

  /// The last failure cannot be fixed by retrying (match gone or over).
  bool _errorIsPermanent = false;

  /// How many of the player's visits the server holds (sent as visitIndex).
  int _serverVisits = 0;

  /// The bot turn that failed, kept as-is so a retry sends the same visit.
  Future<bool> Function()? _pendingBotTurn;

  /// Visit totals of a resumed match (bust = 0), to restore the averages.
  List<int> _resumedPlayerRounds = const [];
  List<int> _resumedBotRounds = const [];

  // Active match state
  PlacementMode _mode = PlacementMode.placement;
  BotRank? _botRank;
  BotMatchConfig? _botConfig;
  String? _currentMatchId;
  int? _currentBotDifficulty;
  int _startingScore = 501;
  int _player1Score = 501;
  int _player2Score = 501;
  bool _isPlayerTurn = true;
  List<BotThrow> _lastBotThrows = [];
  bool _botIsCheckout = false;
  bool _botIsBust = false;

  // Bot-training series state (placement stays a single leg: bestOf 1).
  int _myLegs = 0;
  int _botLegs = 0;
  int _currentLeg = 1;
  bool _playerStartsLeg = true;

  PlacementStatus? get status => _status;
  ActivePlacementMatch? get activeMatch => _activeMatch;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get errorIsPermanent => _errorIsPermanent;
  bool get hasPendingBotTurn => _pendingBotTurn != null;
  List<int> get resumedPlayerRounds => _resumedPlayerRounds;
  List<int> get resumedBotRounds => _resumedBotRounds;
  PlacementMode get mode => _mode;
  BotRank? get botRank => _botRank;
  BotMatchConfig? get botConfig => _botConfig;
  String? get currentMatchId => _currentMatchId;
  int? get currentBotDifficulty => _currentBotDifficulty;
  int get startingScore => _startingScore;
  int get player1Score => _player1Score;
  int get player2Score => _player2Score;
  bool get isPlayerTurn => _isPlayerTurn;
  List<BotThrow> get lastBotThrows => _lastBotThrows;
  bool get botIsCheckout => _botIsCheckout;
  bool get botIsBust => _botIsBust;

  int get bestOf => _botConfig?.bestOf ?? 1;
  int get legsToWin => _botConfig?.legsToWin ?? 1;
  int get myLegs => _myLegs;
  int get botLegs => _botLegs;
  int get currentLeg => _currentLeg;

  /// Whether the player throws first in the current leg. Leg 1 is the
  /// player's, then the starter alternates like an online series.
  bool get playerStartsLeg => _playerStartsLeg;

  bool get botMatchOver => _myLegs >= legsToWin || _botLegs >= legsToWin;

  /// Ends the current bot-training leg. Returns true when the series is over.
  bool recordBotLegResult({required bool playerWon}) {
    if (playerWon) {
      _myLegs++;
    } else {
      _botLegs++;
    }
    notifyListeners();
    return botMatchOver;
  }

  /// Resets scores for the next leg of a bot-training series and flips the
  /// starter, mirroring the online alternation.
  void startNextBotLeg() {
    _currentLeg++;
    _playerStartsLeg = !_playerStartsLeg;
    _player1Score = _startingScore;
    _player2Score = _startingScore;
    _isPlayerTurn = _playerStartsLeg;
    _lastBotThrows = [];
    _botIsCheckout = false;
    _botIsBust = false;
    notifyListeners();
  }

  Future<void> loadStatus() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await _api.getStatus();
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
      final response = await _api.getActiveMatch();
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

  /// Creates the server match — or picks up the one in progress, which the
  /// server returns as-is. Called when the player presses "Play" on the camera
  /// screen, never before: a match created at the hub died on the cron's idle
  /// sweep while the player was still setting up the tripod.
  Future<bool> startMatch() async {
    _isLoading = true;
    _error = null;
    _errorIsPermanent = false;
    _pendingBotTurn = null;
    _mode = PlacementMode.placement;
    _botRank = null;
    _botConfig = null;
    _startingScore = 501;
    notifyListeners();

    try {
      final response = await _withRetries(_api.startMatch);
      _currentMatchId = response['matchId'] as String?;
      _currentBotDifficulty = response['botDifficulty'] as int?;
      if (_currentMatchId == null) {
        throw Exception('Invalid response from server');
      }

      final gameState = response['gameState'] as Map<String, dynamic>?;
      _player1Score = 501;
      _player2Score = 501;
      _resumedPlayerRounds = const [];
      _resumedBotRounds = const [];
      if (gameState != null) {
        _player1Score = gameState['player1Score'] as int? ?? 501;
        _player2Score = gameState['player2Score'] as int? ?? 501;
        _resumedPlayerRounds = _intList(gameState['player1Rounds']);
        _resumedBotRounds = _intList(gameState['player2Rounds']);
        _isPlayerTurn = true;
      }
      // A resumed match: the server already holds these visits.
      _serverVisits = _resumedPlayerRounds.length;

      _lastBotThrows = [];
      _botIsCheckout = false;
      _botIsBust = false;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _errorIsPermanent = isPermanentPlacementError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  static List<int> _intList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<num>().map((e) => e.toInt()).toList();
  }

  /// [call], retried on transient failures with [_retryDelays] between
  /// attempts. A permanent refusal (see [isPermanentPlacementError]) is
  /// rethrown at once.
  Future<T> _withRetries<T>(Future<T> Function() call) async {
    var attempt = 0;
    while (true) {
      try {
        return await call();
      } catch (e) {
        if (isPermanentPlacementError(e) || attempt >= _retryDelays.length) {
          rethrow;
        }
        await Future<void>.delayed(_retryDelays[attempt]);
        attempt++;
      }
    }
  }

  /// Start a bot-training match (no backend match record — the result is
  /// submitted as a TrainingSession when the game ends).
  /// When the current bot match started (progression: training duration).
  DateTime? _botMatchStartedAt;

  void startBotTrainingMatch(BotMatchConfig config) {
    _botMatchStartedAt = DateTime.now();
    _mode = PlacementMode.botTraining;
    _botRank = config.rank;
    _botConfig = config;
    _currentMatchId = 'training-${DateTime.now().millisecondsSinceEpoch}';
    _currentBotDifficulty = null;
    _startingScore = config.startingScore;
    _player1Score = config.startingScore;
    _player2Score = config.startingScore;
    _isPlayerTurn = true;
    _myLegs = 0;
    _botLegs = 0;
    _currentLeg = 1;
    _playerStartsLeg = true;
    _lastBotThrows = [];
    _botIsCheckout = false;
    _botIsBust = false;
    _error = null;
    _errorIsPermanent = false;
    _pendingBotTurn = null;
    _resumedPlayerRounds = const [];
    _resumedBotRounds = const [];
    _isLoading = false;
    notifyListeners();
  }

  /// Sends the bot turn that failed again, with the same visit and the same
  /// visit index (so a server that did record it replays its answer).
  Future<bool> retryBotTurn() async {
    final pending = _pendingBotTurn;
    if (pending == null) return false;
    return pending();
  }

  /// Plays the bot's visit (after the player's, which rides along). Retried
  /// automatically on transient failures; when it still fails the turn is
  /// kept in [hasPendingBotTurn] for [retryBotTurn] and false is returned —
  /// the screen must then stop, never hand the turn back to the player as if
  /// the bot had thrown (that froze the bot at 501 for the rest of the match).
  Future<bool> triggerBotTurn({
    int? playerRoundScore,
    List<String>? playerRoundThrows,
    int? playerScoreAfterRound,
    bool? playerBusted,
    List<Map<String, dynamic>>? playerRoundDarts,
  }) async {
    if (_currentMatchId == null) return false;
    // Fixed now, so a retry sends exactly the same request.
    final visitIndex = _serverVisits;
    Future<bool> attempt() => _botTurn(
          playerRoundScore: playerRoundScore,
          playerRoundThrows: playerRoundThrows,
          playerScoreAfterRound: playerScoreAfterRound,
          playerBusted: playerBusted,
          playerRoundDarts: playerRoundDarts,
          visitIndex: visitIndex,
        );
    _pendingBotTurn = attempt;
    return attempt();
  }

  Future<bool> _botTurn({
    int? playerRoundScore,
    List<String>? playerRoundThrows,
    int? playerScoreAfterRound,
    bool? playerBusted,
    List<Map<String, dynamic>>? playerRoundDarts,
    required int visitIndex,
  }) async {
    _isLoading = true;
    _error = null;
    _errorIsPermanent = false;
    notifyListeners();

    try {
      if (_mode == PlacementMode.botTraining) {
        if (_botRank == null) {
          _error = 'Missing bot rank for training match';
          _errorIsPermanent = true;
          _isLoading = false;
          notifyListeners();
          return false;
        }
        if (playerScoreAfterRound != null) {
          _player1Score = playerScoreAfterRound;
        }
        // Stateless on the server: retrying is always safe.
        final response = await _withRetries(() => _api.trainingBotTurn(
              rank: _botRank!,
              botRemaining: _player2Score,
            ));
        _lastBotThrows = (response['botThrows'] as List<dynamic>?)
                ?.map((t) => BotThrow.fromJson(t as Map<String, dynamic>))
                .toList() ??
            [];
        _botIsCheckout = response['isCheckout'] as bool? ?? false;
        _botIsBust = response['isBust'] as bool? ?? false;
        _player2Score = response['botNewScore'] as int? ?? _player2Score;
        _isPlayerTurn = true;
        _pendingBotTurn = null;
        _isLoading = false;
        notifyListeners();
        return true;
      }

      final matchId = _currentMatchId!;
      final response = await _withRetries(() => _api.botTurn(
            matchId,
            playerRoundScore: playerRoundScore,
            playerRoundThrows: playerRoundThrows,
            playerRoundDarts: playerRoundDarts,
            playerBusted: playerBusted,
            visitIndex: visitIndex,
          ));
      if (playerRoundThrows != null) _serverVisits = visitIndex + 1;

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

      _pendingBotTurn = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _errorIsPermanent = isPermanentPlacementError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> completeMatch(
    String? winnerId, {
    int? player1Score,
    String? currentUserId,
    int? dartsThrown,
    double? matchPlayerAverage,
    Map<String, dynamic>? extraDetails,
  }) async {
    if (_currentMatchId == null) return null;

    _isLoading = true;
    _error = null;
    _errorIsPermanent = false;
    notifyListeners();

    try {
      if (_mode == PlacementMode.botTraining) {
        final won = winnerId != null && winnerId == currentUserId;
        final rank = _botRank;
        final config = _botConfig;
        await TrainingService.submit(
          startedAt: _botMatchStartedAt,
          type: TrainingType.botTraining,
          score: won ? 1 : 0,
          dartsThrown: dartsThrown ?? 0,
          details: {
            'rank': rank?.apiValue,
            'targetAverage': rank?.targetAverage,
            'won': won,
            'startingScore': _startingScore,
            // Stats bucket + format — additive keys the backend groups on.
            // Historic sessions have neither; their bucket is derived from
            // startingScore server-side.
            if (config != null) 'mode': config.modeWire,
            if (config != null) 'format': config.bestOf,
            'legsWon': _myLegs,
            'legsLost': _botLegs,
            'player1RemainingAtEnd': player1Score ?? _player1Score,
            'player2RemainingAtEnd': _player2Score,
            if (matchPlayerAverage != null) 'playerAverage': matchPlayerAverage,
            if (extraDetails != null) ...extraDetails,
          },
        );
        _currentMatchId = null;
        _currentBotDifficulty = null;
        _botRank = null;
        _botConfig = null;
        _mode = PlacementMode.placement;
        _activeMatch = null;
        _isLoading = false;
        notifyListeners();
        return {
          'botTraining': true,
          'won': won,
          'matchPlayerAverage': matchPlayerAverage,
        };
      }

      final matchId = _currentMatchId!;
      Map<String, dynamic> response;
      try {
        response = await _withRetries(() => _api.completeMatch(
              matchId,
              winnerId,
              player1Score: player1Score,
            ));
      } catch (e) {
        // An earlier attempt went through and only its answer was lost: the
        // match is saved, carry on (the hub reloads the status).
        if (!e.toString().contains('already completed')) rethrow;
        response = <String, dynamic>{'alreadyCompleted': true};
      }

      _currentMatchId = null;
      _pendingBotTurn = null;
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
      // _currentMatchId is kept: the screen offers "Retry", which calls this
      // again with the same result.
      _error = e.toString();
      _errorIsPermanent = isPermanentPlacementError(e);
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
    _mode = PlacementMode.placement;
    _botRank = null;
    _botConfig = null;
    _myLegs = 0;
    _botLegs = 0;
    _currentLeg = 1;
    _playerStartsLeg = true;
    _startingScore = 501;
    _player1Score = 501;
    _player2Score = 501;
    _isPlayerTurn = true;
    _lastBotThrows = [];
    _botIsCheckout = false;
    _botIsBust = false;
    _error = null;
    _errorIsPermanent = false;
    _pendingBotTurn = null;
    _serverVisits = 0;
    _resumedPlayerRounds = const [];
    _resumedBotRounds = const [];
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

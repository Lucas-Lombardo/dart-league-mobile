DateTime? _tryParseDateTime(String? value) {
  if (value == null) return null;
  try {
    return DateTime.parse(value);
  } on FormatException {
    return null;
  }
}

class Match {
  final String id;
  final String player1Id;
  final String player2Id;
  final String player1Username;
  final String player2Username;
  final bool player1IsPremium;
  final bool player2IsPremium;
  final int player1Score;
  final int player2Score;
  final String winnerId;
  final int player1EloChange;
  final int player2EloChange;
  final DateTime createdAt;
  final String status;
  final String matchType;
  final int? botDifficulty;
  // Non-null when this match is one leg of a ranked BO3 series. History
  // screens group legs sharing a seriesId into a single entry.
  final String? seriesId;
  // Authoritative series context from the history payload (additive; null on
  // older backends). Prefer these over counting leg rows: abandoned series
  // credit the winner legs he never played, and pagination can cut old legs.
  final String? seriesStatus;
  final String? seriesWinnerId;
  final int? seriesPlayer1LegsWon;
  final int? seriesPlayer2LegsWon;
  // Full series summary (legs results, series score) — only present on the
  // match-detail endpoint; null in list payloads and on older backends.
  final MatchSeries? series;
  final List<MatchRound>? rounds;
  final MatchStatistics? statistics;

  Match({
    required this.id,
    required this.player1Id,
    required this.player2Id,
    required this.player1Username,
    required this.player2Username,
    this.player1IsPremium = false,
    this.player2IsPremium = false,
    required this.player1Score,
    required this.player2Score,
    required this.winnerId,
    required this.player1EloChange,
    required this.player2EloChange,
    required this.createdAt,
    required this.status,
    this.matchType = 'ranked',
    this.botDifficulty,
    this.seriesId,
    this.seriesStatus,
    this.seriesWinnerId,
    this.seriesPlayer1LegsWon,
    this.seriesPlayer2LegsWon,
    this.series,
    this.rounds,
    this.statistics,
  });

  bool get isPlacement => matchType == 'placement';

  bool get isSeriesLeg => seriesId != null;

  bool get isInProgress => status == 'in_progress';

  factory Match.fromJson(Map<String, dynamic> json, [String? currentUserId]) {
    // New format: player1/player2 (absolute)
    return Match(
      id: json['id'] as String? ?? '',
      player1Id: json['player1Id'] as String? ?? '',
      player2Id: json['player2Id'] as String? ?? '',
      player1Username: json['player1Username'] as String? ?? 'Unknown',
      player2Username: json['player2Username'] as String? ?? 'Unknown',
      player1IsPremium: json['player1IsPremium'] as bool? ?? false,
      player2IsPremium: json['player2IsPremium'] as bool? ?? false,
      player1Score: json['player1Score'] as int? ?? 501,
      player2Score: json['player2Score'] as int? ?? 501,
      winnerId: json['winnerId'] as String? ?? '',
      player1EloChange: json['player1EloChange'] as int? ?? 0,
      player2EloChange: json['player2EloChange'] as int? ?? 0,
      createdAt: _tryParseDateTime(json['createdAt'] as String?) ?? DateTime.now(),
      status: json['status'] as String? ?? 'completed',
      matchType: json['matchType'] as String? ?? 'ranked',
      botDifficulty: json['botDifficulty'] as int?,
      seriesId: json['seriesId'] as String?,
      seriesStatus: json['seriesStatus'] as String?,
      seriesWinnerId: json['seriesWinnerId'] as String?,
      seriesPlayer1LegsWon: json['seriesPlayer1LegsWon'] as int?,
      seriesPlayer2LegsWon: json['seriesPlayer2LegsWon'] as int?,
      series: json['series'] is Map<String, dynamic>
          ? MatchSeries.fromJson(json['series'] as Map<String, dynamic>)
          : null,
      rounds: _parseRounds(json),
      statistics: json['statistics'] != null
          ? MatchStatistics.fromJson(json['statistics'] as Map<String, dynamic>)
          : null,
    );
  }

  static List<MatchRound>? _parseRounds(Map<String, dynamic> json) {
    final playerRounds = json['playerRounds'] as List<dynamic>?;
    final opponentRounds = json['opponentRounds'] as List<dynamic>?;
    
    if (playerRounds == null && opponentRounds == null) return null;
    
    final rounds = <MatchRound>[];
    
    // Parse player rounds
    if (playerRounds != null) {
      for (var i = 0; i < playerRounds.length; i++) {
        final roundItem = playerRounds[i];
        
        // Handle both object format and simple integer format
        if (roundItem is Map<String, dynamic>) {
          rounds.add(MatchRound(
            roundNumber: i + 1,
            playerId: 'current_user',
            throws: (roundItem['throws'] as List<dynamic>?)
                    ?.map((t) => t.toString())
                    .toList() ??
                [],
            roundScore: roundItem['score'] as int? ?? 0,
          ));
        } else if (roundItem is int) {
          // Backend just sends score as integer
          rounds.add(MatchRound(
            roundNumber: i + 1,
            playerId: 'current_user',
            throws: [],
            roundScore: roundItem,
          ));
        }
      }
    }
    
    // Parse opponent rounds
    if (opponentRounds != null) {
      for (var i = 0; i < opponentRounds.length; i++) {
        final roundItem = opponentRounds[i];
        
        // Handle both object format and simple integer format
        if (roundItem is Map<String, dynamic>) {
          rounds.add(MatchRound(
            roundNumber: i + 1,
            playerId: json['opponentId'] as String? ?? 'opponent',
            throws: (roundItem['throws'] as List<dynamic>?)
                    ?.map((t) => t.toString())
                    .toList() ??
                [],
            roundScore: roundItem['score'] as int? ?? 0,
          ));
        } else if (roundItem is int) {
          // Backend just sends score as integer
          rounds.add(MatchRound(
            roundNumber: i + 1,
            playerId: json['opponentId'] as String? ?? 'opponent',
            throws: [],
            roundScore: roundItem,
          ));
        }
      }
    }
    
    return rounds.isEmpty ? null : rounds;
  }

  bool isWinner(String userId) => winnerId == userId;

  int getEloChange(String userId) {
    return userId == player1Id ? player1EloChange : player2EloChange;
  }

  String getOpponentUsername(String userId) {
    return userId == player1Id ? player2Username : player1Username;
  }

  String getOpponentId(String userId) {
    return userId == player1Id ? player2Id : player1Id;
  }

  bool getOpponentIsPremium(String userId) {
    return userId == player1Id ? player2IsPremium : player1IsPremium;
  }

  int getMyScore(String userId) {
    return userId == player1Id ? player1Score : player2Score;
  }

  int getOpponentScore(String userId) {
    return userId == player1Id ? player2Score : player1Score;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Match && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Summary of a ranked BO3 series as returned by GET /matches/:id for a leg.
class MatchSeries {
  final String id;
  final int bestOf;
  final int player1LegsWon;
  final int player2LegsWon;
  final String? winnerId;
  final String status;
  final List<SeriesLeg> legs;

  MatchSeries({
    required this.id,
    required this.bestOf,
    required this.player1LegsWon,
    required this.player2LegsWon,
    this.winnerId,
    required this.status,
    required this.legs,
  });

  factory MatchSeries.fromJson(Map<String, dynamic> json) {
    return MatchSeries(
      id: json['id'] as String? ?? '',
      bestOf: json['bestOf'] as int? ?? 3,
      player1LegsWon: json['player1LegsWon'] as int? ?? 0,
      player2LegsWon: json['player2LegsWon'] as int? ?? 0,
      winnerId: json['winnerId'] as String?,
      status: json['status'] as String? ?? 'finished',
      legs: (json['legs'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(SeriesLeg.fromJson)
              .toList() ??
          [],
    );
  }
}

/// One leg's result line inside a [MatchSeries].
class SeriesLeg {
  final String id;
  final int legNumber;
  final String status;
  final int? player1Score;
  final int? player2Score;
  final String? winnerId;

  SeriesLeg({
    required this.id,
    required this.legNumber,
    required this.status,
    this.player1Score,
    this.player2Score,
    this.winnerId,
  });

  factory SeriesLeg.fromJson(Map<String, dynamic> json) {
    return SeriesLeg(
      id: json['id'] as String? ?? '',
      legNumber: json['legNumber'] as int? ?? 0,
      status: json['status'] as String? ?? 'finished',
      player1Score: json['player1Score'] as int?,
      player2Score: json['player2Score'] as int?,
      winnerId: json['winnerId'] as String?,
    );
  }
}

class MatchRound {
  final int roundNumber;
  final String playerId;
  final List<String> throws;
  final int roundScore;

  MatchRound({
    required this.roundNumber,
    required this.playerId,
    required this.throws,
    required this.roundScore,
  });

  factory MatchRound.fromJson(Map<String, dynamic> json) {
    return MatchRound(
      roundNumber: json['roundNumber'] as int? ?? 0,
      playerId: json['playerId'] as String? ?? '',
      throws: (json['throws'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toList() ??
          [],
      roundScore: json['roundScore'] as int? ?? 0,
    );
  }
}

class MatchStatistics {
  final PlayerStatistics player1;
  final PlayerStatistics player2;
  final int totalRounds;

  MatchStatistics({
    required this.player1,
    required this.player2,
    required this.totalRounds,
  });

  factory MatchStatistics.fromJson(Map<String, dynamic> json) {
    return MatchStatistics(
      player1: PlayerStatistics.fromJson(json['player1'] as Map<String, dynamic>),
      player2: PlayerStatistics.fromJson(json['player2'] as Map<String, dynamic>),
      totalRounds: json['totalRounds'] as int? ?? 0,
    );
  }
}

class PlayerStatistics {
  final int rounds;
  final double average;
  final int highest;
  final int total180s;
  // Checkout value for this leg (0 if the player didn't win) and finishing-double
  // percentage. Default 0 so older backends without these fields keep working.
  final int checkout;
  final double doublePercentage;

  PlayerStatistics({
    required this.rounds,
    required this.average,
    required this.highest,
    required this.total180s,
    this.checkout = 0,
    this.doublePercentage = 0.0,
  });

  factory PlayerStatistics.fromJson(Map<String, dynamic> json) {
    return PlayerStatistics(
      rounds: json['rounds'] as int? ?? 0,
      average: (json['average'] as num?)?.toDouble() ?? 0.0,
      highest: json['highest'] as int? ?? 0,
      total180s: json['total180s'] as int? ?? 0,
      checkout: json['checkout'] as int? ?? 0,
      doublePercentage: (json['doublePercentage'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

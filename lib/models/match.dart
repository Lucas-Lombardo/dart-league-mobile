class Match {
  final String id;
  final String player1Id;
  final String player2Id;
  final String player1Username;
  final String player2Username;
  final int player1Score;
  final int player2Score;
  final String winnerId;
  final int player1EloChange;
  final int player2EloChange;
  final DateTime createdAt;
  final String status;
  final List<MatchRound>? rounds;
  final MatchStatistics? statistics;

  Match({
    required this.id,
    required this.player1Id,
    required this.player2Id,
    required this.player1Username,
    required this.player2Username,
    required this.player1Score,
    required this.player2Score,
    required this.winnerId,
    required this.player1EloChange,
    required this.player2EloChange,
    required this.createdAt,
    required this.status,
    this.rounds,
    this.statistics,
  });

  factory Match.fromJson(Map<String, dynamic> json, [String? currentUserId]) {
    // New format: player1/player2 (absolute)
    return Match(
      id: json['id'] as String? ?? '',
      player1Id: json['player1Id'] as String? ?? '',
      player2Id: json['player2Id'] as String? ?? '',
      player1Username: json['player1Username'] as String? ?? 'Unknown',
      player2Username: json['player2Username'] as String? ?? 'Unknown',
      player1Score: json['player1Score'] as int? ?? 501,
      player2Score: json['player2Score'] as int? ?? 501,
      winnerId: json['winnerId'] as String? ?? '',
      player1EloChange: json['player1EloChange'] as int? ?? 0,
      player2EloChange: json['player2EloChange'] as int? ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      status: json['status'] as String? ?? 'completed',
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

  int getMyScore(String userId) {
    return userId == player1Id ? player1Score : player2Score;
  }

  int getOpponentScore(String userId) {
    return userId == player1Id ? player2Score : player1Score;
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

  PlayerStatistics({
    required this.rounds,
    required this.average,
    required this.highest,
    required this.total180s,
  });

  factory PlayerStatistics.fromJson(Map<String, dynamic> json) {
    return PlayerStatistics(
      rounds: json['rounds'] as int? ?? 0,
      average: (json['average'] as num?)?.toDouble() ?? 0.0,
      highest: json['highest'] as int? ?? 0,
      total180s: json['total180s'] as int? ?? 0,
    );
  }
}

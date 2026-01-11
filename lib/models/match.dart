import 'package:flutter/foundation.dart';

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
  });

  factory Match.fromJson(Map<String, dynamic> json, [String? currentUserId]) {
    // Backend format: matchId, opponentId, opponentEmail, opponentElo, 
    // playerScore, opponentScore, result, playerRounds, opponentRounds, createdAt
    
    final result = json['result'] as String? ?? '';
    final isWin = result.toLowerCase() == 'win';
    
    // Use provided userId or fallback to placeholder
    final playerId = currentUserId ?? 'current_user';
    final opponentId = json['opponentId'] as String? ?? '';
    
    final playerScore = json['playerScore'] as int? ?? 501;
    final opponentScore = json['opponentScore'] as int? ?? 501;
    
    // Backend sends playerEloChange for this match
    final eloChange = json['playerEloChange'] as int? ?? 0;
    
    // Get opponent username from opponentUsername or opponentEmail
    final opponentName = json['opponentUsername'] as String? ?? 
                         json['opponentEmail'] as String? ?? 
                         'Unknown Player';
    
    debugPrint('🎮 Parsing match: result=$result, opponentName=$opponentName, eloChange=$eloChange');
    
    return Match(
      id: json['matchId'] as String? ?? '',
      player1Id: playerId,
      player2Id: opponentId,
      player1Username: 'You',
      player2Username: opponentName,
      player1Score: playerScore,
      player2Score: opponentScore,
      winnerId: isWin ? playerId : opponentId,
      player1EloChange: eloChange,
      player2EloChange: -eloChange,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      status: 'completed',
      rounds: _parseRounds(json),
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

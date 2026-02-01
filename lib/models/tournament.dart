class Tournament {
  final String id;
  final String name;
  final String? description;
  final DateTime scheduledDate;
  final DateTime? registrationOpenDate;
  final DateTime? registrationCloseDate;
  final String status;
  final int maxParticipants;
  final int currentParticipants;
  final int winnerEloReward;
  final String? winnerId;
  final String? winnerUsername;
  final int currentRound;
  final int totalRounds;

  Tournament({
    required this.id,
    required this.name,
    this.description,
    required this.scheduledDate,
    this.registrationOpenDate,
    this.registrationCloseDate,
    required this.status,
    required this.maxParticipants,
    required this.currentParticipants,
    required this.winnerEloReward,
    this.winnerId,
    this.winnerUsername,
    this.currentRound = 0,
    this.totalRounds = 0,
  });

  factory Tournament.fromJson(Map<String, dynamic> json) {
    return Tournament(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      scheduledDate: DateTime.parse(json['scheduledDate'] as String),
      registrationOpenDate: json['registrationOpenDate'] != null
          ? DateTime.parse(json['registrationOpenDate'] as String)
          : null,
      registrationCloseDate: json['registrationCloseDate'] != null
          ? DateTime.parse(json['registrationCloseDate'] as String)
          : null,
      status: json['status'] as String,
      maxParticipants: json['maxParticipants'] as int? ?? 32,
      currentParticipants: json['currentParticipants'] as int? ?? 0,
      winnerEloReward: json['winnerEloReward'] as int? ?? 500,
      winnerId: json['winnerId'] as String?,
      winnerUsername: json['winnerUsername'] as String?,
      currentRound: json['currentRound'] as int? ?? 0,
      totalRounds: json['totalRounds'] as int? ?? 0,
    );
  }

  bool get isRegistrationOpen => status == 'registration_open';
  bool get isUpcoming => status == 'upcoming';
  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  String get statusDisplay {
    switch (status) {
      case 'upcoming':
        return 'Upcoming';
      case 'registration_open':
        return 'Registration Open';
      case 'registration_closed':
        return 'Registration Closed';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }
}

class TournamentMatch {
  final String id;
  final String tournamentId;
  final String? tournamentName;
  final int roundNumber;
  final String roundName;
  final int matchNumber;
  final String? player1Id;
  final String? player1Username;
  final String? player2Id;
  final String? player2Username;
  final String status;
  final int player1Score;
  final int player2Score;
  final String? winnerId;
  final int bestOf;
  final String? nextMatchId;
  final bool player1Ready;
  final bool player2Ready;
  final DateTime? inviteSentAt;
  final DateTime? startedAt;
  final DateTime? completedAt;

  TournamentMatch({
    required this.id,
    required this.tournamentId,
    this.tournamentName,
    required this.roundNumber,
    required this.roundName,
    required this.matchNumber,
    this.player1Id,
    this.player1Username,
    this.player2Id,
    this.player2Username,
    required this.status,
    required this.player1Score,
    required this.player2Score,
    this.winnerId,
    required this.bestOf,
    this.nextMatchId,
    this.player1Ready = false,
    this.player2Ready = false,
    this.inviteSentAt,
    this.startedAt,
    this.completedAt,
  });

  factory TournamentMatch.fromJson(Map<String, dynamic> json) {
    return TournamentMatch(
      id: json['id'] as String,
      tournamentId: json['tournamentId'] as String? ?? '',
      tournamentName: json['tournamentName'] as String?,
      roundNumber: json['roundNumber'] as int,
      roundName: json['roundName'] as String,
      matchNumber: json['matchNumber'] as int? ?? 0,
      player1Id: json['player1Id'] as String?,
      player1Username: json['player1Username'] as String?,
      player2Id: json['player2Id'] as String?,
      player2Username: json['player2Username'] as String?,
      status: json['status'] as String,
      player1Score: json['player1Score'] as int? ?? 0,
      player2Score: json['player2Score'] as int? ?? 0,
      winnerId: json['winnerId'] as String?,
      bestOf: json['bestOf'] as int? ?? 1,
      nextMatchId: json['nextMatchId'] as String?,
      player1Ready: json['player1Ready'] as bool? ?? false,
      player2Ready: json['player2Ready'] as bool? ?? false,
      inviteSentAt: json['inviteSentAt'] != null
          ? DateTime.parse(json['inviteSentAt'] as String)
          : null,
      startedAt: json['startedAt'] != null
          ? DateTime.parse(json['startedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
    );
  }

  String get roundNameDisplay {
    switch (roundName) {
      case 'final':
        return 'Final';
      case 'semi_final':
        return 'Semi-Final';
      case 'quarter_final':
        return 'Quarter-Final';
      case 'round_of_16':
        return 'Round of 16';
      case 'round_of_32':
        return 'Round of 32';
      case 'round_of_64':
        return 'Round of 64';
      default:
        return 'Round $roundNumber';
    }
  }

  bool get isWaitingForPlayers => status == 'waiting_for_players' ||
      status == 'player1_ready' ||
      status == 'player2_ready';

  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed' ||
      status == 'player1_forfeit' ||
      status == 'player2_forfeit' ||
      status == 'both_forfeit';
}

class TournamentRegistration {
  final String id;
  final String userId;
  final String? username;
  final int? elo;
  final String? rank;
  final String status;
  final int seed;
  final DateTime registeredAt;

  TournamentRegistration({
    required this.id,
    required this.userId,
    this.username,
    this.elo,
    this.rank,
    required this.status,
    required this.seed,
    required this.registeredAt,
  });

  factory TournamentRegistration.fromJson(Map<String, dynamic> json) {
    return TournamentRegistration(
      id: json['id'] as String,
      userId: json['userId'] as String,
      username: json['username'] as String?,
      elo: json['elo'] as int?,
      rank: json['rank'] as String?,
      status: json['status'] as String,
      seed: json['seed'] as int? ?? 0,
      registeredAt: DateTime.parse(json['registeredAt'] as String),
    );
  }

  String get rankDisplay {
    switch (rank) {
      case 'master':
        return 'Master';
      case 'diamond':
        return 'Diamond';
      case 'platinum':
        return 'Platinum';
      case 'gold':
        return 'Gold';
      case 'silver':
        return 'Silver';
      case 'bronze':
        return 'Bronze';
      default:
        return 'Unranked';
    }
  }
}

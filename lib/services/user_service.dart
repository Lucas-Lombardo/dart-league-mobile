import '../models/user.dart';
import '../models/match.dart';
import 'api_service.dart';

class UserStats {
  final int totalMatches;
  final double winRate;
  final double averageScore;
  final int highestScore;
  final int currentStreak;
  final int wins;
  final int losses;

  UserStats({
    required this.totalMatches,
    required this.winRate,
    required this.averageScore,
    required this.highestScore,
    required this.currentStreak,
    required this.wins,
    required this.losses,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      totalMatches: json['totalMatches'] as int? ?? 0,
      winRate: (json['winRate'] as num?)?.toDouble() ?? 0.0,
      averageScore: (json['averageScore'] as num?)?.toDouble() ?? 0.0,
      highestScore: json['highestScore'] as int? ?? 0,
      currentStreak: json['currentStreak'] as int? ?? 0,
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
    );
  }
}

class LeaderboardEntry {
  final User user;
  final int rank;
  final int wins;
  final int losses;

  LeaderboardEntry({
    required this.user,
    required this.rank,
    required this.wins,
    required this.losses,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json, [int? position]) {
    return LeaderboardEntry(
      user: User.fromJson(json['user'] ?? json),
      rank: position ?? (json['position'] as int? ?? 0),
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
    );
  }
}

class UserService {
  static Future<UserStats> getUserStats(String userId) async {
    try {
      final response = await ApiService.get('/users/$userId/stats');
      // Backend wraps stats in { userId, stats } object
      final statsData = response['stats'] ?? response;
      return UserStats.fromJson(statsData);
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<LeaderboardEntry>> getLeaderboard() async {
    try {
      final response = await ApiService.get('/users/leaderboard');
      final List<dynamic> data = response as List<dynamic>;
      
      
      // Backend sends flat user objects, we need to add position index
      return data.asMap().entries.map((entry) {
        final index = entry.key;
        final json = entry.value as Map<String, dynamic>;
        
        // Add username if missing (use email)
        if (json['username'] == null) {
          final email = json['email'] as String? ?? '';
          json['username'] = email.split('@').first;
        }
        
        return LeaderboardEntry.fromJson(json, index + 1);
      }).toList();
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<Match>> getUserMatches(String userId, {int limit = 50}) async {
    try {
      final response = await ApiService.get('/users/$userId/matches?limit=$limit');
      
      // Handle both array response and object with 'matches' key
      final List<dynamic> data;
      if (response is List) {
        data = response;
      } else if (response is Map && response['matches'] != null) {
        data = response['matches'] as List<dynamic>;
      } else {
        // If response format is unexpected, return empty list
        return [];
      }
      
      return data.map((json) => Match.fromJson(json, userId)).toList();
    } catch (e) {
      rethrow;
    }
  }


  static UserStats calculateStatsFromMatches(List<Match> matches, String userId) {
    if (matches.isEmpty) {
      return UserStats(
        totalMatches: 0,
        winRate: 0.0,
        averageScore: 0.0,
        highestScore: 0,
        currentStreak: 0,
        wins: 0,
        losses: 0,
      );
    }

    int wins = 0;
    int losses = 0;
    int totalScore = 0;
    int highestScore = 0;
    int currentStreak = 0;
    bool lastWasWin = false;

    for (var match in matches) {
      final isWin = match.isWinner(userId);
      final myScore = match.getMyScore(userId);

      if (isWin) {
        wins++;
        if (lastWasWin) {
          currentStreak++;
        } else {
          currentStreak = 1;
          lastWasWin = true;
        }
      } else {
        losses++;
        if (!lastWasWin) {
          currentStreak--;
        } else {
          currentStreak = -1;
          lastWasWin = false;
        }
      }

      // In darts 501, lower score at end is better (closer to 0)
      // But for "highest score in a round", we want the highest round score
      // For now, use the starting score minus final score as "points scored"
      final pointsScored = 501 - myScore;
      totalScore += pointsScored;
      
      if (pointsScored > highestScore) {
        highestScore = pointsScored;
      }
    }

    final totalMatches = matches.length;
    final winRate = totalMatches > 0 ? (wins / totalMatches) * 100 : 0.0;
    final averageScore = totalMatches > 0 ? totalScore / totalMatches : 0.0;

    return UserStats(
      totalMatches: totalMatches,
      winRate: winRate,
      averageScore: averageScore,
      highestScore: highestScore,
      currentStreak: currentStreak,
      wins: wins,
      losses: losses,
    );
  }
}

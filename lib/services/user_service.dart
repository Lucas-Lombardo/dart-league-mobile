import '../models/user.dart';
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

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      user: User.fromJson(json['user'] ?? json),
      rank: json['rank'] as int? ?? 0,
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
    );
  }
}

class UserService {
  static Future<UserStats> getUserStats(String userId) async {
    try {
      final response = await ApiService.get('/users/$userId/stats');
      return UserStats.fromJson(response);
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<LeaderboardEntry>> getLeaderboard() async {
    try {
      final response = await ApiService.get('/users/leaderboard');
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => LeaderboardEntry.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }
}

import '../models/user.dart';
import '../models/match.dart';
import 'api_service.dart';

class UserStats {
  final int totalMatches;
  final double winRate;
  final double averageScore;
  final int count180s;
  final int currentStreak;
  final int wins;
  final int losses;

  UserStats({
    required this.totalMatches,
    required this.winRate,
    required this.averageScore,
    required this.count180s,
    required this.currentStreak,
    required this.wins,
    required this.losses,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      totalMatches: json['totalMatches'] as int? ?? 0,
      winRate: (json['winRate'] as num?)?.toDouble() ?? 0.0,
      // Backend sends 'averageScorePerRound', map it to 'averageScore'
      averageScore: (json['averageScorePerRound'] as num?)?.toDouble() ?? 
                    (json['averageScore'] as num?)?.toDouble() ?? 0.0,
      count180s: json['count180s'] as int? ?? 0,
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

  static Future<void> updateLanguage(String languageCode) async {
    try {
      await ApiService.patch('/users/language', {
        'language': languageCode,
      });
    } catch (e) {
      rethrow;
    }
  }


}

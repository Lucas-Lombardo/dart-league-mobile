import '../models/user.dart';
import '../models/match.dart';
import '../models/inactivity_penalty.dart';
import 'api_service.dart';

class UserStats {
  final int totalMatches;
  final double winRate;
  final double averageScore;
  final int count180s;
  final int currentStreak;
  final int wins;
  final int losses;
  // Checkout & finishing stats. "LastMonth" = rolling 30 days. Default 0 so older
  // backends (without these fields) keep working.
  final int biggestCheckout;
  final int biggestCheckoutLastMonth;
  final double averageCheckout;
  final double averageCheckoutLastMonth;
  final double averageThreeDartLastMonth;
  final double finishingDoublePercentage;
  final double finishingDoublePercentageLastMonth;

  UserStats({
    required this.totalMatches,
    required this.winRate,
    required this.averageScore,
    required this.count180s,
    required this.currentStreak,
    required this.wins,
    required this.losses,
    this.biggestCheckout = 0,
    this.biggestCheckoutLastMonth = 0,
    this.averageCheckout = 0.0,
    this.averageCheckoutLastMonth = 0.0,
    this.averageThreeDartLastMonth = 0.0,
    this.finishingDoublePercentage = 0.0,
    this.finishingDoublePercentageLastMonth = 0.0,
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
      biggestCheckout: json['biggestCheckout'] as int? ?? 0,
      biggestCheckoutLastMonth: json['biggestCheckoutLastMonth'] as int? ?? 0,
      averageCheckout: (json['averageCheckout'] as num?)?.toDouble() ?? 0.0,
      averageCheckoutLastMonth: (json['averageCheckoutLastMonth'] as num?)?.toDouble() ?? 0.0,
      averageThreeDartLastMonth: (json['averageThreeDartLastMonth'] as num?)?.toDouble() ?? 0.0,
      finishingDoublePercentage: (json['finishingDoublePercentage'] as num?)?.toDouble() ?? 0.0,
      finishingDoublePercentageLastMonth: (json['finishingDoublePercentageLastMonth'] as num?)?.toDouble() ?? 0.0,
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
    final response = await ApiService.get('/users/$userId/stats');
    if (response is Map<String, dynamic>) {
      final statsData = response['stats'] ?? response;
      if (statsData is Map<String, dynamic>) {
        return UserStats.fromJson(statsData);
      }
    }
    return UserStats.fromJson(<String, dynamic>{});
  }

  static Future<List<LeaderboardEntry>> getLeaderboard() async {
    final response = await ApiService.get('/users/leaderboard');
    if (response is! List<dynamic>) return [];

    return response.asMap().entries.map((entry) {
      final index = entry.key;
      final json = entry.value;
      if (json is! Map<String, dynamic>) {
        return LeaderboardEntry.fromJson(<String, dynamic>{}, index + 1);
      }

      // Add username if missing (use email)
      if (json['username'] == null) {
        final email = json['email'] as String? ?? '';
        json['username'] = email.split('@').first;
      }

      return LeaderboardEntry.fromJson(json, index + 1);
    }).toList();
  }

  static Future<List<Match>> getUserMatches(String userId, {int limit = 50}) async {
    final response = await ApiService.get('/users/$userId/matches?limit=$limit');

    // Handle both array response and object with 'matches' key
    final List<dynamic> data;
    if (response is List) {
      data = response;
    } else if (response is Map && response['matches'] != null) {
      data = response['matches'] as List<dynamic>;
    } else {
      return [];
    }

    return data
        .whereType<Map<String, dynamic>>()
        .map((json) => Match.fromJson(json, userId))
        .toList();
  }

  /// Weekly inactivity penalties (newest first) for a user's history. Returns
  /// [] against older backends that don't have the endpoint yet.
  static Future<List<InactivityPenalty>> getInactivityPenalties(
    String userId, {
    int limit = 50,
  }) async {
    final response =
        await ApiService.get('/users/$userId/inactivity-penalties?limit=$limit');

    final List<dynamic> data;
    if (response is List) {
      data = response;
    } else if (response is Map && response['penalties'] != null) {
      data = response['penalties'] as List<dynamic>;
    } else {
      return [];
    }

    return data
        .whereType<Map<String, dynamic>>()
        .map((json) => InactivityPenalty.fromJson(json))
        .toList();
  }

  static Future<void> updateLanguage(String languageCode) async {
    await ApiService.patch('/users/language', {'language': languageCode});
  }
}

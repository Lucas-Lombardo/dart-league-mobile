import '../models/season.dart';
import 'api_service.dart';
import 'user_service.dart';

/// `/seasons/*` — all routes are new; an old backend answers 404 and every
/// method here degrades to "no season" so the screens stay as they were.
class SeasonsService {
  /// The active season + next + leader + my standing. Null when the backend
  /// has no seasons (older deploy) or the call fails.
  static Future<CurrentSeason?> getCurrent() async {
    try {
      final response = await ApiService.get('/seasons/current');
      if (response is Map<String, dynamic>) {
        return CurrentSeason.fromJson(response);
      }
    } catch (_) {}
    return null;
  }

  /// Every season, oldest first, with champion and my standing.
  static Future<List<Season>> list() async {
    try {
      final response = await ApiService.get('/seasons');
      if (response is List<dynamic>) {
        return response
            .whereType<Map<String, dynamic>>()
            .map(Season.fromJson)
            .toList()
          ..sort((a, b) => a.number.compareTo(b.number));
      }
    } catch (_) {}
    return [];
  }

  /// Frozen (closed) or live (active) ladder; same row shape as
  /// `/users/leaderboard`, positions come from the backend.
  static Future<List<LeaderboardEntry>> getStandings(
    int number, {
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await ApiService.get(
      '/seasons/$number/standings?limit=$limit&offset=$offset',
    );
    if (response is! List<dynamic>) return [];
    return response
        .whereType<Map<String, dynamic>>()
        .map((row) => LeaderboardEntry.fromJson(row))
        .toList();
  }

  /// My line in a season — null while unranked or for a scheduled season.
  static Future<SeasonStanding?> getMyStanding(int number) async {
    try {
      final response = await ApiService.get('/seasons/$number/standings/me');
      if (response is Map<String, dynamic>) {
        return SeasonStanding.fromJson(response);
      }
    } catch (_) {}
    return null;
  }

  /// The end-of-season screens to show once, or null.
  static Future<SeasonRecap?> getRecap() async {
    try {
      final response = await ApiService.get('/seasons/recap');
      if (response is Map<String, dynamic>) {
        return SeasonRecap.fromJson(response);
      }
    } catch (_) {}
    return null;
  }

  /// Acknowledges the recap of [number]. Returns false when the call failed
  /// (the screens will simply come back at the next launch).
  static Future<bool> markRecapSeen(int number) async {
    try {
      await ApiService.post('/seasons/recap/seen', {'number': number});
      return true;
    } catch (_) {
      return false;
    }
  }
}

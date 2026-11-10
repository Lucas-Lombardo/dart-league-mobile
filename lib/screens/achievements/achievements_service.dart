import 'package:flutter/foundation.dart';

import '../../services/api_service.dart';
import 'achievement_models.dart';

/// Achievements API — docs/progression/CONTRACT.md §14.3.
class AchievementsService {
  static Future<AchievementsSnapshot> list() async => AchievementsSnapshot.fromJson(await ApiService.get('/achievements'));

  static Future<AchievementsSummary> summary() async =>
      AchievementsSummary.fromJson(await ApiService.get('/achievements/summary'));

  static Future<AchievementDetail?> detail(String id) async =>
      AchievementDetail.fromJson(await ApiService.get('/achievements/${Uri.encodeComponent(id)}'));

  /// Tiers unlocked since [since] (the match start), retroactive ones excluded.
  static Future<List<AchievementUnlock>> unlockedSince(DateTime since) async {
    final iso = Uri.encodeQueryComponent(since.toUtc().toIso8601String());
    return AchievementUnlock.listFromJson(await ApiService.get('/achievements/unlocked?since=$iso'));
  }

  /// Tiers never announced yet (home screen).
  static Future<List<AchievementUnlock>> unseen() async =>
      AchievementUnlock.listFromJson(await ApiService.get('/achievements/unseen'));

  /// Never throws: a missed "seen" only means one more announcement.
  static Future<void> markSeen([List<String>? ids]) async {
    try {
      await ApiService.post('/achievements/seen', {'ids': ?ids});
    } catch (e) {
      debugPrint('AchievementsService: seen not sent: $e');
    }
  }
}

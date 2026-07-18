import 'api_service.dart';
import 'socket_service.dart';

/// Hour-of-day histogram of recent ranked matches, used by the queue screen
/// to show when opponents are most likely to be online.
class MatchmakingActivity {
  /// 24 buckets, index = hour of day in UTC.
  final List<int> utcHourCounts;
  final int totalMatches;

  MatchmakingActivity({required this.utcHourCounts, required this.totalMatches});

  factory MatchmakingActivity.fromJson(Map<String, dynamic> json) {
    final raw = json['utcHourCounts'];
    return MatchmakingActivity(
      utcHourCounts: List<int>.generate(
        24,
        (i) => raw is List && i < raw.length ? (raw[i] as num?)?.toInt() ?? 0 : 0,
      ),
      totalMatches: (json['totalMatches'] as num?)?.toInt() ?? 0,
    );
  }

  /// Counts re-indexed to the device's timezone (index = local hour of day).
  List<int> localHourCounts() {
    final offset = (DateTime.now().timeZoneOffset.inMinutes / 60).round();
    return List<int>.generate(
      24,
      (localHour) => utcHourCounts[((localHour - offset) % 24 + 24) % 24],
    );
  }
}

class MatchmakingService {
  static Future<Map<String, dynamic>> joinQueue(String userId) async {
    return await ApiService.post('/matchmaking/join', {
      'userId': userId,
      // BO3 opt-in: only declared when the connected server announced
      // supportsRankedBo3 (so an older backend never sees an unknown field —
      // its ValidationPipe runs with forbidNonWhitelisted and would 400).
      // The server pairs us into a BO3 series only when BOTH players sent it.
      if (SocketService.supportsRankedBo3) 'supportsRankedBo3': true,
    });
  }

  static Future<void> leaveQueue(String userId) async {
    await ApiService.delete('/matchmaking/leave?userId=$userId');
  }

  /// Returns null on any failure (offline, or a backend that predates the
  /// endpoint) — the activity chart simply stays hidden.
  static Future<MatchmakingActivity?> getActivity() async {
    try {
      final json = await ApiService.get('/matchmaking/activity');
      if (json is Map<String, dynamic>) {
        return MatchmakingActivity.fromJson(json);
      }
    } catch (_) {
      // Non-essential decoration; never surface an error for it.
    }
    return null;
  }
}

import 'api_service.dart';

/// One hourly bucket of the activity histogram (bucket start, UTC).
class ActivityHour {
  final DateTime hour;
  final int count;
  const ActivityHour({required this.hour, required this.count});
}

/// Snapshot returned by GET /presence/activity for the homescreen pulse card.
class ActivitySnapshot {
  final int onlineNow;
  final int activeCount;
  final int matches;
  final int matches24h;
  final int windowHours;
  final List<ActivityHour> hourly;
  final DateTime? peakHour;

  const ActivitySnapshot({
    required this.onlineNow,
    required this.activeCount,
    required this.matches,
    required this.matches24h,
    required this.windowHours,
    required this.hourly,
    required this.peakHour,
  });

  int get peakCount =>
      hourly.fold(0, (max, h) => h.count > max ? h.count : max);
}

class PresenceService {
  static Future<int?> ping() async {
    try {
      final result = await ApiService.post('/presence/ping', const {});
      if (result is Map && result['count'] is int) {
        return result['count'] as int;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> getOnlineCount() async {
    try {
      final result = await ApiService.get('/presence/online-count');
      if (result is Map && result['count'] is int) {
        return result['count'] as int;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Activity snapshot for the pulse card. Returns null on any error or
  /// malformed payload so the card can simply stay hidden.
  static Future<ActivitySnapshot?> fetchActivity({int hours = 12}) async {
    try {
      final result = await ApiService.get('/presence/activity?hours=$hours');
      if (result is! Map) return null;

      final hourly = <ActivityHour>[];
      final hourlyRaw = result['hourly'];
      if (hourlyRaw is List) {
        for (final entry in hourlyRaw) {
          if (entry is Map && entry['hour'] is String && entry['count'] is int) {
            final hour = DateTime.tryParse(entry['hour'] as String);
            if (hour != null) {
              hourly.add(ActivityHour(hour: hour, count: entry['count'] as int));
            }
          }
        }
      }
      if (hourly.isEmpty) return null;

      final peakRaw = result['peakHour'];
      final matches = result['matches'] is int ? result['matches'] as int : 0;
      return ActivitySnapshot(
        onlineNow: result['onlineNow'] is int ? result['onlineNow'] as int : 0,
        activeCount:
            result['activeCount'] is int ? result['activeCount'] as int : 0,
        matches: matches,
        matches24h:
            result['matches24h'] is int ? result['matches24h'] as int : matches,
        windowHours:
            result['windowHours'] is int ? result['windowHours'] as int : hours,
        hourly: hourly,
        peakHour: peakRaw is String ? DateTime.tryParse(peakRaw) : null,
      );
    } catch (_) {
      return null;
    }
  }
}

import '../models/training.dart';
import 'api_service.dart';

class TrainingService {
  static Future<TrainingSessionRecord> submit({
    required TrainingType type,
    required int score,
    required int dartsThrown,
    bool completed = true,
    Map<String, dynamic>? details,
  }) async {
    final response = await ApiService.post('/trainings', {
      'type': type.apiValue,
      'score': score,
      'dartsThrown': dartsThrown,
      'completed': completed,
      if (details != null) 'details': details,
    });
    if (response is Map<String, dynamic>) {
      return TrainingSessionRecord.fromJson(response);
    }
    throw Exception('Unexpected training submission response');
  }

  static Future<List<TrainingTypeStats>> getStats() async {
    final response = await ApiService.get('/trainings/stats');
    if (response is Map<String, dynamic> && response['stats'] is List) {
      return (response['stats'] as List)
          .whereType<Map<String, dynamic>>()
          .map(TrainingTypeStats.fromJson)
          .toList();
    }
    return TrainingType.values
        .map((t) => TrainingTypeStats.empty(t))
        .toList();
  }

  static Future<List<TrainingSessionRecord>> listSessions({
    TrainingType? type,
    int limit = 20,
  }) async {
    final typeParam = type != null ? '&type=${type.apiValue}' : '';
    final response = await ApiService.get(
      '/trainings?limit=$limit$typeParam',
    );
    if (response is Map<String, dynamic> && response['sessions'] is List) {
      return (response['sessions'] as List)
          .whereType<Map<String, dynamic>>()
          .map(TrainingSessionRecord.fromJson)
          .toList();
    }
    return [];
  }
}

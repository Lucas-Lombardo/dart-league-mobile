import '../models/bot_rank.dart';
import 'api_service.dart';

class BotTrainingService {
  /// Run one bot 3-dart visit for the given rank against [botRemaining].
  /// Returns the raw payload from POST /trainings/bot-turn — the placement
  /// provider parses it the same way as the placement endpoint's response.
  static Future<Map<String, dynamic>> botTurn({
    required BotRank rank,
    required int botRemaining,
  }) async {
    final response = await ApiService.post('/trainings/bot-turn', {
      'rank': rank.apiValue,
      'botRemaining': botRemaining,
    });
    if (response is Map<String, dynamic>) return response;
    return <String, dynamic>{};
  }
}

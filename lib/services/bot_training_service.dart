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

  /// Run one cricket bot visit. Stateless like the X01 endpoint: the client
  /// sends the whole board and applies the returned throws with its own
  /// CricketState rules.
  static Future<Map<String, dynamic>> cricketBotTurn({
    required BotRank rank,
    required String scoreMode,
    required Map<String, int> botMarks,
    required Map<String, int> playerMarks,
    required int botPoints,
    required int playerPoints,
  }) async {
    final response = await ApiService.post('/trainings/cricket-bot-turn', {
      'rank': rank.apiValue,
      'scoreMode': scoreMode,
      'botMarks': botMarks,
      'playerMarks': playerMarks,
      'botPoints': botPoints,
      'playerPoints': playerPoints,
    });
    if (response is Map<String, dynamic>) return response;
    return <String, dynamic>{};
  }
}

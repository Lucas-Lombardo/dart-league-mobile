import 'bot_rank.dart';
import 'cricket.dart';

/// Game mode of a bot-training match. X01 modes keep today's local engine;
/// cricket runs the [CricketState] rules.
enum BotGameMode { x501, x301, cricket }

/// Everything the player picks on the bot setup screen. Pure value object —
/// persisted locally (last used config) and echoed into the TrainingSession
/// details, never required by the backend.
class BotMatchConfig {
  final BotGameMode gameMode;

  /// Only meaningful when [gameMode] is cricket.
  final CricketScoreMode cricketScoreMode;

  /// Match length in legs (3 / 5 / 7 / 11). First to [legsToWin] wins.
  final int bestOf;

  final BotRank rank;

  const BotMatchConfig({
    this.gameMode = BotGameMode.x501,
    this.cricketScoreMode = CricketScoreMode.score,
    this.bestOf = 3,
    this.rank = BotRank.gold,
  });

  int get legsToWin => (bestOf ~/ 2) + 1;
  bool get isCricket => gameMode == BotGameMode.cricket;

  /// X01 starting score; 501 for cricket so legacy code paths stay harmless.
  int get startingScore => gameMode == BotGameMode.x301 ? 301 : 501;

  /// Stats bucket written to TrainingSession details.mode. Historic sessions
  /// have no mode — the backend derives their bucket from startingScore.
  String get modeWire {
    switch (gameMode) {
      case BotGameMode.x501:
        return '501';
      case BotGameMode.x301:
        return '301';
      case BotGameMode.cricket:
        return cricketScoreMode == CricketScoreMode.noScore
            ? 'cricket_noscore'
            : 'cricket_score';
    }
  }

  BotMatchConfig copyWith({
    BotGameMode? gameMode,
    CricketScoreMode? cricketScoreMode,
    int? bestOf,
    BotRank? rank,
  }) {
    return BotMatchConfig(
      gameMode: gameMode ?? this.gameMode,
      cricketScoreMode: cricketScoreMode ?? this.cricketScoreMode,
      bestOf: bestOf ?? this.bestOf,
      rank: rank ?? this.rank,
    );
  }

  Map<String, dynamic> toJson() => {
        'gameMode': gameMode.name,
        'cricketScoreMode': cricketScoreMode.name,
        'bestOf': bestOf,
        'rank': rank.apiValue,
      };

  /// Tolerant parse — any unknown/missing value falls back to the default so
  /// a config saved by a future app version can't crash this one.
  factory BotMatchConfig.fromJson(Map<String, dynamic> json) {
    BotRank rank = BotRank.gold;
    final rawRank = json['rank'];
    if (rawRank is String) {
      for (final r in BotRank.values) {
        if (r.apiValue == rawRank) rank = r;
      }
    }
    final bestOf = json['bestOf'];
    return BotMatchConfig(
      gameMode: BotGameMode.values.asNameMap()[json['gameMode']] ??
          BotGameMode.x501,
      cricketScoreMode:
          CricketScoreMode.values.asNameMap()[json['cricketScoreMode']] ??
              CricketScoreMode.score,
      bestOf: bestOf is int && const [3, 5, 7, 11].contains(bestOf)
          ? bestOf
          : 3,
      rank: rank,
    );
  }
}

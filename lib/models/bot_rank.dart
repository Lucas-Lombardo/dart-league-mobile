enum BotRank {
  bronze,
  silver,
  gold,
  platinum,
  diamond,
  pro,
  master,
}

extension BotRankX on BotRank {
  /// Backend wire value (matches BotRank enum in
  /// backend/src/trainings/dto/bot-turn.dto.ts).
  String get apiValue {
    switch (this) {
      case BotRank.bronze:
        return 'bronze';
      case BotRank.silver:
        return 'silver';
      case BotRank.gold:
        return 'gold';
      case BotRank.platinum:
        return 'platinum';
      case BotRank.diamond:
        return 'diamond';
      case BotRank.pro:
        return 'pro';
      case BotRank.master:
        return 'master';
    }
  }

  /// Target 3-dart average for this rank. Only used by the mobile UI for
  /// display; the actual throw simulation runs on the backend with the same
  /// numbers (see BOT_RANK_CONFIGS in bot-turn.dto.ts).
  int get targetAverage {
    switch (this) {
      case BotRank.bronze:
        return 30;
      case BotRank.silver:
        return 40;
      case BotRank.gold:
        return 50;
      case BotRank.platinum:
        return 60;
      case BotRank.diamond:
        return 75;
      case BotRank.pro:
        return 90;
      case BotRank.master:
        return 110;
    }
  }

  static BotRank fromApi(String value) {
    for (final r in BotRank.values) {
      if (r.apiValue == value) return r;
    }
    throw ArgumentError('Unknown bot rank: $value');
  }
}

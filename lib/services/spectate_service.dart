import 'package:flutter/foundation.dart';

import 'api_service.dart';

/// Public identity of one player in a spectatable match.
class SpectatorPlayer {
  final String id;
  final String username;
  final int elo;
  final String rank;

  const SpectatorPlayer({
    required this.id,
    required this.username,
    required this.elo,
    this.rank = 'unranked',
  });

  static SpectatorPlayer? fromJson(dynamic json) {
    if (json is! Map) return null;
    final id = json['id'] as String?;
    final username = json['username'] as String?;
    if (id == null || username == null) return null;
    return SpectatorPlayer(
      id: id,
      username: username,
      elo: (json['elo'] as num?)?.toInt() ?? 0,
      rank: json['rank'] as String? ?? 'unranked',
    );
  }
}

/// One live ranked BO3 series, spectatable on its current leg [matchId].
class LiveRankedSeries {
  final String seriesId;
  final String matchId;
  final int legNumber;
  final int bestOf;
  final int player1LegsWon;
  final int player2LegsWon;
  final SpectatorPlayer player1;
  final SpectatorPlayer player2;
  final int spectatorCount;

  const LiveRankedSeries({
    required this.seriesId,
    required this.matchId,
    required this.legNumber,
    required this.bestOf,
    required this.player1LegsWon,
    required this.player2LegsWon,
    required this.player1,
    required this.player2,
    required this.spectatorCount,
  });

  static LiveRankedSeries? fromJson(dynamic json) {
    if (json is! Map) return null;
    final seriesId = json['seriesId'] as String?;
    final matchId = json['matchId'] as String?;
    final player1 = SpectatorPlayer.fromJson(json['player1']);
    final player2 = SpectatorPlayer.fromJson(json['player2']);
    if (seriesId == null || matchId == null || player1 == null || player2 == null) {
      return null;
    }
    return LiveRankedSeries(
      seriesId: seriesId,
      matchId: matchId,
      legNumber: (json['legNumber'] as num?)?.toInt() ?? 1,
      bestOf: (json['bestOf'] as num?)?.toInt() ?? 3,
      player1LegsWon: (json['player1LegsWon'] as num?)?.toInt() ?? 0,
      player2LegsWon: (json['player2LegsWon'] as num?)?.toInt() ?? 0,
      player1: player1,
      player2: player2,
      spectatorCount: (json['spectatorCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One live tournament match, spectatable on its current leg [matchId].
class LiveTournamentMatch {
  final String tournamentMatchId;
  final String matchId;
  final String roundName;
  final int roundNumber;
  final int matchNumber;
  final int bestOf;
  final int legNumber;
  final int player1LegsWon;
  final int player2LegsWon;
  final SpectatorPlayer player1;
  final SpectatorPlayer player2;
  final int spectatorCount;

  const LiveTournamentMatch({
    required this.tournamentMatchId,
    required this.matchId,
    required this.roundName,
    required this.roundNumber,
    required this.matchNumber,
    required this.bestOf,
    required this.legNumber,
    required this.player1LegsWon,
    required this.player2LegsWon,
    required this.player1,
    required this.player2,
    required this.spectatorCount,
  });

  static LiveTournamentMatch? fromJson(dynamic json) {
    if (json is! Map) return null;
    final tournamentMatchId = json['tournamentMatchId'] as String?;
    final matchId = json['matchId'] as String?;
    final player1 = SpectatorPlayer.fromJson(json['player1']);
    final player2 = SpectatorPlayer.fromJson(json['player2']);
    if (tournamentMatchId == null ||
        matchId == null ||
        player1 == null ||
        player2 == null) {
      return null;
    }
    return LiveTournamentMatch(
      tournamentMatchId: tournamentMatchId,
      matchId: matchId,
      roundName: json['roundName'] as String? ?? '',
      roundNumber: (json['roundNumber'] as num?)?.toInt() ?? 0,
      matchNumber: (json['matchNumber'] as num?)?.toInt() ?? 0,
      bestOf: (json['bestOf'] as num?)?.toInt() ?? 3,
      legNumber: (json['legNumber'] as num?)?.toInt() ?? 1,
      player1LegsWon: (json['player1LegsWon'] as num?)?.toInt() ?? 0,
      player2LegsWon: (json['player2LegsWon'] as num?)?.toInt() ?? 0,
      player1: player1,
      player2: player2,
      spectatorCount: (json['spectatorCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A tournament that currently has at least one live match.
class LiveTournamentGroup {
  final String tournamentId;
  final String name;
  final List<LiveTournamentMatch> matches;

  const LiveTournamentGroup({
    required this.tournamentId,
    required this.name,
    required this.matches,
  });

  static LiveTournamentGroup? fromJson(dynamic json) {
    if (json is! Map) return null;
    final tournamentId = json['tournamentId'] as String?;
    if (tournamentId == null) return null;
    final matches = <LiveTournamentMatch>[];
    final rawMatches = json['matches'];
    if (rawMatches is List) {
      for (final raw in rawMatches) {
        final match = LiveTournamentMatch.fromJson(raw);
        if (match != null) matches.add(match);
      }
    }
    return LiveTournamentGroup(
      tournamentId: tournamentId,
      name: json['name'] as String? ?? '',
      matches: matches,
    );
  }
}

/// Everything currently spectatable, as served by GET /spectate/live.
class SpectateLive {
  final int liveCount;
  final List<LiveRankedSeries> ranked;
  final List<LiveTournamentGroup> tournaments;

  const SpectateLive({
    required this.liveCount,
    required this.ranked,
    required this.tournaments,
  });
}

/// REST access to the spectate discovery endpoint. Follows the
/// PresenceService pattern: static, typed extraction, null on any failure so
/// the UI simply hides the surface.
class SpectateService {
  static Future<SpectateLive?> fetchLive() async {
    try {
      final result = await ApiService.get('/spectate/live');
      if (result is! Map) return null;

      final ranked = <LiveRankedSeries>[];
      final rawRanked = result['ranked'];
      if (rawRanked is List) {
        for (final raw in rawRanked) {
          final series = LiveRankedSeries.fromJson(raw);
          if (series != null) ranked.add(series);
        }
      }

      final tournaments = <LiveTournamentGroup>[];
      final rawTournaments = result['tournaments'];
      if (rawTournaments is List) {
        for (final raw in rawTournaments) {
          final group = LiveTournamentGroup.fromJson(raw);
          if (group != null && group.matches.isNotEmpty) tournaments.add(group);
        }
      }

      final liveCount = (result['liveCount'] as num?)?.toInt() ??
          (ranked.length +
              tournaments.fold<int>(0, (n, t) => n + t.matches.length));
      return SpectateLive(
        liveCount: liveCount,
        ranked: ranked,
        tournaments: tournaments,
      );
    } catch (e) {
      debugPrint('SpectateService: fetchLive failed: $e');
      return null;
    }
  }
}

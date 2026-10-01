import 'package:flutter/foundation.dart' show debugPrint;
import '../models/tournament.dart';
import 'api_service.dart';

class TournamentService {
  static Future<List<Tournament>> getAllTournaments() async {
    final response = await ApiService.get('/tournaments');
    final list = response?['tournaments'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((t) => Tournament.fromJson(t))
        .toList();
  }

  static Future<List<Tournament>> getUpcomingTournaments() async {
    final response = await ApiService.get('/tournaments/upcoming');
    final list = response?['tournaments'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((t) => Tournament.fromJson(t))
        .toList();
  }

  static Future<Map<String, List<Tournament>>> getMyTournaments() async {
    final response = await ApiService.get('/tournaments/my');
    final registeredList = response?['registered'] as List<dynamic>? ?? [];
    final activeList = response?['active'] as List<dynamic>? ?? [];
    // Community tournaments the user organises (absent on older backends).
    final organizedList = response?['organized'] as List<dynamic>? ?? [];
    final registered = registeredList
        .whereType<Map<String, dynamic>>()
        .map((t) => Tournament.fromJson(t))
        .toList();
    final active = activeList
        .whereType<Map<String, dynamic>>()
        .map((t) => Tournament.fromJson(t))
        .toList();
    final organized = organizedList
        .whereType<Map<String, dynamic>>()
        .map((t) => Tournament.fromJson(t))
        .toList();
    return {'registered': registered, 'active': active, 'organized': organized};
  }

  static Future<Tournament> getTournament(String id) async {
    final response = await ApiService.get('/tournaments/$id');
    final data = response?['tournament'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid tournament data');
    }
    return Tournament.fromJson(data);
  }

  static Future<List<TournamentMatch>> getBracket(String tournamentId) async {
    final response = await ApiService.get('/tournaments/$tournamentId/bracket');
    final list = response?['matches'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => TournamentMatch.fromJson(m))
        .toList();
  }

  static Future<List<TournamentRegistration>> getRegistrations(String tournamentId) async {
    final response = await ApiService.get('/tournaments/$tournamentId/registrations');
    final list = response?['registrations'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((r) => TournamentRegistration.fromJson(r))
        .toList();
  }

  static Future<Map<String, dynamic>> createPaymentIntent(String tournamentId) async {
    final response = await ApiService.post('/tournaments/$tournamentId/create-payment-intent', {});
    return response as Map<String, dynamic>;
  }

  static Future<void> registerForTournament(String tournamentId, {String? paymentIntentId}) async {
    final body = <String, dynamic>{};
    if (paymentIntentId != null) {
      body['paymentIntentId'] = paymentIntentId;
    }
    await ApiService.post('/tournaments/$tournamentId/register', body);
  }

  static Future<void> unregisterFromTournament(String tournamentId) async {
    await ApiService.delete('/tournaments/$tournamentId/register');
  }

  /// Tournaments left this month for a player without premium, for the
  /// month of [date] (a tournament's start).
  static Future<MonthlyTournamentQuota> getMonthlyQuota(DateTime date) async {
    final at = Uri.encodeQueryComponent(date.toUtc().toIso8601String());
    final response = await ApiService.get('/tournaments/monthly-quota?date=$at');
    if (response is! Map<String, dynamic>) {
      throw Exception('Invalid quota data');
    }
    return MonthlyTournamentQuota.fromJson(response);
  }

  // ── Community tournaments (organised by a player) ──────────────────────

  /// Creates a tournament organised by the signed-in player; returns its id.
  static Future<String> createCommunityTournament({
    required String name,
    required DateTime scheduledDate,
    required int maxParticipants,
    required int bestOf,
    required bool organizerPlays,
  }) async {
    final response = await ApiService.post('/tournaments/community', {
      'name': name,
      'scheduledDate': scheduledDate.toUtc().toIso8601String(),
      'maxParticipants': maxParticipants,
      'bestOf': bestOf,
      'organizerPlays': organizerPlays,
    });
    final id = response?['tournament']?['id'];
    if (id is! String) throw Exception('Invalid tournament data');
    return id;
  }

  static Future<void> updateCommunityTournament(
    String tournamentId, {
    String? name,
    DateTime? scheduledDate,
    int? maxParticipants,
    int? bestOf,
  }) async {
    await ApiService.patch('/tournaments/$tournamentId/community', {
      'name': ?name,
      'scheduledDate': ?scheduledDate?.toUtc().toIso8601String(),
      'maxParticipants': ?maxParticipants,
      'bestOf': ?bestOf,
    });
  }

  static Future<void> cancelCommunityTournament(String tournamentId) async {
    await ApiService.delete('/tournaments/$tournamentId/community');
  }

  static Future<void> startCommunityTournament(String tournamentId) async {
    await ApiService.post('/tournaments/$tournamentId/start', {});
  }

  static Future<void> removeParticipant(String tournamentId, String userId) async {
    await ApiService.delete('/tournaments/$tournamentId/registrations/$userId');
  }

  /// Pushes an invitation to some friends; returns how many got one.
  static Future<int> inviteFriends(String tournamentId, List<String> userIds) async {
    final response = await ApiService.post(
      '/tournaments/$tournamentId/invite',
      {'userIds': userIds},
    );
    return response?['invited'] as int? ?? 0;
  }

  static Future<Map<String, dynamic>> getMyRegistration(String tournamentId) async {
    final response = await ApiService.get('/tournaments/$tournamentId/my-registration');
    if (response is Map<String, dynamic>) return response;
    return <String, dynamic>{};
  }

  static Future<List<TournamentMatch>> getPendingMatches() async {
    final response = await ApiService.get('/tournaments/pending-matches');
    final list = response?['matches'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((m) => TournamentMatch.fromJson(m))
        .toList();
  }

  static Future<TournamentMatch?> getActiveMatch() async {
    final response = await ApiService.get('/tournaments/active-match');
    final match = response?['match'];
    if (match is! Map<String, dynamic>) return null;
    return TournamentMatch.fromJson(match);
  }

  static Future<Map<String, dynamic>> getActiveTournamentStatus() async {
    try {
      final response = await ApiService.get('/tournaments/active-status');
      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error fetching active tournament status: $e');
      return {'inActiveTournament': false};
    }
  }

  static Future<void> setMatchReady(String matchId) async {
    await ApiService.post('/tournaments/matches/$matchId/ready', {});
  }

  /// Poll fallback for the ready screen: ready flags + (once both players
  /// readied and the leg exists) the same start payload as the
  /// tournamentMatchStart socket event — so a missed emit can't strand the
  /// lobby on "waiting for opponent".
  static Future<Map<String, dynamic>> getMatchReadyState(String matchId) async {
    final response =
        await ApiService.get('/tournaments/matches/$matchId/ready-state');
    if (response is Map<String, dynamic>) return response;
    return <String, dynamic>{};
  }

  /// Withdraw a ready state (backing out of the ready screen before the match
  /// starts). Throws if the match already started.
  static Future<void> setMatchUnready(String matchId) async {
    await ApiService.post('/tournaments/matches/$matchId/unready', {});
  }

  static Future<List<TournamentHistory>> getTournamentHistory() async {
    // scope=all: every completed tournament, with `participated` flagging ours.
    final response = await ApiService.get('/tournaments/history?scope=all');
    final list = response?['tournaments'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((t) => TournamentHistory.fromJson(t))
        .toList();
  }
}

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
    final registered = registeredList
        .whereType<Map<String, dynamic>>()
        .map((t) => Tournament.fromJson(t))
        .toList();
    final active = activeList
        .whereType<Map<String, dynamic>>()
        .map((t) => Tournament.fromJson(t))
        .toList();
    return {'registered': registered, 'active': active};
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

  static Future<List<TournamentHistory>> getTournamentHistory() async {
    final response = await ApiService.get('/tournaments/history');
    final list = response?['tournaments'] as List<dynamic>? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((t) => TournamentHistory.fromJson(t))
        .toList();
  }
}

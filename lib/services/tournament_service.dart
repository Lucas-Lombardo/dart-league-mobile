import 'package:flutter/foundation.dart' show debugPrint;
import '../models/tournament.dart';
import 'api_service.dart';

class TournamentService {
  static Future<List<Tournament>> getAllTournaments() async {
    final response = await ApiService.get('/tournaments');
    return (response['tournaments'] as List)
        .map((t) => Tournament.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Tournament>> getUpcomingTournaments() async {
    final response = await ApiService.get('/tournaments/upcoming');
    return (response['tournaments'] as List)
        .map((t) => Tournament.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  static Future<Map<String, List<Tournament>>> getMyTournaments() async {
    final response = await ApiService.get('/tournaments/my');
    final registered = (response['registered'] as List)
        .map((t) => Tournament.fromJson(t as Map<String, dynamic>))
        .toList();
    final active = (response['active'] as List)
        .map((t) => Tournament.fromJson(t as Map<String, dynamic>))
        .toList();
    return {'registered': registered, 'active': active};
  }

  static Future<Tournament> getTournament(String id) async {
    final response = await ApiService.get('/tournaments/$id');
    return Tournament.fromJson(response['tournament'] as Map<String, dynamic>);
  }

  static Future<List<TournamentMatch>> getBracket(String tournamentId) async {
    final response = await ApiService.get('/tournaments/$tournamentId/bracket');
    return (response['matches'] as List)
        .map((m) => TournamentMatch.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  static Future<List<TournamentRegistration>> getRegistrations(String tournamentId) async {
    final response = await ApiService.get('/tournaments/$tournamentId/registrations');
    return (response['registrations'] as List)
        .map((r) => TournamentRegistration.fromJson(r as Map<String, dynamic>))
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
    return response as Map<String, dynamic>;
  }

  static Future<List<TournamentMatch>> getPendingMatches() async {
    final response = await ApiService.get('/tournaments/pending-matches');
    return (response['matches'] as List)
        .map((m) => TournamentMatch.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  static Future<TournamentMatch?> getActiveMatch() async {
    final response = await ApiService.get('/tournaments/active-match');
    if (response['match'] == null) return null;
    return TournamentMatch.fromJson(response['match'] as Map<String, dynamic>);
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
    return (response['tournaments'] as List)
        .map((t) => TournamentHistory.fromJson(t as Map<String, dynamic>))
        .toList();
  }
}

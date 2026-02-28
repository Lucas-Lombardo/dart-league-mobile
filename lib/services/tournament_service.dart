import 'package:flutter/foundation.dart' show debugPrint;
import '../models/tournament.dart';
import 'api_service.dart';

class TournamentService {
  static Future<List<Tournament>> getAllTournaments() async {
    try {
      final response = await ApiService.get('/tournaments');
      final tournaments = (response['tournaments'] as List)
          .map((t) => Tournament.fromJson(t as Map<String, dynamic>))
          .toList();
      return tournaments;
    } catch (e) {
      debugPrint('Error fetching tournaments: $e');
      rethrow;
    }
  }

  static Future<List<Tournament>> getUpcomingTournaments() async {
    try {
      final response = await ApiService.get('/tournaments/upcoming');
      final tournaments = (response['tournaments'] as List)
          .map((t) => Tournament.fromJson(t as Map<String, dynamic>))
          .toList();
      return tournaments;
    } catch (e) {
      debugPrint('Error fetching upcoming tournaments: $e');
      rethrow;
    }
  }

  static Future<Map<String, List<Tournament>>> getMyTournaments() async {
    try {
      final response = await ApiService.get('/tournaments/my');
      final registered = (response['registered'] as List)
          .map((t) => Tournament.fromJson(t as Map<String, dynamic>))
          .toList();
      final active = (response['active'] as List)
          .map((t) => Tournament.fromJson(t as Map<String, dynamic>))
          .toList();
      return {'registered': registered, 'active': active};
    } catch (e) {
      debugPrint('Error fetching my tournaments: $e');
      rethrow;
    }
  }

  static Future<Tournament> getTournament(String id) async {
    try {
      final response = await ApiService.get('/tournaments/$id');
      return Tournament.fromJson(response['tournament'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Error fetching tournament: $e');
      rethrow;
    }
  }

  static Future<List<TournamentMatch>> getBracket(String tournamentId) async {
    try {
      final response = await ApiService.get('/tournaments/$tournamentId/bracket');
      return (response['matches'] as List)
          .map((m) => TournamentMatch.fromJson(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching bracket: $e');
      rethrow;
    }
  }

  static Future<List<TournamentRegistration>> getRegistrations(String tournamentId) async {
    try {
      final response = await ApiService.get('/tournaments/$tournamentId/registrations');
      return (response['registrations'] as List)
          .map((r) => TournamentRegistration.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching registrations: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> createPaymentIntent(String tournamentId) async {
    try {
      final response = await ApiService.post('/tournaments/$tournamentId/create-payment-intent', {});
      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error creating payment intent: $e');
      rethrow;
    }
  }

  static Future<void> registerForTournament(String tournamentId, {String? paymentIntentId}) async {
    try {
      final body = <String, dynamic>{};
      if (paymentIntentId != null) {
        body['paymentIntentId'] = paymentIntentId;
      }
      await ApiService.post('/tournaments/$tournamentId/register', body);
    } catch (e) {
      debugPrint('Error registering for tournament: $e');
      rethrow;
    }
  }

  static Future<void> unregisterFromTournament(String tournamentId) async {
    try {
      await ApiService.delete('/tournaments/$tournamentId/register');
    } catch (e) {
      debugPrint('Error unregistering from tournament: $e');
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getMyRegistration(String tournamentId) async {
    try {
      final response = await ApiService.get('/tournaments/$tournamentId/my-registration');
      return response as Map<String, dynamic>;
    } catch (e) {
      debugPrint('Error fetching my registration: $e');
      rethrow;
    }
  }

  static Future<List<TournamentMatch>> getPendingMatches() async {
    try {
      final response = await ApiService.get('/tournaments/pending-matches');
      return (response['matches'] as List)
          .map((m) => TournamentMatch.fromJson(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching pending matches: $e');
      rethrow;
    }
  }

  static Future<TournamentMatch?> getActiveMatch() async {
    try {
      final response = await ApiService.get('/tournaments/active-match');
      if (response['match'] == null) return null;
      return TournamentMatch.fromJson(response['match'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Error fetching active match: $e');
      rethrow;
    }
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
    try {
      await ApiService.post('/tournaments/matches/$matchId/ready', {});
    } catch (e) {
      debugPrint('Error setting match ready: $e');
      rethrow;
    }
  }

  static Future<List<TournamentHistory>> getTournamentHistory() async {
    try {
      final response = await ApiService.get('/tournaments/history');
      return (response['tournaments'] as List)
          .map((t) => TournamentHistory.fromJson(t as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching tournament history: $e');
      rethrow;
    }
  }
}

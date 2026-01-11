import 'dart:convert';
import 'package:http/http.dart' as http;
import '../utils/api_config.dart';
import '../utils/storage_service.dart';

class MatchService {
  static Future<Map<String, dynamic>> acceptMatchResult(
    String matchId,
    String playerId,
  ) async {
    final token = await StorageService.getToken();
    if (token == null) {
      throw Exception('No authentication token found');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/matches/$matchId/accept'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'playerId': playerId,
      }),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      final error = json.decode(response.body);
      throw Exception(error['message'] ?? 'Failed to accept match result');
    }
  }

  static Future<Map<String, dynamic>> disputeMatchResult(
    String matchId,
    String playerId,
    String reason,
  ) async {
    final token = await StorageService.getToken();
    if (token == null) {
      throw Exception('No authentication token found');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/matches/$matchId/dispute'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({
        'playerId': playerId,
        'reason': reason,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return json.decode(response.body) as Map<String, dynamic>;
    } else {
      final error = json.decode(response.body);
      throw Exception(error['message'] ?? 'Failed to dispute match result');
    }
  }
}

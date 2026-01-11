import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../utils/api_config.dart';
import '../utils/storage_service.dart';

class ApiService {
  static const Duration _timeout = Duration(seconds: 30);

  static Future<Map<String, String>> _getHeaders({bool includeAuth = true}) async {
    final headers = {
      'Content-Type': 'application/json',
    };

    if (includeAuth) {
      final token = await StorageService.getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    return headers;
  }

  static Future<dynamic> get(String endpoint, {bool includeAuth = true}) async {
    try {
      final url = Uri.parse('$baseUrl$endpoint');
      final headers = await _getHeaders(includeAuth: includeAuth);
      
      final response = await http.get(url, headers: headers).timeout(_timeout);
      
      return _handleResponse(response);
    } on TimeoutException {
      throw Exception('Connection timeout - Please check your internet');
    } catch (e) {
      if (e.toString().contains('SocketException') || 
          e.toString().contains('HandshakeException')) {
        throw Exception('Unable to connect - Check your internet connection');
      }
      rethrow;
    }
  }

  static Future<dynamic> post(
    String endpoint,
    Map<String, dynamic> body, {
    bool includeAuth = true,
  }) async {
    try {
      final url = Uri.parse('$baseUrl$endpoint');
      final headers = await _getHeaders(includeAuth: includeAuth);
      
      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      ).timeout(_timeout);
      
      return _handleResponse(response);
    } on TimeoutException {
      throw Exception('Connection timeout - Please check your internet');
    } catch (e) {
      if (e.toString().contains('SocketException') || 
          e.toString().contains('HandshakeException')) {
        throw Exception('Unable to connect - Check your internet connection');
      }
      rethrow;
    }
  }

  static Future<dynamic> put(
    String endpoint,
    Map<String, dynamic> body, {
    bool includeAuth = true,
  }) async {
    try {
      final headers = await _getHeaders(includeAuth: includeAuth);
      final response = await http.put(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
        body: jsonEncode(body),
      ).timeout(_timeout);

      return _handleResponse(response);
    } on TimeoutException {
      throw Exception('Connection timeout - Please check your internet');
    } catch (e) {
      if (e.toString().contains('SocketException') || 
          e.toString().contains('HandshakeException')) {
        throw Exception('Unable to connect - Check your internet connection');
      }
      rethrow;
    }
  }

  static Future<dynamic> delete(String endpoint, {bool includeAuth = true}) async {
    try {
      final headers = await _getHeaders(includeAuth: includeAuth);
      final response = await http.delete(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
      );

      return _handleResponse(response);
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }

  static dynamic _handleResponse(http.Response response) {
    final statusCode = response.statusCode;
    final body = response.body.isNotEmpty ? jsonDecode(response.body) : null;

    if (statusCode >= 200 && statusCode < 300) {
      return body;
    }

    switch (statusCode) {
      case 401:
        throw Exception('Unauthorized: ${body?['message'] ?? 'Invalid credentials'}');
      case 403:
        throw Exception('Forbidden: ${body?['message'] ?? 'Access denied'}');
      case 404:
        throw Exception('Not found: ${body?['message'] ?? 'Resource not found'}');
      case 500:
        throw Exception('Server error: ${body?['message'] ?? 'Internal server error'}');
      default:
        throw Exception('Error $statusCode: ${body?['message'] ?? 'Unknown error'}');
    }
  }
}

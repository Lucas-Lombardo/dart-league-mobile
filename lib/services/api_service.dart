import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../utils/api_config.dart';
import '../utils/storage_service.dart';

class ApiService {
  static const Duration _timeout = Duration(seconds: 30);

  /// Called when token refresh fails — the app should navigate to login.
  static void Function()? onAuthFailure;

  static Completer<bool>? _refreshCompleter;

  static Future<Map<String, String>> _getHeaders({bool includeAuth = true}) async {
    final headers = {
      'Content-Type': 'application/json',
    };

    if (includeAuth) {
      final token = await StorageService.getToken();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      } else {
        debugPrint('⚠️ No token found in storage');
      }
    }

    return headers;
  }

  /// Attempts to refresh the access token using the stored refresh token.
  /// Returns true if refresh succeeded, false otherwise.
  /// Deduplicates concurrent refresh calls.
  static Future<bool> refreshAccessToken() async {
    // If a refresh is already in progress, wait for it
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();

    try {
      final refreshToken = await StorageService.getRefreshToken();
      if (refreshToken == null) {
        _refreshCompleter!.complete(false);
        return false;
      }

      final url = Uri.parse('$baseUrl/auth/refresh');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      ).timeout(_timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body);
        await StorageService.saveToken(body['access_token']);
        await StorageService.saveRefreshToken(body['refresh_token']);
        debugPrint('🔄 Token refreshed successfully');
        _refreshCompleter!.complete(true);
        return true;
      } else {
        debugPrint('❌ Token refresh failed: ${response.statusCode}');
        _refreshCompleter!.complete(false);
        return false;
      }
    } catch (e) {
      debugPrint('❌ Token refresh error: $e');
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  static void _handleAuthFailure() {
    onAuthFailure?.call();
  }

  static Future<dynamic> get(String endpoint, {bool includeAuth = true}) async {
    try {
      final url = Uri.parse('$baseUrl$endpoint');
      final headers = await _getHeaders(includeAuth: includeAuth);

      final response = await http.get(url, headers: headers).timeout(_timeout);

      if (response.statusCode == 401 && includeAuth) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          final retryHeaders = await _getHeaders(includeAuth: true);
          final retryResponse = await http.get(url, headers: retryHeaders).timeout(_timeout);
          return _handleResponse(retryResponse);
        } else {
          _handleAuthFailure();
          return _handleResponse(response);
        }
      }

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

      debugPrint('📤 POST $endpoint with body: $body');

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      ).timeout(_timeout);

      debugPrint('📥 Response status: ${response.statusCode}');
      debugPrint('📥 Response body: ${response.body}');

      if (response.statusCode == 401 && includeAuth) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          final retryHeaders = await _getHeaders(includeAuth: true);
          final retryResponse = await http.post(
            url,
            headers: retryHeaders,
            body: jsonEncode(body),
          ).timeout(_timeout);
          return _handleResponse(retryResponse);
        } else {
          _handleAuthFailure();
          return _handleResponse(response);
        }
      }

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
      final url = Uri.parse('$baseUrl$endpoint');
      final headers = await _getHeaders(includeAuth: includeAuth);
      final response = await http.put(
        url,
        headers: headers,
        body: jsonEncode(body),
      ).timeout(_timeout);

      if (response.statusCode == 401 && includeAuth) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          final retryHeaders = await _getHeaders(includeAuth: true);
          final retryResponse = await http.put(
            url,
            headers: retryHeaders,
            body: jsonEncode(body),
          ).timeout(_timeout);
          return _handleResponse(retryResponse);
        } else {
          _handleAuthFailure();
          return _handleResponse(response);
        }
      }

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

  static Future<dynamic> patch(
    String endpoint,
    Map<String, dynamic> body, {
    bool includeAuth = true,
  }) async {
    try {
      final url = Uri.parse('$baseUrl$endpoint');
      final headers = await _getHeaders(includeAuth: includeAuth);
      final response = await http.patch(
        url,
        headers: headers,
        body: jsonEncode(body),
      ).timeout(_timeout);

      if (response.statusCode == 401 && includeAuth) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          final retryHeaders = await _getHeaders(includeAuth: true);
          final retryResponse = await http.patch(
            url,
            headers: retryHeaders,
            body: jsonEncode(body),
          ).timeout(_timeout);
          return _handleResponse(retryResponse);
        } else {
          _handleAuthFailure();
          return _handleResponse(response);
        }
      }

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
      final url = Uri.parse('$baseUrl$endpoint');
      final headers = await _getHeaders(includeAuth: includeAuth);

      debugPrint('🗑️ DELETE $endpoint');

      final response = await http.delete(url, headers: headers).timeout(_timeout);

      debugPrint('📥 Response status: ${response.statusCode}');
      debugPrint('📥 Response body: ${response.body}');

      if (response.statusCode == 401 && includeAuth) {
        final refreshed = await refreshAccessToken();
        if (refreshed) {
          final retryHeaders = await _getHeaders(includeAuth: true);
          final retryResponse = await http.delete(url, headers: retryHeaders).timeout(_timeout);
          return _handleResponse(retryResponse);
        } else {
          _handleAuthFailure();
          return _handleResponse(response);
        }
      }

      return _handleResponse(response);
    } on TimeoutException {
      throw Exception('Connection timeout - Please check your internet');
    } catch (e) {
      if (e.toString().contains('SocketException') ||
          e.toString().contains('HandshakeException')) {
        throw Exception('Unable to connect - Check your internet connection');
      }
      debugPrint('❌ DELETE error: $e');
      rethrow;
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

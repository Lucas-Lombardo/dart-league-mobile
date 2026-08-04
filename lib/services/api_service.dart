import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../utils/api_config.dart';
import '../utils/storage_service.dart';

class ApiService {
  static const Duration _timeout = Duration(seconds: 30);

  // Sent on every request so the backend can gate version-dependent features
  // (tournament entry requires an up-to-date app). Resolved once per session.
  static String? _appVersion;
  static String? _appPlatform;
  // Phone model, stored server-side to correlate AI-scoring quality and
  // thermal behaviour with actual hardware. iOS keeps the raw machine id
  // ("iPhone14,3") — the marketing name hides which chip is in the phone.
  static String? _deviceModel;
  static Future<void>? _versionInfoFuture;

  static Future<void> _ensureVersionInfo() {
    return _versionInfoFuture ??= () async {
      if (kIsWeb) return;
      try {
        final info = await PackageInfo.fromPlatform();
        _appVersion = info.version;
        _appPlatform = Platform.isIOS ? 'ios' : 'android';
      } catch (e) {
        debugPrint('ApiService: could not resolve app version: $e');
      }
      // Separate try: a device-info failure must not cost us the version.
      try {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isIOS) {
          _deviceModel = _asHeaderValue((await deviceInfo.iosInfo).utsname.machine);
        } else {
          final android = await deviceInfo.androidInfo;
          _deviceModel =
              _asHeaderValue('${android.manufacturer} ${android.model}');
        }
      } catch (e) {
        debugPrint('ApiService: could not resolve device model: $e');
      }
    }();
  }

  /// Keeps only printable ASCII, the range dart:io accepts in a header value
  /// (`_isValueChar`: 32-127). The model name comes from the OEM: a single
  /// non-ASCII character in it would make `HttpHeaders.set` throw a
  /// FormatException on EVERY request, killing the app for that user with no
  /// server-side trace. Null when nothing usable is left.
  static String? _asHeaderValue(String? raw) {
    if (raw == null) return null;
    final cleaned =
        String.fromCharCodes(raw.codeUnits.where((c) => c >= 0x20 && c < 0x7F))
            .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  /// Called when token refresh fails -- the app should navigate to login.
  /// This is a static callback that persists for the app lifetime.
  /// Use [resetAuthFailure] during logout/cleanup to prevent stale references.
  static void Function()? onAuthFailure;

  static void resetAuthFailure() {
    onAuthFailure = null;
  }

  static Completer<bool>? _refreshCompleter;
  static int _refreshFailCount = 0;
  static DateTime? _nextRefreshAllowedAt;

  static Future<Map<String, String>> _getHeaders({bool includeAuth = true}) async {
    final headers = {
      'Content-Type': 'application/json',
    };

    await _ensureVersionInfo();
    if (_appVersion != null) headers['X-App-Version'] = _appVersion!;
    if (_appPlatform != null) headers['X-App-Platform'] = _appPlatform!;
    if (_deviceModel != null) headers['X-Device-Model'] = _deviceModel!;

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
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    if (_nextRefreshAllowedAt != null &&
        DateTime.now().isBefore(_nextRefreshAllowedAt!)) {
      return false;
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
        _refreshFailCount = 0;
        _nextRefreshAllowedAt = null;
        _refreshCompleter!.complete(true);
        return true;
      } else {
        debugPrint('Token refresh failed: ${response.statusCode}');
        _applyRefreshBackoff();
        _refreshCompleter!.complete(false);
        return false;
      }
    } catch (e) {
      debugPrint('Token refresh error: $e');
      _applyRefreshBackoff();
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  static void _applyRefreshBackoff() {
    _refreshFailCount++;
    final delaySec = _refreshFailCount.clamp(1, 5) * 2; // 2, 4, 6, 8, 10s cap
    _nextRefreshAllowedAt = DateTime.now().add(Duration(seconds: delaySec));
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

      if (kDebugMode) debugPrint('POST $endpoint');

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      ).timeout(_timeout);

      if (kDebugMode) debugPrint('Response status: ${response.statusCode}');

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

      if (kDebugMode) debugPrint('DELETE $endpoint');

      final response = await http.delete(url, headers: headers).timeout(_timeout);

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
    dynamic body;
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(response.body);
      } on FormatException {
        if (statusCode >= 200 && statusCode < 300) {
          return response.body;
        }
        throw Exception('Error $statusCode: Invalid response from server');
      }
    }

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

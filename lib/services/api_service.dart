import 'dart:convert';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kIsWeb, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../utils/api_config.dart';
import '../utils/storage_service.dart';

/// What a refresh attempt established about the session.
enum RefreshOutcome {
  /// New access token stored.
  refreshed,

  /// The server does not know this refresh token: the session is over.
  rejected,

  /// Could not reach a verdict (network, timeout, 5xx, backoff): keep going.
  unavailable,
}

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

  /// Called once the session is definitely gone -- the app should navigate
  /// to login. This is a static callback that persists for the app lifetime.
  /// Use [resetAuthFailure] during logout/cleanup to prevent stale references.
  static void Function()? onAuthFailure;

  /// Whether a match is being played right now. While it is, a lost session
  /// is held back (see [handleAuthFailure]): leaving the match screen emits a
  /// voluntary forfeit, and the socket keeps serving an in-progress match on
  /// an expired token for up to an hour.
  static bool Function()? isMatchLive;

  static void resetAuthFailure() {
    onAuthFailure = null;
    _deferredAuthFailure?.cancel();
    _deferredAuthFailure = null;
    _authFailureNotified = false;
  }

  static Completer<RefreshOutcome>? _refreshCompleter;
  static int _refreshFailCount = 0;
  static DateTime? _nextRefreshAllowedAt;
  // The server said our refresh token is unknown: no point asking again until
  // a sign-in stores a new one.
  static bool _sessionRejected = false;
  static bool _authFailureNotified = false;
  static Timer? _deferredAuthFailure;
  static const Duration _deferredAuthFailurePoll = Duration(seconds: 5);

  /// A sign-in stored fresh tokens: forget any earlier rejection.
  static void markSessionValid() {
    _sessionRejected = false;
    _authFailureNotified = false;
    _refreshFailCount = 0;
    _nextRefreshAllowedAt = null;
    _deferredAuthFailure?.cancel();
    _deferredAuthFailure = null;
  }

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
  /// Returns true if refresh succeeded, false otherwise. Kept for callers
  /// that only need to know whether to retry; [refreshSession] tells the
  /// transient failure from the definitive one.
  static Future<bool> refreshAccessToken() async {
    return await refreshSession() == RefreshOutcome.refreshed;
  }

  /// Deduplicates concurrent refresh calls. Only a 401 from the refresh
  /// endpoint is [RefreshOutcome.rejected]; a timeout, a dead network or a
  /// 5xx is [RefreshOutcome.unavailable] and the session is kept -- the next
  /// 401 tries again after a short backoff.
  static Future<RefreshOutcome> refreshSession() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    if (_sessionRejected) return RefreshOutcome.rejected;
    if (_nextRefreshAllowedAt != null &&
        DateTime.now().isBefore(_nextRefreshAllowedAt!)) {
      return RefreshOutcome.unavailable;
    }

    final completer = Completer<RefreshOutcome>();
    _refreshCompleter = completer;
    RefreshOutcome outcome;
    try {
      outcome = await _refreshOnce();
    } catch (e) {
      debugPrint('Token refresh error: $e');
      _applyRefreshBackoff();
      outcome = RefreshOutcome.unavailable;
      reportClientEvent('auth.refresh_error', '$e');
    }
    _refreshCompleter = null;
    completer.complete(outcome);
    return outcome;
  }

  static Future<RefreshOutcome> _refreshOnce() async {
    final refreshToken = await StorageService.getRefreshToken();
    if (refreshToken == null) {
      // Nothing to refresh with: there is no session to keep.
      _sessionRejected = true;
      return RefreshOutcome.rejected;
    }

    final url = Uri.parse('$baseUrl/auth/refresh');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    ).timeout(_timeout);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = jsonDecode(response.body);
      final accessToken = body is Map ? body['access_token'] as String? : null;
      final newRefresh = body is Map ? body['refresh_token'] as String? : null;
      if (accessToken == null) {
        debugPrint('Token refresh: malformed response');
        _applyRefreshBackoff();
        reportClientEvent('auth.refresh_malformed', response.body);
        return RefreshOutcome.unavailable;
      }
      // Memory first, keychain best-effort: these never throw.
      await StorageService.saveToken(accessToken);
      if (newRefresh != null && newRefresh != refreshToken) {
        await StorageService.saveRefreshToken(newRefresh);
      }
      _refreshFailCount = 0;
      _nextRefreshAllowedAt = null;
      return RefreshOutcome.refreshed;
    }

    if (response.statusCode == 401) {
      debugPrint('Token refresh rejected by the server');
      _sessionRejected = true;
      reportClientEvent(
        'auth.refresh_rejected',
        'refresh token rejected',
        context: {'body': _clip(response.body)},
      );
      return RefreshOutcome.rejected;
    }

    debugPrint('Token refresh failed: ${response.statusCode}');
    _applyRefreshBackoff();
    reportClientEvent(
      'auth.refresh_failed',
      'HTTP ${response.statusCode}',
      context: {'body': _clip(response.body)},
    );
    return RefreshOutcome.unavailable;
  }

  static void _applyRefreshBackoff() {
    _refreshFailCount++;
    final delaySec = _refreshFailCount.clamp(1, 5) * 2; // 2, 4, 6, 8, 10s cap
    _nextRefreshAllowedAt = DateTime.now().add(Duration(seconds: delaySec));
  }

  /// The session is gone for good. Signs out now -- or, during a live match,
  /// once the match is over: the player keeps playing on the socket, and
  /// navigating away would hand the opponent an instant forfeit.
  @visibleForTesting
  static void handleAuthFailure() {
    if (_authFailureNotified || _deferredAuthFailure != null) return;
    if (isMatchLive?.call() == true) {
      debugPrint('ApiService: session lost during a live match, sign-out deferred');
      _deferredAuthFailure = Timer.periodic(_deferredAuthFailurePoll, (timer) {
        if (isMatchLive?.call() == true) return;
        timer.cancel();
        _deferredAuthFailure = null;
        _notifyAuthFailure();
      });
      return;
    }
    _notifyAuthFailure();
  }

  static void _notifyAuthFailure() {
    if (_authFailureNotified) return;
    _authFailureNotified = true;
    onAuthFailure?.call();
  }

  /// Sends a diagnostic line to the server log (`POST /client-logs`), for
  /// the failures only the app can see. Fire and forget, never throws, and
  /// never goes through the 401 path: the session may be exactly what broke.
  static DateTime? _lastClientEventAt;
  static Future<void> reportClientEvent(
    String event,
    String message, {
    Map<String, dynamic>? context,
  }) async {
    final now = DateTime.now();
    if (_lastClientEventAt != null &&
        now.difference(_lastClientEventAt!) < const Duration(seconds: 5)) {
      return;
    }
    _lastClientEventAt = now;
    try {
      final headers = await _getHeaders(includeAuth: true);
      await http
          .post(
            Uri.parse('$baseUrl/client-logs'),
            headers: headers,
            body: jsonEncode({
              'event': event,
              'message': _clip(message),
              'context': ?context,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('ApiService: client log not sent: $e');
    }
  }

  static String _clip(String s) => s.length <= 500 ? s : s.substring(0, 500);

  static Future<dynamic> get(String endpoint, {bool includeAuth = true}) async {
    try {
      final url = Uri.parse('$baseUrl$endpoint');
      final headers = await _getHeaders(includeAuth: includeAuth);

      final response = await http.get(url, headers: headers).timeout(_timeout);

      if (response.statusCode == 401 && includeAuth) {
        final outcome = await refreshSession();
        if (outcome == RefreshOutcome.refreshed) {
          final retryHeaders = await _getHeaders(includeAuth: true);
          final retryResponse = await http.get(url, headers: retryHeaders).timeout(_timeout);
          return _handleResponse(retryResponse);
        } else {
          if (outcome == RefreshOutcome.rejected) handleAuthFailure();
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
        final outcome = await refreshSession();
        if (outcome == RefreshOutcome.refreshed) {
          final retryHeaders = await _getHeaders(includeAuth: true);
          final retryResponse = await http.post(
            url,
            headers: retryHeaders,
            body: jsonEncode(body),
          ).timeout(_timeout);
          return _handleResponse(retryResponse);
        } else {
          if (outcome == RefreshOutcome.rejected) handleAuthFailure();
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
        final outcome = await refreshSession();
        if (outcome == RefreshOutcome.refreshed) {
          final retryHeaders = await _getHeaders(includeAuth: true);
          final retryResponse = await http.put(
            url,
            headers: retryHeaders,
            body: jsonEncode(body),
          ).timeout(_timeout);
          return _handleResponse(retryResponse);
        } else {
          if (outcome == RefreshOutcome.rejected) handleAuthFailure();
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
        final outcome = await refreshSession();
        if (outcome == RefreshOutcome.refreshed) {
          final retryHeaders = await _getHeaders(includeAuth: true);
          final retryResponse = await http.patch(
            url,
            headers: retryHeaders,
            body: jsonEncode(body),
          ).timeout(_timeout);
          return _handleResponse(retryResponse);
        } else {
          if (outcome == RefreshOutcome.rejected) handleAuthFailure();
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
        final outcome = await refreshSession();
        if (outcome == RefreshOutcome.refreshed) {
          final retryHeaders = await _getHeaders(includeAuth: true);
          final retryResponse = await http.delete(url, headers: retryHeaders).timeout(_timeout);
          return _handleResponse(retryResponse);
        } else {
          if (outcome == RefreshOutcome.rejected) handleAuthFailure();
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

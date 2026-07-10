import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../utils/api_config.dart';
import '../utils/storage_service.dart';
import 'api_service.dart';

class SocketService {
  static io.Socket? _socket;
  static Completer<void>? _connectCompleter;
  static Function()? _onReconnectHandler;
  static Function()? _onDisconnectHandler;
  static Function()? _onConnectFailedHandler;

  // Multi-listener connection-state notifications. The legacy single-slot
  // handlers above are kept for existing callers (matchmaking); these lists
  // let other consumers (GameProvider) observe the connection without
  // clobbering each other.
  static final List<Function()> _disconnectListeners = [];
  static final List<Function()> _reconnectListeners = [];
  static final List<Function()> _connectFailedListeners = [];

  // Registered handlers keyed by event name — enables targeted removal
  static final Map<String, Function(dynamic)> _handlers = {};

  static StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  static Timer? _reconnectRestartTimer;

  // True between a disconnect and the next successful (re)connect. Gates
  // reconnect dispatch so it fires exactly once per drop, whichever event
  // surfaces the recovery first.
  static bool _wasDisconnected = false;

  // Rate-limits the refresh-token + socket-rebuild recovery so an
  // unrecoverable auth problem can't loop it.
  static DateTime? _lastAuthRebuild;

  // Capability announced by the server in its `authenticated` payload.
  //
  // False until the current socket has been authenticated by a server that
  // understands per-dart ids. The providers MUST NOT attach a dartId, retry an
  // un-acked dart, or send dartCount while this is false: an older backend
  // silently drops the unknown dartId, scores the dart, and never acks — so a
  // retry loop would score the same dart on every attempt. Reset on every
  // disconnect so a backend rollback mid-session degrades us safely instead of
  // corrupting scores.
  static bool _supportsDartAck = false;

  /// Whether the server this socket is authenticated against acknowledges and
  /// deduplicates individual darts. See [_supportsDartAck].
  static bool get supportsDartAck => _supportsDartAck;

  static void _handleAuthenticated(dynamic data) {
    final supports = data is Map && data['supportsDartAck'] == true;
    if (supports != _supportsDartAck) {
      debugPrint('SocketService: server supportsDartAck=$supports');
    }
    _supportsDartAck = supports;
  }

  /// Refresh the access token and rebuild the socket with it, keeping every
  /// registered event handler. Used when the server signals an auth problem —
  /// a server-initiated disconnect turns off socket.io auto-reconnect, so
  /// without this the app stayed offline until a restart.
  static Future<void> _refreshTokenAndRebuild() async {
    final now = DateTime.now();
    if (_lastAuthRebuild != null &&
        now.difference(_lastAuthRebuild!) < const Duration(seconds: 10)) {
      return;
    }
    _lastAuthRebuild = now;
    try {
      final refreshed = await ApiService.refreshAccessToken();
      if (!refreshed) return;
      debugPrint('SocketService: token refreshed, rebuilding socket');
      _disconnectInternal(preserveHandlers: true);
      _connectCompleter = null;
      await connect();
    } catch (e) {
      debugPrint('SocketService: auth rebuild failed: $e');
    }
  }

  // Fire the reconnect handlers once, only if we were actually disconnected.
  // Both onConnect and the manager 'reconnect' event funnel through here: on
  // Android a recovered connection often surfaces as a fresh 'connect' rather
  // than the manager 'reconnect' event, so keying recovery solely off
  // 'reconnect' left the "connection lost" banner stuck. The flag makes the
  // two paths idempotent (first one wins, the other is a no-op).
  static void _dispatchReconnected() {
    if (!_wasDisconnected) return;
    _wasDisconnected = false;
    _onReconnectHandler?.call();
    for (final l in List.of(_reconnectListeners)) {
      l();
    }
  }

  static bool get isConnected => _socket?.connected ?? false;
  static String? get socketId => _socket?.id;

  static Future<void> connect() async {
    if (_connectCompleter != null) {
      return _connectCompleter!.future;
    }
    if (isConnected) return;

    _startConnectivityMonitoring();

    // Reuse the existing socket when we have one: it carries every handler
    // registered via on(), and socket_io_client caches sockets per URL — a
    // second io.io() call would hand back the same instance and our
    // connection-callback registrations below would be added AGAIN, causing
    // duplicate dispatches per event.
    if (_socket != null) {
      _socket!.connect();
      return;
    }

    _connectCompleter = Completer<void>();

    try {
      final token = await StorageService.getToken();

      if (token == null) {
        throw Exception('No authentication token found');
      }

      final socketUrl = baseUrl;
      debugPrint('SocketService: Connecting to $socketUrl');

      _socket = io.io(
        socketUrl,
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableAutoConnect()
            // No reconnection-attempts cap: the old cap (20) gave up after
            // ~3 minutes — inside the 5-minute match grace period — leaving
            // the app permanently offline until a restart.
            .enableReconnection()
            .setReconnectionDelay(2000)
            .setReconnectionDelayMax(10000)
            .setAuth({'token': token})
            .build(),
      );

      _socket!.onConnect((_) {
        debugPrint('SocketService: Connected! socketId=${_socket?.id}');
        // Recovery after a drop reliably surfaces here even when the manager
        // 'reconnect' event does not (common on Android). Idempotent: a no-op
        // on the very first connect since _wasDisconnected is false.
        _dispatchReconnected();
      });

      // Capability handshake. Attached directly to the socket (not through the
      // single-slot `on` registry) so a provider can still listen to
      // 'authenticated' without displacing this.
      _socket!.on('authenticated', _handleAuthenticated);

      _socket!.onDisconnect((reason) {
        debugPrint('SocketService: Disconnected - reason: $reason');
        _wasDisconnected = true;
        // Re-derived from the next 'authenticated'. Until then we assume the
        // server cannot dedup darts, which is always the safe assumption.
        _supportsDartAck = false;
        _onDisconnectHandler?.call();
        for (final l in List.of(_disconnectListeners)) {
          l();
        }
        // A server-initiated disconnect (usually an auth rejection) disables
        // socket.io auto-reconnect: without intervention the app stays
        // offline for good. Refresh the token and rebuild.
        if (reason.toString().contains('io server disconnect')) {
          _refreshTokenAndRebuild();
        }
      });

      // Server-side auth verdicts. 'invalid_token' = we were (or are about to
      // be) kicked; 'token_expiring' = the server let an expired-token
      // reconnect through for an active match and asks us to refresh for the
      // next one. Both resolve by refreshing; only the kick needs a rebuild.
      _socket!.on('auth_error', (data) {
        final reason = (data is Map ? data['reason'] : null)?.toString();
        debugPrint('SocketService: auth_error from server: $reason');
        if (reason == 'token_expiring') {
          ApiService.refreshAccessToken();
        } else {
          _refreshTokenAndRebuild();
        }
      });

      _socket!.on('reconnect', (_) {
        debugPrint('SocketService: Reconnected');
        _dispatchReconnected();
      });

      _socket!.on('reconnect_failed', (_) {
        debugPrint('SocketService: Reconnection cycle failed, restarting');
        _onConnectFailedHandler?.call();
        for (final l in List.of(_connectFailedListeners)) {
          l();
        }
        // Safety net: never stay permanently offline. With unbounded
        // attempts this shouldn't fire, but if it does, kick off a new cycle.
        _reconnectRestartTimer?.cancel();
        _reconnectRestartTimer = Timer(const Duration(seconds: 5), () {
          if (!isConnected) _socket?.connect();
        });
      });

      _socket!.onConnectError((error) async {
        debugPrint('SocketService: Connect error - $error');
        if (error.toString().contains('401') ||
            error.toString().contains('unauthorized') ||
            error.toString().contains('jwt')) {
          debugPrint('SocketService: Auth error, attempting token refresh...');
          final refreshed = await ApiService.refreshAccessToken();
          if (refreshed) {
            debugPrint('SocketService: Token refreshed, reconnecting with new token...');
            // Keep the registered event handlers: they are re-attached to the
            // new socket inside connect(). Wiping them here (the old behavior)
            // silently killed every game listener while the providers still
            // believed they were set up — a frozen match on a healthy socket.
            _disconnectInternal(preserveHandlers: true);
            _connectCompleter = null;
            await connect();
          }
        }
      });

      _socket!.onError((error) {
        debugPrint('SocketService: Error - $error');
      });

      // Re-attach handlers that were registered on a previous socket instance
      // (auth-refresh rebuild path). No-op on the very first connect.
      _handlers.forEach((event, handler) {
        _socket!.on(event, handler);
      });

      _socket!.connect();
    } catch (e) {
      rethrow;
    } finally {
      _connectCompleter?.complete();
      _connectCompleter = null;
    }
  }

  /// Reconnect immediately when the network comes back (wifi↔cellular switch,
  /// airplane mode off, …) instead of waiting for the next backoff attempt.
  static void _startConnectivityMonitoring() {
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork =
          results.any((r) => r != ConnectivityResult.none);
      if (hasNetwork && !isConnected && _socket != null) {
        debugPrint('SocketService: Network available again, reconnecting now');
        _socket!.connect();
      }
    });
  }

  /// [preserveHandlers] keeps the tracked event handlers so an immediately
  /// following connect() re-attaches them to the new socket (token-refresh
  /// rebuild). A full teardown (logout) clears them.
  static void _disconnectInternal({bool preserveHandlers = false}) {
    _reconnectRestartTimer?.cancel();
    _reconnectRestartTimer = null;
    _supportsDartAck = false;
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      if (!preserveHandlers) {
        _handlers.clear();
      }
    }
  }

  static Future<void> disconnect() async {
    if (_connectCompleter != null) {
      await _connectCompleter!.future;
    }
    _disconnectInternal();
  }

  /// Test seam: when set, [emit] routes here instead of touching a real socket,
  /// and [debugDispatch] feeds server events back to the registered handlers.
  /// Never set in production code.
  @visibleForTesting
  static void Function(String event, dynamic data)? debugEmitOverride;

  /// Test seam: deliver [event] to whatever handler `on(event, …)` registered,
  /// exactly as socket.io would. 'authenticated' also drives the capability
  /// handshake, as it does against a real socket.
  @visibleForTesting
  static void debugDispatch(String event, dynamic data) {
    if (event == 'authenticated') _handleAuthenticated(data);
    _handlers[event]?.call(data);
  }

  @visibleForTesting
  static void debugReset() {
    debugEmitOverride = null;
    _supportsDartAck = false;
    _handlers.clear();
    _disconnectListeners.clear();
    _reconnectListeners.clear();
    _connectFailedListeners.clear();
  }

  static void emit(String event, dynamic data) {
    final override = debugEmitOverride;
    if (override != null) {
      override(event, data);
      return;
    }
    if (!isConnected) {
      throw Exception('Socket not connected');
    }
    _socket!.emit(event, data);
  }

  static void on(String event, Function(dynamic) handler) {
    // Remove any previously registered handler for this event before adding the new one
    final existing = _handlers[event];
    if (existing != null && _socket != null) {
      _socket!.off(event, existing);
    }
    _handlers[event] = handler;
    // Socket may be mid-rebuild (token refresh); connect() attaches every
    // tracked handler to the new instance, so storing it is enough.
    _socket?.on(event, handler);
  }

  static void off(String event) {
    if (_socket == null) return;
    final handler = _handlers.remove(event);
    if (handler != null) {
      _socket!.off(event, handler);
    }
    // If no tracked handler exists, do nothing — avoids removing
    // handlers registered by other sources for the same event.
  }

  static Future<void> ensureConnected({
    Duration timeout = const Duration(seconds: 10),
    Duration pollInterval = const Duration(milliseconds: 250),
  }) async {
    if (isConnected) return;
    await connect();

    final deadline = DateTime.now().add(timeout);
    while (!isConnected && DateTime.now().isBefore(deadline)) {
      await Future.delayed(pollInterval);
    }
    if (!isConnected) {
      throw Exception('Socket connection timed out after ${timeout.inSeconds}s');
    }
  }

  static void setReconnectHandler(Function() handler) {
    _onReconnectHandler = handler;
  }

  static void clearReconnectHandler() {
    _onReconnectHandler = null;
  }

  static void setDisconnectHandler(Function() handler) {
    _onDisconnectHandler = handler;
  }

  static void clearDisconnectHandler() {
    _onDisconnectHandler = null;
  }

  static void setConnectFailedHandler(Function() handler) {
    _onConnectFailedHandler = handler;
  }

  static void clearConnectFailedHandler() {
    _onConnectFailedHandler = null;
  }

  // Additive listener API — multiple consumers can observe connection state.
  static void addDisconnectListener(Function() listener) {
    if (!_disconnectListeners.contains(listener)) {
      _disconnectListeners.add(listener);
    }
  }

  static void removeDisconnectListener(Function() listener) {
    _disconnectListeners.remove(listener);
  }

  static void addReconnectListener(Function() listener) {
    if (!_reconnectListeners.contains(listener)) {
      _reconnectListeners.add(listener);
    }
  }

  static void removeReconnectListener(Function() listener) {
    _reconnectListeners.remove(listener);
  }

  static void addConnectFailedListener(Function() listener) {
    if (!_connectFailedListeners.contains(listener)) {
      _connectFailedListeners.add(listener);
    }
  }

  static void removeConnectFailedListener(Function() listener) {
    _connectFailedListeners.remove(listener);
  }
}

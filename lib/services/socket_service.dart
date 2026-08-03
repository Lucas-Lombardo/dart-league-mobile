import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../utils/api_config.dart';
import '../utils/storage_service.dart';
import 'api_service.dart';
import 'rtc_frames_service.dart';

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

  // Fired when the socket stops belonging to the user it used to belong to
  // (account switch / logout). Consumers holding per-user state — the game
  // providers' matchId + myUserId — must drop it: see [setSessionUser].
  static final List<Function()> _sessionChangeListeners = [];

  // Registered handlers keyed by event name — enables targeted removal
  static final Map<String, Function(dynamic)> _handlers = {};

  // Who registered each handler. The registry is one slot per event and
  // GameProvider / TournamentGameProvider listen to the SAME event names, so
  // whichever registers last owns the slot — that part is fine, the loser is
  // idle. What was NOT fine: an off() from the idle provider (its reset()
  // clears the same event list) tore out the ACTIVE provider's handler, and
  // the running match went deaf. off() now only removes what its caller
  // actually registered.
  static final Map<String, Object> _handlerOwners = {};

  static StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  static Timer? _reconnectRestartTimer;

  // True between a disconnect and the next successful (re)connect. Gates
  // reconnect dispatch so it fires exactly once per drop, whichever event
  // surfaces the recovery first.
  static bool _wasDisconnected = false;

  // Rate-limits the refresh-token + socket-rebuild recovery so an
  // unrecoverable auth problem can't loop it.
  static DateTime? _lastAuthRebuild;

  // Same idea for the identity-mismatch rebuild (see _handleAuthenticated).
  static DateTime? _lastIdentityRebuild;

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

  // Server capability: friend/support chat (/chat REST routes + chat:message
  // socket event). The chat UI stays functional without it (REST errors are
  // surfaced), but realtime delivery needs it. Reset on every disconnect,
  // like the flags above, so a backend rollback degrades us safely.
  static bool _supportsChat = false;

  // Server capability: RTC v2 (P2P WebRTC). The server relays `rtc_signal`
  // between the two match participants and, when both sockets declared the
  // capability in their CONNECT auth payload, adds an `rtcV2` block to every
  // credential-carrying match payload. The app never chooses P2P from this
  // flag alone — it acts on the presence of `rtcV2` in the match payload,
  // which is the server's both-sides-support verdict. Reset on disconnect
  // like the other flags so a backend rollback degrades to Agora.
  static bool _supportsRtcV2 = false;

  // True once the current socket has received the server's `authenticated`
  // handshake — the event that carries the capability flags above. Reset on
  // every disconnect, like the flags themselves, so it always describes the
  // CURRENT socket.
  static bool _isAuthenticated = false;

  // Who the app is logged in as (set by AuthProvider), and who the LIVE socket
  // is actually authenticated as (echoed by the server's `authenticated`
  // payload).
  //
  // These used to be able to disagree, and silently: the JWT is baked into the
  // socket at construction, connect() short-circuits on an existing socket, and
  // nothing tore the socket down on logout. Logging out and back in as another
  // account therefore kept a socket authenticated as the PREVIOUS user, while
  // every HTTP call used the new one. The server then had no socket for the
  // logged-in user — `emitToUser: No socket found` — so match_invite,
  // matchReadyUpdate, tournamentMatchStart and game_started all went nowhere,
  // and the emits this app sent were attributed to the old account. The app
  // looked online the whole time.
  static String? _sessionUserId;
  static String? _authenticatedUserId;

  /// Whether the server this socket is authenticated against acknowledges and
  /// deduplicates individual darts. See [_supportsDartAck].
  static bool get supportsDartAck => _supportsDartAck;

  /// Whether the server has the friend/support chat (REST + `chat:message`).
  static bool get supportsChat => _supportsChat;

  /// Whether the server this socket is authenticated against can run match
  /// video as P2P WebRTC (`rtc_signal` relay + `rtcV2` payload block).
  static bool get supportsRtcV2 => _supportsRtcV2;

  /// Whether the current socket has completed the `authenticated` handshake.
  static bool get isAuthenticated => _isAuthenticated;

  /// The user the LIVE socket is authenticated as, per the server. Null until
  /// the handshake lands. Never assume it equals the logged-in user — compare
  /// with [belongsToSession] instead.
  static String? get authenticatedUserId => _authenticatedUserId;

  /// True when the socket is connected AND authenticated as the user the app
  /// is currently logged in as. Anything that starts a match must check this:
  /// a socket belonging to someone else delivers none of the match events.
  static bool get belongsToSession =>
      isConnected &&
      _isAuthenticated &&
      _sessionUserId != null &&
      _authenticatedUserId == _sessionUserId;

  /// Bind the socket to the logged-in user. Called by AuthProvider on login,
  /// register, session restore and logout.
  ///
  /// A change of user tears the socket down and rebuilds it with the new
  /// token (handlers are preserved and re-attached), and notifies the session
  /// listeners so per-user state is dropped. `null` (logout) is a full
  /// teardown, handlers included.
  static void setSessionUser(String? userId) {
    if (userId == _sessionUserId) return;
    final previous = _sessionUserId;
    _sessionUserId = userId;
    if (previous == null && userId != null && _socket == null) {
      // First login of the process — nothing to rebuild.
      return;
    }
    debugPrint('SocketService: session user $previous -> $userId');
    if (userId == null) {
      _disconnectInternal();
    } else {
      _rebuildWithCurrentToken();
    }
    for (final l in List.of(_sessionChangeListeners)) {
      l();
    }
  }

  /// Drop the current socket and build a new one from the token in storage,
  /// keeping every registered handler (connect() re-attaches them). Fire and
  /// forget — callers reach the socket through ensureConnected().
  static void _rebuildWithCurrentToken() {
    _disconnectInternal(preserveHandlers: true);
    _connectCompleter = null;
    connect().catchError((Object e) {
      debugPrint('SocketService: rebuild failed: $e');
    });
  }

  static void _handleAuthenticated(dynamic data) {
    _isAuthenticated = true;
    _authenticatedUserId = data is Map ? data['userId'] as String? : null;
    if (_sessionUserId != null &&
        _authenticatedUserId != null &&
        _authenticatedUserId != _sessionUserId) {
      // Stale socket: it authenticated as somebody else. Rebuild with the
      // token currently in storage rather than staying silently mis-bound.
      // Rate-limited: if storage still holds the other account's token this
      // must not spin.
      final now = DateTime.now();
      if (_lastIdentityRebuild != null &&
          now.difference(_lastIdentityRebuild!) < const Duration(seconds: 10)) {
        return;
      }
      _lastIdentityRebuild = now;
      debugPrint(
        'SocketService: socket authenticated as $_authenticatedUserId '
        'but session is $_sessionUserId — rebuilding',
      );
      // Deliberately NOT adopting this socket's capability flags: they
      // describe a connection this user will never receive events on.
      _rebuildWithCurrentToken();
      return;
    }
    final supports = data is Map && data['supportsDartAck'] == true;
    if (supports != _supportsDartAck) {
      debugPrint('SocketService: server supportsDartAck=$supports');
    }
    _supportsDartAck = supports;

    final supportsChat = data is Map && data['supportsChat'] == true;
    if (supportsChat != _supportsChat) {
      debugPrint('SocketService: server supportsChat=$supportsChat');
    }
    _supportsChat = supportsChat;

    final supportsRtcV2 = data is Map && data['supportsRtcV2'] == true;
    if (supportsRtcV2 != _supportsRtcV2) {
      debugPrint('SocketService: server supportsRtcV2=$supportsRtcV2');
    }
    _supportsRtcV2 = supportsRtcV2;
  }

  /// Supplies the CONNECT-packet auth payload, called by socket.io on every
  /// connection attempt (first connect, auto-reconnects, and rebuilds alike).
  ///
  /// The token must be resolved here, at send time, and never baked into the
  /// socket options: socket_io_client caches the Manager AND the Socket per
  /// URL (Manager.destroy never removes the namespace entry), so every
  /// "rebuild" gets the same Socket instance back and its construction-time
  /// `auth` map would outlive every token refresh. With the 15-minute access
  /// token, any socket older than that reconnected in a `jwt expired` loop
  /// forever while HTTP kept working on refreshed tokens — the 2026-07-25
  /// tournament outage.
  static Future<void> _authPayload(dynamic cb) async {
    String? token;
    try {
      token = await StorageService.getToken();
      if (token != null && _tokenLooksExpired(token)) {
        debugPrint('SocketService: token expired/expiring, refreshing');
        await ApiService.refreshAccessToken();
        token = await StorageService.getToken();
      }
    } catch (e) {
      debugPrint('SocketService: auth payload error: $e');
    }
    // A null/stale token still gets sent: the server answers auth_error and
    // the recovery paths below take over (refresh is backoff-limited).
    //
    // supportsRtcV2 declares the P2P capability. It rides the handshake auth
    // (never a DTO) on purpose: handshake keys bypass the backend's
    // forbidNonWhitelisted ValidationPipe, so an OLD backend ignores it
    // silently — no 400, no behavior change. Declared only where the game
    // screen will actually take the P2P path (RtcFramesService.isSupported):
    // a web build declaring true made the server emit rtcV2 to the MOBILE
    // opponent, who then burned the 10s watchdog against a peer that never
    // signals before falling back to Agora.
    cb({'token': token, 'supportsRtcV2': RtcFramesService.isSupported});
  }

  /// Local expiry check (30s skew) so we refresh BEFORE the server rejects us,
  /// saving the reject-refresh-reconnect round trip. Unparseable tokens are
  /// treated as valid — the server stays the authority.
  static bool _tokenLooksExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final payload = json.decode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = payload is Map ? payload['exp'] : null;
      if (exp is! num) return false;
      final expiry =
          DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      return DateTime.now()
          .isAfter(expiry.subtract(const Duration(seconds: 30)));
    } catch (_) {
      return false;
    }
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
            .setAuth({'token': token, 'supportsRtcV2': RtcFramesService.isSupported})
            .build(),
      );

      // io.io() may have handed back the cached Socket from a previous
      // (dispose+rebuild) cycle, options ignored — see _authPayload. Assigning
      // the auth callback directly is the only per-attempt token path that
      // survives the cache, and it must be (re)set on every connect() build.
      _socket!.auth = _authPayload;

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
        // server cannot dedup darts, the safe assumption.
        _isAuthenticated = false;
        _authenticatedUserId = null;
        _supportsDartAck = false;
        _supportsChat = false;
        _supportsRtcV2 = false;
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
    // Never let a connectivity-plugin failure abort connect(): this is only a
    // "reconnect sooner" optimisation, the socket's own backoff still works.
    try {
      _listenToConnectivity();
    } catch (e) {
      debugPrint('SocketService: connectivity monitoring unavailable: $e');
    }
  }

  static void _listenToConnectivity() {
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
    _isAuthenticated = false;
    _authenticatedUserId = null;
    _supportsDartAck = false;
    _supportsChat = false;
    _supportsRtcV2 = false;
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

  /// Test seam for the per-attempt auth payload ([_authPayload]): must always
  /// complete and hand the callback a `{'token': …}` map, even with storage
  /// unavailable — a throwing payload would silently drop the CONNECT packet.
  @visibleForTesting
  static Future<void> debugAuthPayload(void Function(dynamic) cb) =>
      _authPayload(cb);

  /// Test seam for the local expiry check backing [_authPayload].
  @visibleForTesting
  static bool debugTokenLooksExpired(String token) => _tokenLooksExpired(token);

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
    _isAuthenticated = false;
    _authenticatedUserId = null;
    _sessionUserId = null;
    _lastIdentityRebuild = null;
    _supportsDartAck = false;
    _supportsChat = false;
    _supportsRtcV2 = false;
    _handlers.clear();
    _handlerOwners.clear();
    _disconnectListeners.clear();
    _reconnectListeners.clear();
    _connectFailedListeners.clear();
    _sessionChangeListeners.clear();
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

  /// Register [handler] for [event], replacing any previous one.
  ///
  /// Pass [owner] (typically `this`) so [off] can tell your handler apart from
  /// another consumer's — see [_handlerOwners].
  static void on(String event, Function(dynamic) handler, {Object? owner}) {
    // Remove any previously registered handler for this event before adding the new one
    final existing = _handlers[event];
    if (existing != null && _socket != null) {
      _socket!.off(event, existing);
    }
    _handlers[event] = handler;
    if (owner != null) {
      _handlerOwners[event] = owner;
    } else {
      _handlerOwners.remove(event);
    }
    // Socket may be mid-rebuild (token refresh); connect() attaches every
    // tracked handler to the new instance, so storing it is enough.
    _socket?.on(event, handler);
  }

  /// Remove the handler for [event]. With [owner] set, this is a no-op unless
  /// the live handler was registered by that same owner — so a provider
  /// tearing down its listeners can never unhook the provider that displaced
  /// it and is currently driving a live match.
  static void off(String event, {Object? owner}) {
    if (owner != null && !identical(_handlerOwners[event], owner)) return;
    _handlerOwners.remove(event);
    final handler = _handlers.remove(event);
    if (_socket == null) return;
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

  /// Like [ensureConnected], but additionally waits for the server's
  /// `authenticated` handshake. The handshake lands a round-trip AFTER the
  /// transport connects (the server verifies the JWT and does DB work first),
  /// so any code that snapshots a capability flag — like the BO3 opt-in in the
  /// matchmaking join body — must wait on this, not just on [ensureConnected]:
  /// in the gap the flags still hold their reset-on-disconnect false and the
  /// caller silently takes the no-capability path.
  ///
  /// Unlike the connection wait, the handshake wait does NOT throw on timeout:
  /// it returns with the flags still false so callers degrade (BO1, no dart
  /// acks) instead of being blocked by a server that never announces
  /// capabilities.
  static Future<void> ensureAuthenticated({
    Duration timeout = const Duration(seconds: 10),
    Duration authTimeout = const Duration(seconds: 5),
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    await ensureConnected(timeout: timeout, pollInterval: pollInterval);
    final deadline = DateTime.now().add(authTimeout);
    // Wait for the handshake AND for it to name the logged-in user: a socket
    // left over from a previous account answers `authenticated` immediately,
    // so keying only off _isAuthenticated declared success on a socket that
    // receives none of this user's events. isConnected is deliberately not a
    // loop condition — the identity rebuild bounces the connection.
    bool settled() => _sessionUserId == null ? _isAuthenticated : belongsToSession;
    while (!settled() && DateTime.now().isBefore(deadline)) {
      await Future.delayed(pollInterval);
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

  /// Notified when the socket stops belonging to the previous user (account
  /// switch or logout). Providers holding a matchId + myUserId must drop them:
  /// a stale tournament provider kept firing reconnect_to_match for the old
  /// account's match on the new account's socket.
  static void addSessionChangeListener(Function() listener) {
    if (!_sessionChangeListeners.contains(listener)) {
      _sessionChangeListeners.add(listener);
    }
  }

  static void removeSessionChangeListener(Function() listener) {
    _sessionChangeListeners.remove(listener);
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

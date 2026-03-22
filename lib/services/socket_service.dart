import 'dart:async';

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

  // Registered handlers keyed by event name — enables targeted removal
  static final Map<String, Function(dynamic)> _handlers = {};

  static bool get isConnected => _socket?.connected ?? false;
  static String? get socketId => _socket?.id;

  static Future<void> connect() async {
    if (_connectCompleter != null) {
      return _connectCompleter!.future;
    }
    if (isConnected) return;

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
            .enableReconnection()
            .setReconnectionAttempts(20)
            .setReconnectionDelay(2000)
            .setReconnectionDelayMax(10000)
            .setAuth({'token': token})
            .build(),
      );

      _socket!.onConnect((_) {
        debugPrint('SocketService: Connected! socketId=${_socket?.id}');
      });

      _socket!.onDisconnect((reason) {
        debugPrint('SocketService: Disconnected - reason: $reason');
        _onDisconnectHandler?.call();
      });

      _socket!.on('reconnect', (_) {
        debugPrint('SocketService: Reconnected');
        _onReconnectHandler?.call();
      });

      _socket!.on('reconnect_failed', (_) {
        debugPrint('SocketService: Reconnection failed permanently');
        _onConnectFailedHandler?.call();
      });

      _socket!.onConnectError((error) async {
        debugPrint('SocketService: Connect error - $error');
        if (error.toString().contains('401') ||
            error.toString().contains('unauthorized') ||
            error.toString().contains('jwt')) {
          debugPrint('SocketService: Auth error, attempting token refresh...');
          final refreshed = await ApiService.refreshAccessToken();
          if (refreshed) {
            debugPrint('SocketService: Token refreshed, reconnecting...');
            _disconnectInternal();
            _connectCompleter = null;
            await connect();
          }
        }
      });

      _socket!.onError((error) {
        debugPrint('SocketService: Error - $error');
      });

      _socket!.connect();
    } catch (e) {
      rethrow;
    } finally {
      _connectCompleter?.complete();
      _connectCompleter = null;
    }
  }

  static void _disconnectInternal() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _handlers.clear();
    }
  }

  static Future<void> disconnect() async {
    if (_connectCompleter != null) {
      await _connectCompleter!.future;
    }
    _disconnectInternal();
  }

  static void emit(String event, dynamic data) {
    if (!isConnected) {
      throw Exception('Socket not connected');
    }
    _socket!.emit(event, data);
  }

  static void on(String event, Function(dynamic) handler) {
    if (_socket == null) throw Exception('Socket not initialized');
    // Remove any previously registered handler for this event before adding the new one
    final existing = _handlers[event];
    if (existing != null) {
      _socket!.off(event, existing);
    }
    _handlers[event] = handler;
    _socket!.on(event, handler);
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
}

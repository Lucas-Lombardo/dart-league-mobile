import 'package:socket_io_client/socket_io_client.dart' as io;
import '../utils/api_config.dart';
import '../utils/storage_service.dart';
import 'api_service.dart';

class SocketService {
  static io.Socket? _socket;
  static bool _isConnecting = false;
  static Function()? _onReconnectHandler;
  static Function()? _onDisconnectHandler;
  static Function()? _onConnectFailedHandler;

  // Registered handlers keyed by event name — enables targeted removal
  static final Map<String, Function(dynamic)> _handlers = {};

  static bool get isConnected => _socket?.connected ?? false;
  static String? get socketId => _socket?.id;

  static Future<void> connect() async {
    if (_isConnecting || isConnected) return;

    _isConnecting = true;

    try {
      final token = await StorageService.getToken();
      
      if (token == null) {
        throw Exception('No authentication token found');
      }

      // baseUrl is already the full URL (https://api.dart-rivals.com)
      // No need to modify it - socket.io connects to the same host
      final socketUrl = baseUrl;
      print('🔌 SocketService: Connecting to $socketUrl');

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
        print('✅ SocketService: Connected! socketId=${_socket?.id}');
      });

      _socket!.onDisconnect((reason) {
        print('❌ SocketService: Disconnected - reason: $reason');
        _onDisconnectHandler?.call();
      });

      _socket!.on('reconnect', (_) {
        print('🔄 SocketService: Reconnected');
        _onReconnectHandler?.call();
      });

      _socket!.on('reconnect_failed', (_) {
        print('❌ SocketService: Reconnection failed permanently');
        _onConnectFailedHandler?.call();
      });

      _socket!.onConnectError((error) async {
        print('❌ SocketService: Connect error - $error');
        // If auth-related, try refreshing the token and reconnecting
        if (error.toString().contains('401') ||
            error.toString().contains('unauthorized') ||
            error.toString().contains('jwt')) {
          print('🔄 SocketService: Auth error, attempting token refresh...');
          final refreshed = await ApiService.refreshAccessToken();
          if (refreshed) {
            print('🔄 SocketService: Token refreshed, reconnecting...');
            disconnect();
            await connect();
          }
        }
      });

      _socket!.onError((error) {
        print('❌ SocketService: Error - $error');
      });

      _socket!.connect();
    } catch (e) {
      rethrow;
    } finally {
      _isConnecting = false;
    }
  }

  static void disconnect() {
    if (_socket != null) {
      _socket!.disconnect();
      _socket!.dispose();
      _socket = null;
      _handlers.clear();
    }
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
    } else {
      _socket!.off(event);
    }
  }

  static Future<void> ensureConnected() async {
    if (!isConnected) {
      await connect();
      await Future.delayed(const Duration(milliseconds: 500));
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

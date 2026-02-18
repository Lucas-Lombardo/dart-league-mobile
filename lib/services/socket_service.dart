import 'package:socket_io_client/socket_io_client.dart' as io;
import '../utils/api_config.dart';
import '../utils/storage_service.dart';

class SocketService {
  static io.Socket? _socket;
  static bool _isConnecting = false;
  static Function()? _onReconnectHandler;

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
            .setReconnectionAttempts(5)
            .setReconnectionDelay(1000)
            .setAuth({'token': token})
            .build(),
      );

      _socket!.onConnect((_) {
        print('✅ SocketService: Connected! socketId=${_socket?.id}');
      });

      _socket!.onDisconnect((reason) {
        print('❌ SocketService: Disconnected - reason: $reason');
      });

      _socket!.on('reconnect', (_) {
        print('🔄 SocketService: Reconnected');
        // Trigger reconnection handler if registered
        _onReconnectHandler?.call();
      });

      _socket!.onConnectError((error) {
        print('❌ SocketService: Connect error - $error');
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
    }
  }

  static void emit(String event, dynamic data) {
    if (!isConnected) {
      throw Exception('Socket not connected');
    }
    _socket!.emit(event, data);
  }

  static void on(String event, Function(dynamic) handler) {
    if (_socket == null) {
      throw Exception('Socket not initialized');
    }
    _socket!.on(event, handler);
  }

  static void off(String event) {
    if (_socket == null) return;
    _socket!.off(event);
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
}

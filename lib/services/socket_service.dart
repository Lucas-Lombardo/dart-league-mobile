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

      final socketUrl = baseUrl.replaceAll('/api', '');

      _socket = io.io(
        socketUrl,
        io.OptionBuilder()
            .setTransports(['websocket'])
            .enableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(5)
            .setReconnectionDelay(1000)
            .setAuth({'token': token})
            .build(),
      );

      _socket!.onConnect((_) {
      });

      _socket!.onDisconnect((_) {
      });

      _socket!.on('reconnect', (_) {
        // Trigger reconnection handler if registered
        _onReconnectHandler?.call();
      });

      _socket!.onConnectError((error) {
      });

      _socket!.onError((error) {
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

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../utils/api_config.dart';
import '../utils/storage_service.dart';

class SocketService {
  static io.Socket? _socket;
  static bool _isConnecting = false;

  static bool get isConnected => _socket?.connected ?? false;

  static Future<void> connect() async {
    if (_isConnecting || isConnected) return;

    _isConnecting = true;

    try {
      final token = await StorageService.getToken();
      
      if (token == null) {
        throw Exception('No authentication token found');
      }

      final socketUrl = baseUrl.replaceAll('/api', '');
      debugPrint('🔌 Connecting to socket: $socketUrl');

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
        debugPrint('✅ Socket connected to $socketUrl');
      });

      _socket!.onDisconnect((_) {
        debugPrint('❌ Socket disconnected');
      });

      _socket!.onConnectError((error) {
        debugPrint('⚠️ Socket connection error: $error');
      });

      _socket!.onError((error) {
        debugPrint('⚠️ Socket error: $error');
      });

      _socket!.connect();
    } catch (e) {
      debugPrint('Failed to connect socket: $e');
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
      debugPrint('❌ Cannot emit $event - Socket not connected');
      throw Exception('Socket not connected');
    }
    debugPrint('📤 Emitting event: $event with data: $data');
    _socket!.emit(event, data);
  }

  static void on(String event, Function(dynamic) handler) {
    if (_socket == null) {
      throw Exception('Socket not initialized');
    }
    debugPrint('👂 Listening to event: $event');
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
}

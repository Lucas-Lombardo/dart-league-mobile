import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🔔 Background message: ${message.notification?.title}');
}

class PushNotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static String? _fcmToken;
  static bool _initialized = false;
  static StreamSubscription<RemoteMessage>? _onMessageSub;
  static StreamSubscription<RemoteMessage>? _onMessageOpenedAppSub;
  static StreamSubscription<String>? _onTokenRefreshSub;

  static String? get fcmToken => _fcmToken;

  static Future<void> initialize() async {
    if (_initialized) return;
    if (kIsWeb) {
      debugPrint('⚠️ Push notifications not supported on web');
      return;
    }

    try {
      // Request permission (required for iOS, no-op on Android)
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('🔔 Notification permission: ${settings.authorizationStatus}');

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('⚠️ User denied notification permissions');
        return;
      }

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Handle foreground messages
      _onMessageSub?.cancel();
      _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('🔔 Foreground message: ${message.notification?.title} - ${message.notification?.body}');
      });

      // Handle notification tap when app is in background
      _onMessageOpenedAppSub?.cancel();
      _onMessageOpenedAppSub = FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('🔔 Notification tapped: ${message.data}');
      });

      // Get the FCM token
      _fcmToken = await _messaging.getToken();
      debugPrint('🔔 FCM Token: $_fcmToken');

      // Listen for token refresh
      _onTokenRefreshSub?.cancel();
      _onTokenRefreshSub = _messaging.onTokenRefresh.listen((newToken) {
        debugPrint('🔔 FCM Token refreshed');
        _fcmToken = newToken;
        _registerTokenWithBackend(newToken);
      });

      // Set foreground notification presentation options (iOS)
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      _initialized = true;
      debugPrint('🔔 Push notification service initialized');
    } catch (e) {
      debugPrint('❌ Failed to initialize push notifications: $e');
    }
  }

  static Future<void> registerToken() async {
    if (_fcmToken == null) {
      debugPrint('⚠️ No FCM token available');
      return;
    }

    await _registerTokenWithBackend(_fcmToken!);
  }

  static Future<void> _registerTokenWithBackend(String token) async {
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      await ApiService.post('/notifications/register-token', {
        'token': token,
        'platform': platform,
      });
      debugPrint('🔔 FCM token registered with backend');
    } catch (e) {
      debugPrint('❌ Failed to register FCM token: $e');
    }
  }

  static void dispose() {
    _onMessageSub?.cancel();
    _onMessageSub = null;
    _onMessageOpenedAppSub?.cancel();
    _onMessageOpenedAppSub = null;
    _onTokenRefreshSub?.cancel();
    _onTokenRefreshSub = null;
    _initialized = false;
  }

  static Future<void> unregisterToken() async {
    if (_fcmToken == null) return;

    try {
      await ApiService.post('/notifications/unregister-token', {
        'token': _fcmToken,
      });
      debugPrint('🔔 FCM token unregistered from backend');
    } catch (e) {
      debugPrint('❌ Failed to unregister FCM token: $e');
    }
  }
}

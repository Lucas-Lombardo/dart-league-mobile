import 'package:flutter/foundation.dart' show debugPrint;
import '../models/user.dart';
import '../utils/storage_service.dart';
import 'api_service.dart';

class AuthService {
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String language,
  }) async {
    try {
      final response = await ApiService.post(
        '/auth/register',
        {
          'username': username,
          'email': email,
          'password': password,
          'language': language,
        },
        includeAuth: false,
      );

      if (response['access_token'] != null) {
        await StorageService.saveToken(response['access_token']);
      }
      if (response['refresh_token'] != null) {
        await StorageService.saveRefreshToken(response['refresh_token']);
      }

      return {
        'user': User.fromJson(response['user']),
        'token': response['access_token'],
      };
    } catch (e) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await ApiService.post(
        '/auth/login',
        {
          'email': email,
          'password': password,
        },
        includeAuth: false,
      );

      if (response['access_token'] != null) {
        await StorageService.saveToken(response['access_token']);
      }
      if (response['refresh_token'] != null) {
        await StorageService.saveRefreshToken(response['refresh_token']);
      }

      return {
        'user': User.fromJson(response['user']),
        'token': response['access_token'],
      };
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> logout() async {
    try {
      // Call backend to invalidate the refresh token server-side
      try {
        await ApiService.post('/auth/logout', {});
      } catch (e) {
        debugPrint('⚠️ Backend logout failed (token may already be invalid): $e');
      }
      await StorageService.deleteToken();
      await StorageService.deleteRefreshToken();
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> deleteAccount() async {
    try {
      debugPrint('🗑️ Attempting to delete account...');
      await ApiService.delete('/auth/account');
      debugPrint('✅ Account deleted from backend');
      await StorageService.deleteToken();
      await StorageService.deleteRefreshToken();
      debugPrint('✅ Tokens cleared from storage');
    } catch (e) {
      debugPrint('❌ Error deleting account: $e');
      rethrow;
    }
  }

  static Future<void> forgotPassword({required String email}) async {
    try {
      await ApiService.post(
        '/auth/forgot-password',
        {'email': email},
        includeAuth: false,
      );
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> resendVerification() async {
    try {
      await ApiService.post('/auth/resend-verification', {});
    } catch (e) {
      rethrow;
    }
  }

  static Future<User?> getCurrentUser() async {
    try {
      debugPrint('🔍 Fetching current user profile...');
      final token = await StorageService.getToken();
      if (token == null) {
        debugPrint('⚠️ No token in storage, user not authenticated');
        return null;
      }

      try {
        final response = await ApiService.get('/auth/profile');
        debugPrint('✅ User profile fetched successfully');
        return User.fromJson(response);
      } catch (profileError) {
        debugPrint('⚠️ Could not fetch profile, endpoint may not exist');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error fetching user profile: $e');

      if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
        debugPrint('🗑️ Token invalid, deleting...');
        await StorageService.deleteToken();
        await StorageService.deleteRefreshToken();
      } else {
        debugPrint('⚠️ Network or parsing error, keeping token');
      }

      return null;
    }
  }
}

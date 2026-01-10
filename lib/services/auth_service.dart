import '../models/user.dart';
import '../utils/storage_service.dart';
import 'api_service.dart';

class AuthService {
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      final response = await ApiService.post(
        '/auth/register',
        {
          'username': username,
          'email': email,
          'password': password,
        },
        includeAuth: false,
      );

      if (response['access_token'] != null) {
        await StorageService.saveToken(response['access_token']);
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
      await StorageService.deleteToken();
    } catch (e) {
      rethrow;
    }
  }

  static Future<User?> getCurrentUser() async {
    try {
      final token = await StorageService.getToken();
      if (token == null) {
        return null;
      }

      final response = await ApiService.get('/auth/me');
      return User.fromJson(response['user']);
    } catch (e) {
      await StorageService.deleteToken();
      return null;
    }
  }
}

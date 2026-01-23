import '../models/user.dart';
import 'api_service.dart';

class FriendsService {
  static Future<List<User>> getFriends() async {
    try {
      final response = await ApiService.get('/friends');
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => User.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<User>> getFriendsLeaderboard() async {
    try {
      final response = await ApiService.get('/friends/leaderboard');
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => User.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<User>> searchUsers(String query) async {
    try {
      if (query.trim().isEmpty) {
        return [];
      }
      final response = await ApiService.get('/friends/search?q=${Uri.encodeComponent(query)}');
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => User.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> addFriend(String friendId) async {
    try {
      await ApiService.post('/friends', {'friendId': friendId});
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> removeFriend(String friendId) async {
    try {
      await ApiService.delete('/friends/$friendId');
    } catch (e) {
      rethrow;
    }
  }

  static Future<bool> checkFriendship(String friendId) async {
    try {
      final response = await ApiService.get('/friends/check/$friendId');
      return response['isFriend'] as bool? ?? false;
    } catch (e) {
      return false;
    }
  }
}

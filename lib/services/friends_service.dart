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

  static Future<void> sendFriendRequest(String friendId) async {
    try {
      await ApiService.post('/friends', {'friendId': friendId});
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> acceptFriendRequest(String friendshipId) async {
    try {
      await ApiService.post('/friends/accept/$friendshipId', {});
    } catch (e) {
      rethrow;
    }
  }

  static Future<void> rejectFriendRequest(String friendshipId) async {
    try {
      await ApiService.post('/friends/reject/$friendshipId', {});
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<FriendRequest>> getPendingRequests() async {
    try {
      final response = await ApiService.get('/friends/requests/pending');
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => FriendRequest.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  static Future<List<FriendRequest>> getSentRequests() async {
    try {
      final response = await ApiService.get('/friends/requests/sent');
      final List<dynamic> data = response as List<dynamic>;
      return data.map((json) => FriendRequest.fromJson(json)).toList();
    } catch (e) {
      rethrow;
    }
  }

  static Future<int> getPendingRequestsCount() async {
    try {
      final response = await ApiService.get('/friends/requests/count');
      return response['count'] as int? ?? 0;
    } catch (e) {
      return 0;
    }
  }

  static Future<void> removeFriend(String friendId) async {
    try {
      await ApiService.delete('/friends/$friendId');
    } catch (e) {
      rethrow;
    }
  }

  static Future<String> getFriendshipStatus(String friendId) async {
    try {
      final response = await ApiService.get('/friends/status/$friendId');
      return response['status'] as String? ?? 'none';
    } catch (e) {
      return 'none';
    }
  }
}

class FriendRequest {
  final String id;
  final User user;
  final DateTime createdAt;

  FriendRequest({
    required this.id,
    required this.user,
    required this.createdAt,
  });

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      id: json['id'] as String,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

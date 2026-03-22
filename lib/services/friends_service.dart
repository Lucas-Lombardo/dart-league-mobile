import '../models/user.dart';
import 'api_service.dart';

DateTime? _tryParseDateTime(String? value) {
  if (value == null) return null;
  try {
    return DateTime.parse(value);
  } on FormatException {
    return null;
  }
}

class FriendsService {
  static Future<List<User>> getFriends() async {
    final response = await ApiService.get('/friends');
    if (response is! List<dynamic>) return [];
    return response.whereType<Map<String, dynamic>>().map((json) => User.fromJson(json)).toList();
  }

  static Future<List<User>> getFriendsLeaderboard() async {
    final response = await ApiService.get('/friends/leaderboard');
    if (response is! List<dynamic>) return [];
    return response.whereType<Map<String, dynamic>>().map((json) => User.fromJson(json)).toList();
  }

  static Future<List<User>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final response = await ApiService.get('/friends/search?q=${Uri.encodeComponent(query)}');
    if (response is! List<dynamic>) return [];
    return response.whereType<Map<String, dynamic>>().map((json) => User.fromJson(json)).toList();
  }

  static Future<void> sendFriendRequest(String friendId) async {
    await ApiService.post('/friends', {'friendId': friendId});
  }

  static Future<void> acceptFriendRequest(String friendshipId) async {
    await ApiService.post('/friends/accept/$friendshipId', {});
  }

  static Future<void> rejectFriendRequest(String friendshipId) async {
    await ApiService.post('/friends/reject/$friendshipId', {});
  }

  static Future<List<FriendRequest>> getPendingRequests() async {
    final response = await ApiService.get('/friends/requests/pending');
    if (response is! List<dynamic>) return [];
    return response.whereType<Map<String, dynamic>>().map((json) => FriendRequest.fromJson(json)).toList();
  }

  static Future<List<FriendRequest>> getSentRequests() async {
    final response = await ApiService.get('/friends/requests/sent');
    if (response is! List<dynamic>) return [];
    return response.whereType<Map<String, dynamic>>().map((json) => FriendRequest.fromJson(json)).toList();
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
    await ApiService.delete('/friends/$friendId');
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
      id: json['id'] as String? ?? '',
      user: User.fromJson(json['user'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      createdAt: _tryParseDateTime(json['createdAt'] as String?) ?? DateTime.now(),
    );
  }
}

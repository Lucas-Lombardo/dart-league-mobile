import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/friends_service.dart';

class FriendsProvider with ChangeNotifier {
  List<User> _friends = [];
  bool _isLoading = false;
  String? _error;

  List<User> get friends => _friends;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadFriends() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _friends = await FriendsService.getFriends();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addFriend(String friendId) async {
    try {
      await FriendsService.addFriend(friendId);
      await loadFriends();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> removeFriend(String friendId) async {
    try {
      await FriendsService.removeFriend(friendId);
      await loadFriends();
    } catch (e) {
      rethrow;
    }
  }

  bool isFriend(String userId) {
    return _friends.any((friend) => friend.id == userId);
  }
}

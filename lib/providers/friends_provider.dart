import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/friends_service.dart';

class FriendsProvider with ChangeNotifier {
  List<User> _friends = [];
  List<FriendRequest> _pendingRequests = [];
  List<FriendRequest> _sentRequests = [];
  int _pendingRequestsCount = 0;
  bool _isLoading = false;
  String? _error;

  List<User> get friends => _friends;
  List<FriendRequest> get pendingRequests => _pendingRequests;
  List<FriendRequest> get sentRequests => _sentRequests;
  int get pendingRequestsCount => _pendingRequestsCount;
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

  Future<void> sendFriendRequest(String friendId) async {
    try {
      await FriendsService.sendFriendRequest(friendId);
      await loadSentRequests();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> acceptFriendRequest(String friendshipId) async {
    try {
      await FriendsService.acceptFriendRequest(friendshipId);
      await loadFriends();
      await loadPendingRequests();
      await loadPendingRequestsCount();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> rejectFriendRequest(String friendshipId) async {
    try {
      await FriendsService.rejectFriendRequest(friendshipId);
      await loadPendingRequests();
      await loadPendingRequestsCount();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> loadPendingRequests() async {
    try {
      _pendingRequests = await FriendsService.getPendingRequests();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadSentRequests() async {
    try {
      _sentRequests = await FriendsService.getSentRequests();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadPendingRequestsCount() async {
    try {
      _pendingRequestsCount = await FriendsService.getPendingRequestsCount();
      notifyListeners();
    } catch (e) {
      _pendingRequestsCount = 0;
      notifyListeners();
    }
  }

  Future<void> loadAll() async {
    await Future.wait([
      loadFriends(),
      loadPendingRequests(),
      loadSentRequests(),
      loadPendingRequestsCount(),
    ]);
  }

  Future<void> removeFriend(String friendId) async {
    try {
      await FriendsService.removeFriend(friendId);
      await loadFriends();
    } catch (e) {
      rethrow;
    }
  }

  String getFriendshipStatus(String userId) {
    if (_friends.any((friend) => friend.id == userId)) {
      return 'friends';
    }
    if (_pendingRequests.any((req) => req.user.id == userId)) {
      return 'pending_received';
    }
    if (_sentRequests.any((req) => req.user.id == userId)) {
      return 'pending_sent';
    }
    return 'none';
  }

  bool isFriend(String userId) {
    return _friends.any((friend) => friend.id == userId);
  }
}

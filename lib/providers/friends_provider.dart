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
  Set<String> _onlineFriendIds = {};

  List<User> get friends => _friends;
  List<FriendRequest> get pendingRequests => _pendingRequests;
  List<FriendRequest> get sentRequests => _sentRequests;
  int get pendingRequestsCount => _pendingRequestsCount;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Whether the given friend is currently online (presence-backed).
  bool isOnline(String userId) => _onlineFriendIds.contains(userId);

  /// Refreshes the set of online friends. Cheap; polled while the friends
  /// screen is visible. Only notifies listeners when the set actually changes.
  Future<void> refreshOnlineFriends() async {
    final ids = await FriendsService.getOnlineFriendIds();
    final changed =
        ids.length != _onlineFriendIds.length || !ids.containsAll(_onlineFriendIds);
    if (changed) {
      _onlineFriendIds = ids;
      notifyListeners();
    }
  }

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
      refreshOnlineFriends(),
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

  @override
  void dispose() {
    _friends = [];
    _pendingRequests = [];
    _sentRequests = [];
    _pendingRequestsCount = 0;
    _error = null;
    _onlineFriendIds = {};
    super.dispose();
  }
}

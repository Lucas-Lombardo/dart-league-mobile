import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../services/push_notification_service.dart';
import '../services/socket_service.dart';

/// Chat state: unread counters (AppBar badge + per-friend bubbles), the
/// conversation list, blocked users, and realtime delivery via the
/// `chat:message` socket event. Reading and writing go through ChatService.
class ChatProvider with ChangeNotifier {
  bool _initialized = false;

  int _unreadTotal = 0;
  int _unreadSupport = 0;
  Map<String, int> _unreadBySender = {};
  List<ChatConversation> _conversations = [];
  Set<String> _blockedIds = {};
  bool _isLoading = false;

  /// Counterpart id of the thread currently on screen — its incoming messages
  /// are forwarded to the thread (and auto-read) instead of counting unread.
  String? _activeThreadId;

  final List<void Function(ChatMessage message)> _threadListeners = [];

  int get unreadTotal => _unreadTotal;
  int get unreadSupport => _unreadSupport;
  List<ChatConversation> get conversations => _conversations;
  bool get isLoading => _isLoading;
  Set<String> get blockedIds => _blockedIds;

  int unreadFrom(String counterpartId) => counterpartId == kSupportConversationId
      ? _unreadSupport
      : (_unreadBySender[counterpartId] ?? 0);

  bool isBlocked(String userId) => _blockedIds.contains(userId);

  /// Idempotent. Called from the home screen once the user is logged in.
  void init() {
    if (_initialized) return;
    _initialized = true;
    SocketService.on('chat:message', _onSocketMessage, owner: this);
    SocketService.addSessionChangeListener(_onSessionChange);
    PushNotificationService.addOpenedListener(_onPushOpened);
    refreshUnread();
    loadBlocked();
  }

  // ------------------------------------------------------------------ loads

  Future<void> refreshUnread() async {
    final summary = await ChatService.getUnread();
    _unreadTotal = summary.total;
    _unreadSupport = summary.support;
    _unreadBySender = Map.of(summary.bySender);
    notifyListeners();
  }

  Future<void> loadConversations() async {
    _isLoading = true;
    notifyListeners();
    try {
      final conversations = await ChatService.getConversations();
      conversations.sort((a, b) => b.lastAt.compareTo(a.lastAt));
      _conversations = conversations;
    } catch (_) {
      // Keep the previous list; the screen shows what it has.
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadBlocked() async {
    _blockedIds = await ChatService.getBlockedUserIds();
    notifyListeners();
  }

  // ----------------------------------------------------------------- thread

  void setActiveThread(String counterpartId) {
    _activeThreadId = counterpartId;
  }

  void clearActiveThread(String counterpartId) {
    if (_activeThreadId == counterpartId) _activeThreadId = null;
  }

  void addThreadListener(void Function(ChatMessage message) listener) {
    if (!_threadListeners.contains(listener)) _threadListeners.add(listener);
  }

  void removeThreadListener(void Function(ChatMessage message) listener) {
    _threadListeners.remove(listener);
  }

  /// Mark a whole conversation read: server first, then the local counters so
  /// the AppBar badge and friend bubbles drop immediately.
  Future<void> markThreadRead(String counterpartId) async {
    try {
      await ChatService.markRead(counterpartId);
    } catch (_) {
      // The next refreshUnread() reconciles.
    }
    if (counterpartId == kSupportConversationId) {
      _unreadTotal -= _unreadSupport;
      _unreadSupport = 0;
    } else {
      _unreadTotal -= _unreadBySender.remove(counterpartId) ?? 0;
    }
    if (_unreadTotal < 0) _unreadTotal = 0;
    _conversations = _conversations
        .map((c) => c.conversationId == counterpartId
            ? ChatConversation(
                conversationId: c.conversationId,
                isSupport: c.isSupport,
                username: c.username,
                lastContent: c.lastContent,
                lastSenderId: c.lastSenderId,
                lastAt: c.lastAt,
                unreadCount: 0,
              )
            : c)
        .toList();
    notifyListeners();
  }

  Future<ChatMessage> sendMessage(String counterpartId, String content) async {
    final message = await ChatService.sendMessage(counterpartId, content);
    // Refresh the conversation list lazily next time it's opened.
    return message;
  }

  // ------------------------------------------------------------- moderation

  Future<void> blockUser(String userId) async {
    await ChatService.blockUser(userId);
    _blockedIds = {..._blockedIds, userId};
    notifyListeners();
  }

  Future<void> unblockUser(String userId) async {
    await ChatService.unblockUser(userId);
    _blockedIds = {..._blockedIds}..remove(userId);
    notifyListeners();
  }

  Future<void> reportConversation(String reportedUserId, {String? comment}) {
    return ChatService.reportConversation(reportedUserId, comment: comment);
  }

  // ---------------------------------------------------------------- routing

  void _onSocketMessage(dynamic data) {
    if (data is! Map) return;
    final message = ChatMessage.fromJson(Map<String, dynamic>.from(data));
    if (message.id.isEmpty) return;

    if (_activeThreadId == message.senderId) {
      // The thread is on screen: deliver there and mark read server-side.
      for (final listener in List.of(_threadListeners)) {
        listener(message);
      }
      ChatService.markRead(message.senderId).catchError((_) {});
      return;
    }

    _unreadTotal += 1;
    if (message.senderId == kSupportConversationId) {
      _unreadSupport += 1;
    } else {
      _unreadBySender[message.senderId] =
          (_unreadBySender[message.senderId] ?? 0) + 1;
    }
    notifyListeners();
  }

  void _onPushOpened(Map<String, dynamic> data) {
    if (data['type'] != 'chat_message') return;
    // Navigation is handled by whoever owns the navigator; we just make sure
    // the badge is fresh when the app comes to the foreground from the push.
    refreshUnread();
    final handler = onOpenThreadFromPush;
    if (handler != null) {
      final senderId = data['senderId'] as String? ?? '';
      if (senderId.isNotEmpty) {
        handler(senderId, data['senderUsername'] as String?);
      }
    }
  }

  /// Set by the home screen: navigates to the thread when the user taps a
  /// "new message" push (senderId is 'support' for team replies).
  void Function(String counterpartId, String? username)? onOpenThreadFromPush;

  void _onSessionChange() {
    _unreadTotal = 0;
    _unreadSupport = 0;
    _unreadBySender = {};
    _conversations = [];
    _blockedIds = {};
    _activeThreadId = null;
    notifyListeners();
    refreshUnread();
    loadBlocked();
  }

  @override
  void dispose() {
    SocketService.off('chat:message', owner: this);
    SocketService.removeSessionChangeListener(_onSessionChange);
    PushNotificationService.removeOpenedListener(_onPushOpened);
    _threadListeners.clear();
    super.dispose();
  }
}

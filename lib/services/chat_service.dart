import '../models/chat_message.dart';
import 'api_service.dart';

/// REST client of the /chat backend. Sending goes through REST (authoritative
/// even with a flaky socket); realtime receive is the `chat:message` socket
/// event handled by ChatProvider.
class ChatService {
  static Future<List<ChatConversation>> getConversations() async {
    final response = await ApiService.get('/chat/conversations');
    if (response is! List<dynamic>) return [];
    return response
        .whereType<Map<String, dynamic>>()
        .map(ChatConversation.fromJson)
        .toList();
  }

  /// Newest-first page of one conversation. Pass [before] to page backwards.
  static Future<List<ChatMessage>> getMessages(
    String counterpartId, {
    int limit = 50,
    DateTime? before,
  }) async {
    final query = StringBuffer('limit=$limit');
    if (before != null) {
      query.write('&before=${Uri.encodeComponent(before.toUtc().toIso8601String())}');
    }
    final response = await ApiService.get('/chat/messages/$counterpartId?$query');
    if (response is! List<dynamic>) return [];
    return response
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList();
  }

  static Future<ChatMessage> sendMessage(String counterpartId, String content) async {
    final response = await ApiService.post(
      '/chat/messages/$counterpartId',
      {'content': content},
    );
    return ChatMessage.fromJson(response as Map<String, dynamic>? ?? {});
  }

  static Future<void> markRead(String counterpartId) async {
    await ApiService.post('/chat/read/$counterpartId', {});
  }

  static Future<ChatUnreadSummary> getUnread() async {
    try {
      final response = await ApiService.get('/chat/unread');
      if (response is! Map<String, dynamic>) return const ChatUnreadSummary();
      return ChatUnreadSummary.fromJson(response);
    } catch (_) {
      return const ChatUnreadSummary();
    }
  }

  static Future<Set<String>> getBlockedUserIds() async {
    try {
      final response = await ApiService.get('/chat/blocks');
      final ids = (response as Map<String, dynamic>?)?['blockedUserIds'];
      if (ids is! List) return <String>{};
      return ids.whereType<String>().toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> blockUser(String userId) async {
    await ApiService.post('/chat/block/$userId', {});
  }

  static Future<void> unblockUser(String userId) async {
    await ApiService.delete('/chat/block/$userId');
  }

  static Future<void> reportConversation(String reportedUserId, {String? comment}) async {
    await ApiService.post('/chat/report', {
      'reportedUserId': reportedUserId,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
    });
  }
}

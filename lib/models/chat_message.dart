/// Counterpart id of the virtual "Équipe Dart Rivals" conversation — mirrors
/// the backend's SUPPORT_CONVERSATION_ID.
const String kSupportConversationId = 'support';

DateTime _parseDate(dynamic value) {
  if (value is String) {
    try {
      return DateTime.parse(value).toLocal();
    } on FormatException {
      // fall through
    }
  }
  return DateTime.now();
}

class ChatMessage {
  final String id;
  final String senderId;
  final String content;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.createdAt,
  });

  bool get isFromSupport => senderId == kSupportConversationId;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: _parseDate(json['createdAt']),
    );
  }
}

class ChatConversation {
  /// Friend uuid, or [kSupportConversationId] for the team conversation.
  final String conversationId;
  final bool isSupport;
  final String username;
  final String lastContent;
  final String lastSenderId;
  final DateTime lastAt;
  final int unreadCount;

  ChatConversation({
    required this.conversationId,
    required this.isSupport,
    required this.username,
    required this.lastContent,
    required this.lastSenderId,
    required this.lastAt,
    required this.unreadCount,
  });

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    final last = json['lastMessage'] as Map<String, dynamic>? ?? const {};
    return ChatConversation(
      conversationId: json['conversationId'] as String? ?? '',
      isSupport: json['isSupport'] as bool? ?? false,
      username: json['username'] as String? ?? 'Unknown',
      lastContent: last['content'] as String? ?? '',
      lastSenderId: last['senderId'] as String? ?? '',
      lastAt: _parseDate(last['createdAt']),
      unreadCount: json['unreadCount'] as int? ?? 0,
    );
  }
}

class ChatUnreadSummary {
  final int total;
  final int support;
  final Map<String, int> bySender;

  const ChatUnreadSummary({
    this.total = 0,
    this.support = 0,
    this.bySender = const {},
  });

  factory ChatUnreadSummary.fromJson(Map<String, dynamic> json) {
    final raw = json['bySender'] as Map<String, dynamic>? ?? const {};
    return ChatUnreadSummary(
      total: json['total'] as int? ?? 0,
      support: json['support'] as int? ?? 0,
      bySender: raw.map((key, value) => MapEntry(key, value as int? ?? 0)),
    );
  }
}

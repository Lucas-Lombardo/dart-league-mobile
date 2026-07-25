import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chat_message.dart';
import '../../providers/chat_provider.dart';
import '../../providers/friends_provider.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import 'chat_thread_screen.dart';

/// The read-only inbox behind the AppBar 💬 icon: every conversation with
/// received messages, unread first. Tapping a row opens the thread. Writing a
/// NEW message goes through the Friends tab (💬 button on each friend row).
class ReceivedMessagesScreen extends StatefulWidget {
  const ReceivedMessagesScreen({super.key});

  @override
  State<ReceivedMessagesScreen> createState() => _ReceivedMessagesScreenState();
}

class _ReceivedMessagesScreenState extends State<ReceivedMessagesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ChatProvider>().loadConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chat = context.watch<ChatProvider>();
    final friends = context.watch<FriendsProvider>();
    final unread =
        chat.conversations.where((c) => c.unreadCount > 0).toList();
    final earlier =
        chat.conversations.where((c) => c.unreadCount == 0).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.receivedMessagesTitle)),
      body: RefreshIndicator(
        onRefresh: () => chat.loadConversations(),
        child: chat.isLoading && chat.conversations.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : chat.conversations.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      const Center(
                          child: Text('💬', style: TextStyle(fontSize: 40))),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          l10n.noReceivedMessages,
                          style: const TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _writeHint(l10n),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    children: [
                      if (unread.isNotEmpty) ...[
                        _sectionLabel('${l10n.unreadSection.toUpperCase()} — ${unread.length}'),
                        ...unread.map((c) => _ConversationRow(
                            conversation: c,
                            online: !c.isSupport &&
                                friends.isOnline(c.conversationId),
                            onTap: () => _openThread(c))),
                      ],
                      if (earlier.isNotEmpty) ...[
                        _sectionLabel(l10n.earlierSection.toUpperCase()),
                        ...earlier.map((c) => _ConversationRow(
                            conversation: c,
                            online: !c.isSupport &&
                                friends.isOnline(c.conversationId),
                            onTap: () => _openThread(c))),
                      ],
                      const SizedBox(height: 16),
                      _writeHint(l10n),
                    ],
                  ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _writeHint(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          l10n.writeViaFriendsHint,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ),
    );
  }

  void _openThread(ChatConversation conversation) {
    HapticService.lightImpact();
    AppNavigator.toScreen(
      context,
      ChatThreadScreen(
        counterpartId: conversation.conversationId,
        username: conversation.username,
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  final ChatConversation conversation;
  final bool online;
  final VoidCallback onTap;

  const _ConversationRow({
    required this.conversation,
    required this.online,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasUnread = conversation.unreadCount > 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: hasUnread
              ? AppTheme.primary.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: hasUnread
              ? Border.all(color: AppTheme.primary.withValues(alpha: 0.25))
              : const Border(
                  bottom: BorderSide(color: Color(0x66334155), width: 1)),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: conversation.isSupport
                        ? const LinearGradient(
                            colors: [AppTheme.primary, AppTheme.primaryDark])
                        : null,
                    color:
                        conversation.isSupport ? null : AppTheme.surfaceLight,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    conversation.isSupport
                        ? '🎯'
                        : (conversation.username.isEmpty
                            ? '?'
                            : conversation.username[0].toUpperCase()),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                if (online)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: AppTheme.success,
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppTheme.background, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          conversation.isSupport
                              ? l10n.teamDartRivals
                              : conversation.username,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (conversation.isSupport) ...[
                        const SizedBox(width: 6),
                        _teamBadge(l10n),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    conversation.lastContent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: hasUnread
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontWeight:
                          hasUnread ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _timeLabel(conversation.lastAt, l10n),
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 4),
                if (hasUnread)
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${conversation.unreadCount}',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  )
                else
                  const Icon(Icons.chevron_right,
                      size: 16, color: AppTheme.textSecondary),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamBadge(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.15),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        l10n.teamBadge,
        style: const TextStyle(
            fontSize: 8, fontWeight: FontWeight.w800, color: AppTheme.accent),
      ),
    );
  }

  String _timeLabel(DateTime at, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    if (day == today) {
      return '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    }
    if (day == today.subtract(const Duration(days: 1))) {
      return l10n.yesterdayLabel;
    }
    return '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
  }
}

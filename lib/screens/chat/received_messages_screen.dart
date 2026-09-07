import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chat_message.dart';
import '../../providers/chat_provider.dart';
import '../../providers/friends_provider.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';
import '../../widgets/loading_widget.dart';
import '../../widgets/premium_badge.dart';
import 'chat_thread_screen.dart';

/// The inbox behind the header's messages icon: every conversation with
/// received messages, unread first, as 64 px surface rows. Tapping a row
/// opens the thread. Writing a NEW message goes through the Friends tab
/// (the message button on each friend row).
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
    final unread = chat.conversations.where((c) => c.unreadCount > 0).toList();
    final earlier = chat.conversations.where((c) => c.unreadCount == 0).toList();

    final Widget body;
    if (chat.isLoading && chat.conversations.isEmpty) {
      body = const LoadingWidget();
    } else if (chat.conversations.isEmpty) {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 40, 16, 24),
        children: const [ConversationsEmpty()],
      );
    } else {
      body = ConversationList(
        unread: unread,
        earlier: earlier,
        isOnline: (c) => !c.isSupport && friends.isOnline(c.conversationId),
        isPremium: (c) => !c.isSupport &&
            (friends.friends
                    .where((f) => f.id == c.conversationId)
                    .firstOrNull
                    ?.isPremiumActive ??
                false),
        onOpen: _openThread,
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: DsScreenHeader(title: l10n.receivedMessagesTitle, showBack: true),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppTheme.primary,
                backgroundColor: AppTheme.surface,
                onRefresh: () => chat.loadConversations(),
                child: body,
              ),
            ),
          ],
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

/// The scrollable inbox: "NON LUS — 2" and "PLUS TÔT" groups of
/// [ConversationRow]s, 10 px apart, and the "write via Friends" hint.
/// Presentation only (the screen wires the providers) so it can be rendered
/// on its own.
class ConversationList extends StatelessWidget {
  final List<ChatConversation> unread;
  final List<ChatConversation> earlier;
  final bool Function(ChatConversation) isOnline;
  final bool Function(ChatConversation) isPremium;
  final ValueChanged<ChatConversation> onOpen;

  const ConversationList({
    super.key,
    required this.unread,
    required this.earlier,
    required this.isOnline,
    required this.isPremium,
    required this.onOpen,
  });

  List<Widget> _rows(List<ChatConversation> conversations) {
    final out = <Widget>[];
    for (var i = 0; i < conversations.length; i++) {
      if (i > 0) out.add(const SizedBox(height: 10));
      final c = conversations[i];
      out.add(ConversationRow(
        conversation: c,
        online: isOnline(c),
        premium: isPremium(c),
        onTap: () => onOpen(c),
      ));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        if (unread.isNotEmpty) ...[
          _SectionLabel('${l10n.unreadSection.toUpperCase()} — ${unread.length}'),
          const SizedBox(height: 10),
          ..._rows(unread),
        ],
        if (earlier.isNotEmpty) ...[
          if (unread.isNotEmpty) const SizedBox(height: 20),
          _SectionLabel(l10n.earlierSection.toUpperCase()),
          const SizedBox(height: 10),
          ..._rows(earlier),
        ],
        const SizedBox(height: 24),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.writeViaFriendsHint,
            textAlign: TextAlign.center,
            style: AppTheme.caption.copyWith(color: AppTheme.textTertiary),
          ),
        ),
      ],
    );
  }
}

/// Empty inbox: one card with the outlined bubble, the title and the hint.
class ConversationsEmpty extends StatelessWidget {
  const ConversationsEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DsCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(
            Icons.chat_bubble_outline_rounded,
            size: 32,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.noReceivedMessages,
            textAlign: TextAlign.center,
            style: AppTheme.rowTitle,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.writeViaFriendsHint,
            textAlign: TextAlign.center,
            style: AppTheme.caption,
          ),
        ],
      ),
    );
  }
}

/// "NON LUS — 2 ————————" group label with a hairline.
class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text, style: AppTheme.labelSmall),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1,
            color: AppTheme.surfaceLight.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

/// 64 px conversation row: 40 px initial disc (the team = primary disc with
/// the shield) with the presence dot, name + premium crown, the last message
/// on one line, the time on the right and the unread counter.
class ConversationRow extends StatelessWidget {
  final ChatConversation conversation;
  final bool online;
  final bool premium;
  final VoidCallback onTap;

  const ConversationRow({
    super.key,
    required this.conversation,
    required this.online,
    this.premium = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasUnread = conversation.unreadCount > 0;

    return SizedBox(
      height: 64,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
        onTap: onTap,
        child: Row(
          children: [
            ChatAvatar(
              isSupport: conversation.isSupport,
              username: conversation.username,
              online: online,
              size: 40,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          conversation.isSupport ? l10n.teamDartRivals : conversation.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.sectionTitle,
                        ),
                      ),
                      PremiumBadge(isPremium: premium, size: 12, color: AppTheme.accent),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    conversation.lastContent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(
                      color: hasUnread ? AppTheme.textPrimary : AppTheme.textSecondary,
                      fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _timeLabel(conversation.lastAt, l10n),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textTertiary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                if (hasUnread) ...[
                  const SizedBox(height: 4),
                  DsBadge(count: conversation.unreadCount),
                ],
              ],
            ),
          ],
        ),
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

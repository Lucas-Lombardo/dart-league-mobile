import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chat_message.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/friends_provider.dart';
import '../../services/chat_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_match_launcher.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';
import '../../widgets/loading_widget.dart';

/// One conversation — with a friend, or with the team when
/// [counterpartId] == [kSupportConversationId]. Flat app bar with the
/// counterpart, primary bubbles for mine / surface bubbles for theirs, the
/// time under each, and a themed composer with a round send button.
class ChatThreadScreen extends StatefulWidget {
  final String counterpartId;
  final String username;

  const ChatThreadScreen({
    super.key,
    required this.counterpartId,
    required this.username,
  });

  @override
  State<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends State<ChatThreadScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  late final ChatProvider _chat;
  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;

  bool get _isSupport => widget.counterpartId == kSupportConversationId;

  @override
  void initState() {
    super.initState();
    _chat = context.read<ChatProvider>();
    _chat.setActiveThread(widget.counterpartId);
    _chat.addThreadListener(_onIncoming);
    _chat.markThreadRead(widget.counterpartId);
    _load();
  }

  @override
  void dispose() {
    _chat.clearActiveThread(widget.counterpartId);
    _chat.removeThreadListener(_onIncoming);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final page = await ChatService.getMessages(widget.counterpartId);
      if (!mounted) return;
      setState(() {
        _messages = page.reversed.toList();
        _loading = false;
      });
      _jumpToBottom();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onIncoming(ChatMessage message) {
    final fromThisThread = _isSupport
        ? message.isFromSupport
        : message.senderId == widget.counterpartId;
    if (!fromThisThread || !mounted) return;
    setState(() => _messages = [..._messages, message]);
    _jumpToBottom();
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final content = _inputController.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final message =
          await context.read<ChatProvider>().sendMessage(widget.counterpartId, content);
      if (!mounted) return;
      _inputController.clear();
      setState(() => _messages = [..._messages, message]);
      _jumpToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).error)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final friends = context.watch<FriendsProvider>();
    final chat = context.watch<ChatProvider>();
    final myId = context.read<AuthProvider>().currentUser?.id ?? '';
    final online = !_isSupport && friends.isOnline(widget.counterpartId);
    final blocked = !_isSupport && chat.isBlocked(widget.counterpartId);
    final User? friend = _isSupport
        ? null
        : friends.friends.where((f) => f.id == widget.counterpartId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: ChatThreadTitle(
          isSupport: _isSupport,
          username: widget.username,
          online: online,
        ),
        actions: [
          if (friend != null)
            IconButton(
              icon: const Icon(Icons.sports_esports_outlined, size: 22),
              tooltip: l10n.challengeFriend,
              onPressed: () => FriendlyMatchLauncher.invite(context, friend),
            ),
          if (!_isSupport)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded, size: 22),
              color: AppTheme.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusControl),
                side: const BorderSide(color: AppTheme.border),
              ),
              onSelected: _onMenuAction,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'report',
                  child: _MenuRow(
                    icon: Icons.flag_outlined,
                    label: l10n.reportConversationAction,
                  ),
                ),
                PopupMenuItem(
                  value: blocked ? 'unblock' : 'block',
                  child: _MenuRow(
                    icon: blocked ? Icons.lock_open_rounded : Icons.block_rounded,
                    label: blocked
                        ? l10n.unblockAction
                        : '${l10n.blockAction} ${widget.username}',
                  ),
                ),
              ],
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const LoadingWidget()
                : ChatMessagesView(
                    messages: _messages,
                    myId: myId,
                    controller: _scrollController,
                    emptyText: _isSupport ? l10n.teamConversationSubtitle : l10n.chatEmpty,
                  ),
          ),
          SafeArea(
            top: false,
            child: blocked
                ? _buildBlockedBanner(l10n)
                : ChatComposer(
                    controller: _inputController,
                    sending: _sending,
                    onSend: () {
                      HapticService.lightImpact();
                      _send();
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedBanner(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        side: BorderSide(color: AppTheme.error.withValues(alpha: 0.4)),
        child: Row(
          children: [
            const Icon(Icons.block_rounded, size: 18, color: AppTheme.error),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.blockedBanner,
                style: AppTheme.caption.copyWith(fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: () =>
                  context.read<ChatProvider>().unblockUser(widget.counterpartId),
              child: Text(l10n.unblockAction),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onMenuAction(String action) async {
    final l10n = AppLocalizations.of(context);
    final chat = context.read<ChatProvider>();
    switch (action) {
      case 'report':
        final comment = await _askReportComment(l10n);
        if (comment == null) return; // cancelled
        try {
          await chat.reportConversation(widget.counterpartId,
              comment: comment.isEmpty ? null : comment);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.reportSentConfirmation)),
            );
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l10n.error)));
          }
        }
      case 'block':
        await chat.blockUser(widget.counterpartId);
      case 'unblock':
        await chat.unblockUser(widget.counterpartId);
    }
  }

  /// Returns null when cancelled, '' when confirmed without a comment.
  Future<String?> _askReportComment(AppLocalizations l10n) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.reportConversationAction),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.reportConversationSubtitle,
              style: AppTheme.caption.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLength: 500,
              maxLines: 3,
              minLines: 1,
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
              decoration: AppTheme.inputDecoration(
                label: l10n.reportCommentHint,
                prefixIcon: Icons.flag_outlined,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(
              l10n.reportConversationAction,
              style: const TextStyle(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// Popup menu entry: 18 px error icon + label (report, block).
class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppTheme.error),
        const SizedBox(width: 10),
        Text(
          label,
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.error),
        ),
      ],
    );
  }
}

/// App bar title of a thread: 36 px avatar, the name (17 / 700) and the
/// presence / reply-delay caption.
class ChatThreadTitle extends StatelessWidget {
  final bool isSupport;
  final String username;
  final bool online;

  const ChatThreadTitle({
    super.key,
    required this.isSupport,
    required this.username,
    required this.online,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final subtitle = isSupport ? l10n.teamReplyDelay : (online ? l10n.online : '');
    return Row(
      children: [
        ChatAvatar(isSupport: isSupport, username: username, online: online, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isSupport ? l10n.teamDartRivals : username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.titleLarge,
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(
                    color: online ? AppTheme.success : AppTheme.textSecondary,
                    fontWeight: online ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The scrolling thread: retention notice, empty text, spaced-label day
/// separators and [ChatBubble]s. Presentation only so it can be rendered on
/// its own.
class ChatMessagesView extends StatelessWidget {
  final List<ChatMessage> messages;
  final String myId;
  final ScrollController? controller;
  final String emptyText;

  const ChatMessagesView({
    super.key,
    required this.messages,
    required this.myId,
    this.controller,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.schedule_outlined, size: 12, color: AppTheme.textTertiary),
            const SizedBox(width: 6),
            Text(
              l10n.chatRetentionNotice,
              style: AppTheme.caption.copyWith(fontSize: 11, color: AppTheme.textTertiary),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (messages.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 0),
            child: Text(
              emptyText,
              textAlign: TextAlign.center,
              style: AppTheme.bodyMedium,
            ),
          ),
        ..._buildMessageWidgets(l10n),
      ],
    );
  }

  List<Widget> _buildMessageWidgets(AppLocalizations l10n) {
    final widgets = <Widget>[];
    DateTime? lastDay;
    for (final message in messages) {
      final day = DateTime(
          message.createdAt.year, message.createdAt.month, message.createdAt.day);
      if (lastDay == null || day != lastDay) {
        lastDay = day;
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(_dayLabel(day, l10n), style: AppTheme.labelSmall),
          ),
        ));
      }
      widgets.add(ChatBubble(
        content: message.content,
        time: _timeLabel(message.createdAt),
        isMine: message.senderId == myId,
      ));
    }
    return widgets;
  }

  String _dayLabel(DateTime day, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return l10n.todayLabel.toUpperCase();
    if (day == today.subtract(const Duration(days: 1))) {
      return l10n.yesterdayLabel.toUpperCase();
    }
    return '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
  }

  String _timeLabel(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
}

/// One message: mine = solid primary, white 14 / 500, 16 px corners with a
/// 4 px bottom-right; theirs = surface + hairline, text primary, 4 px
/// bottom-left. The time sits under the bubble as a tertiary caption.
class ChatBubble extends StatelessWidget {
  final String content;
  final String time;
  final bool isMine;

  const ChatBubble({
    super.key,
    required this.content,
    required this.time,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            decoration: BoxDecoration(
              color: isMine ? AppTheme.primary : AppTheme.surface,
              border: isMine ? null : Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
            ),
            child: Text(
              content,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.35,
                color: isMine ? Colors.white : AppTheme.textPrimary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 3, 4, 6),
            child: Text(
              time,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppTheme.textTertiary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The input bar: a themed field (surface, 14 px radius) and a 44 px round
/// primary send button.
class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const ChatComposer({
    super.key,
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLength: 1000,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.messageHint,
                counterText: '',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: AppTheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: sending ? null : onSend,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.arrow_upward_rounded, size: 22, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Round avatar of a counterpart: the team = primary gradient disc with the
/// shield; a player = surfaceLight disc with the initial. [online] draws the
/// presence dot on the bottom-right corner.
class ChatAvatar extends StatelessWidget {
  final bool isSupport;
  final String username;
  final bool online;
  final double size;

  const ChatAvatar({
    super.key,
    required this.isSupport,
    required this.username,
    required this.online,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isSupport ? AppTheme.primaryGradient : null,
              color: isSupport ? null : AppTheme.surfaceLight,
            ),
            alignment: Alignment.center,
            child: isSupport
                ? Image.asset(
                    'assets/logo/logo-without-letters.png',
                    width: size * 0.55,
                    height: size * 0.55,
                    fit: BoxFit.contain,
                  )
                : Text(
                    username.isEmpty ? '?' : username.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontSize: size * 0.4,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      height: 1,
                    ),
                  ),
          ),
          if (online)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppTheme.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

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

/// One conversation — with a friend, or with the team when
/// [counterpartId] == [kSupportConversationId].
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
        title: Row(
          children: [
            _Avatar(isSupport: _isSupport, username: widget.username, online: online),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isSupport ? l10n.teamDartRivals : widget.username,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _isSupport
                        ? l10n.teamReplyDelay
                        : (online ? l10n.online : ''),
                    style: TextStyle(
                      fontSize: 11,
                      color: online ? AppTheme.success : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (friend != null)
            IconButton(
              icon: const Text('⚔️', style: TextStyle(fontSize: 18)),
              tooltip: l10n.challengeFriend,
              onPressed: () => FriendlyMatchLauncher.invite(context, friend),
            ),
          if (!_isSupport)
            PopupMenuButton<String>(
              color: AppTheme.surface,
              onSelected: _onMenuAction,
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'report',
                  child: Text('🚩 ${l10n.reportConversationAction}',
                      style: const TextStyle(color: AppTheme.error)),
                ),
                PopupMenuItem(
                  value: blocked ? 'unblock' : 'block',
                  child: Text(
                    blocked
                        ? '🔓 ${l10n.unblockAction}'
                        : '🚫 ${l10n.blockAction} ${widget.username}',
                    style: const TextStyle(color: AppTheme.error),
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
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceLight.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '🕒 ${l10n.chatRetentionNotice}',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_messages.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Center(
                            child: Text(
                              _isSupport
                                  ? l10n.teamConversationSubtitle
                                  : l10n.chatEmpty,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppTheme.textSecondary),
                            ),
                          ),
                        ),
                      ..._buildMessageWidgets(myId, l10n),
                    ],
                  ),
          ),
          SafeArea(
            top: false,
            child: blocked ? _buildBlockedBanner(l10n) : _buildInputBar(l10n),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMessageWidgets(String myId, AppLocalizations l10n) {
    final widgets = <Widget>[];
    DateTime? lastDay;
    for (final message in _messages) {
      final day = DateTime(
          message.createdAt.year, message.createdAt.month, message.createdAt.day);
      if (lastDay == null || day != lastDay) {
        lastDay = day;
        widgets.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(
              _dayLabel(day, l10n),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ));
      }
      final isMine = message.senderId == myId;
      widgets.add(Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: isMine ? AppTheme.primary : AppTheme.surface,
            border: isMine
                ? null
                : Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isMine ? 16 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.content,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  color: isMine ? Colors.white : AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _timeLabel(message.createdAt),
                style: TextStyle(
                  fontSize: 9,
                  color: (isMine ? Colors.white : AppTheme.textSecondary)
                      .withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ));
    }
    return widgets;
  }

  Widget _buildInputBar(AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              maxLength: 1000,
              maxLines: 4,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: l10n.messageHint,
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                border: InputBorder.none,
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              HapticService.lightImpact();
              _send();
            },
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: AppTheme.primary,
                shape: BoxShape.circle,
              ),
              child: _sending
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send_rounded, size: 17, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedBanner(AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '🚫 ${l10n.blockedBanner}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () =>
                context.read<ChatProvider>().unblockUser(widget.counterpartId),
            child: Text(l10n.unblockAction),
          ),
        ],
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
        backgroundColor: AppTheme.surface,
        title: Text('🚩 ${l10n.reportConversationAction}',
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.reportConversationSubtitle,
                style:
                    const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 500,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(fontSize: 14),
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
            child: Text(l10n.reportConversationAction,
                style: const TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
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

class _Avatar extends StatelessWidget {
  final bool isSupport;
  final String username;
  final bool online;

  const _Avatar({
    required this.isSupport,
    required this.username,
    required this.online,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isSupport
                ? const LinearGradient(
                    colors: [AppTheme.primary, AppTheme.primaryDark])
                : null,
            color: isSupport ? null : AppTheme.surfaceLight,
          ),
          alignment: Alignment.center,
          child: Text(
            isSupport ? '🎯' : (username.isEmpty ? '?' : username[0].toUpperCase()),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
        if (online)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: AppTheme.success,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.background, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

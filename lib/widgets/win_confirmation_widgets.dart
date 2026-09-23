import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/win_confirmation.dart';
import '../utils/app_theme.dart';
import 'game_turn_ui.dart';
import 'design_system.dart';

/// The existing checkout frame, with variant B's microphone in its title.
class WinConfirmationDialog extends StatefulWidget {
  final Listenable game;
  final bool Function() pending;
  final WinConfirmation? Function() confirmation;
  final bool Function() muted;
  final Future<void> Function() toggleMic;
  final VoidCallback confirm;
  final VoidCallback edit;
  final String title;
  final Widget content;
  final Widget? replay;
  const WinConfirmationDialog({
    super.key,
    required this.game,
    required this.pending,
    required this.confirmation,
    required this.muted,
    required this.toggleMic,
    required this.confirm,
    required this.edit,
    required this.title,
    required this.content,
    this.replay,
  });

  @override
  State<WinConfirmationDialog> createState() => _WinConfirmationDialogState();
}

class _WinConfirmationDialogState extends State<WinConfirmationDialog> {
  bool _closing = false;
  bool _toggling = false;
  @override
  void initState() {
    super.initState();
    widget.game.addListener(_changed);
  }

  @override
  void dispose() {
    widget.game.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    // Schedule the frame whose post-frame callback dismisses this modal.
    setState(() {});
    if (!widget.pending()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _close();
      });
    }
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  Future<void> _toggle() async {
    if (_toggling) return;
    setState(() => _toggling = true);
    try {
      await widget.toggleMic();
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final muted = widget.muted();
    return gameDialogFrame(
      accent: AppTheme.success,
      icon: Icons.emoji_events_outlined,
      title: widget.title,
      prominentActions: true,
      titleTrailing: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: muted ? l10n.checkoutEnableMic : l10n.checkoutDisableMic,
            child: GameControlButton(
              icon: muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              color: AppTheme.opponentPink,
              active: !muted,
              onTap: _toggling ? null : _toggle,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            muted ? l10n.checkoutMicOff : l10n.checkoutMicOn,
            style: AppTheme.caption.copyWith(fontSize: 9),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          widget.content,
          if (widget.confirmation() != null)
            WinConfirmationNotice(
              confirmation: widget.confirmation()!,
              own: true,
            ),
        ],
      ),
      actions: [
        OutlinedButton(
          onPressed: () {
            _close();
            widget.edit();
          },
          style: gameNeutralOutlineButtonStyle(),
          child: Text(l10n.editDarts),
        ),
        ElevatedButton(
          onPressed: () {
            _close();
            widget.confirm();
          },
          style: gameFilledButtonStyle(AppTheme.success),
          child: Text(dsSentence(l10n.confirmWin)),
        ),
      ],
      bottomBar: widget.replay,
    );
  }
}

/// Uses the server deadline; a local clock never decides who won.
class WinConfirmationNotice extends StatefulWidget {
  final WinConfirmation confirmation;
  final bool own;
  final bool compact;
  const WinConfirmationNotice({
    super.key,
    required this.confirmation,
    required this.own,
    this.compact = false,
  });
  @override
  State<WinConfirmationNotice> createState() => _WinConfirmationNoticeState();
}

class _WinConfirmationNoticeState extends State<WinConfirmationNotice> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.confirmation, l10n = AppLocalizations.of(context);
    final seconds = info.secondsLeft;
    if (seconds == null || !info.pending) return const SizedBox.shrink();
    final warning = info.warning;
    final clock =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    final title = warning && info.closesCall
        ? l10n.checkoutCallEnds
        : l10n.checkoutAuto;
    final message = widget.own ? l10n.checkoutOwnAuto : l10n.checkoutOtherAuto;
    if (widget.compact) {
      return Semantics(
        liveRegion: warning,
        child: Text(
          '$title $clock',
          style: AppTheme.caption.copyWith(
            color: warning ? AppTheme.error : AppTheme.textSecondary,
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning ? AppTheme.error.withValues(alpha: .12) : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: warning
              ? AppTheme.error.withValues(alpha: .4)
              : AppTheme.border,
        ),
      ),
      child: Semantics(
        liveRegion: warning,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$title $clock',
              style: AppTheme.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: warning ? AppTheme.error : AppTheme.textSecondary,
              ),
            ),
            ...[
              const SizedBox(height: 4),
              Text(message, style: AppTheme.caption),
            ],
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tournament.dart';
import '../../models/user.dart';
import '../../providers/friends_provider.dart';
import '../../providers/tournament_provider.dart';
import '../../services/tournament_service.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/tournament_registration_gate.dart';
import '../../widgets/design_system.dart';
import 'community_tournament_form_screen.dart';

/// Players a community bracket needs before it can start. Keep in sync with
/// TournamentService.COMMUNITY_MIN_PLAYERS (backend).
const int kCommunityTournamentMinPlayers = 8;

/// What the organiser of a community tournament sees above the tabs while
/// registration is open: the start, share / invite / edit, and "start now"
/// once 8 players are in. Replaces the registration button for them — their
/// own participation is a switch of the edit form.
class CommunityOrganizerPanel extends StatefulWidget {
  final Tournament tournament;

  /// Whether the organiser is registered as a player (null while unknown).
  final bool? isRegistered;

  /// Reloads the screen after an action changed the tournament.
  final Future<void> Function() onChanged;

  const CommunityOrganizerPanel({
    super.key,
    required this.tournament,
    required this.isRegistered,
    required this.onChanged,
  });

  @override
  State<CommunityOrganizerPanel> createState() =>
      _CommunityOrganizerPanelState();
}

class _CommunityOrganizerPanelState extends State<CommunityOrganizerPanel> {
  bool _starting = false;

  Tournament get _t => widget.tournament;

  String _when(String pattern) {
    final locale = Localizations.localeOf(context).toString();
    return DateFormat(pattern, locale).format(_t.scheduledDate.toLocal());
  }

  Future<void> _share() async {
    final l10n = AppLocalizations.of(context);
    HapticService.lightImpact();
    await SharePlus.instance.share(
      ShareParams(
        text: l10n.organizerShareMessage(_t.name, _when('EEEE d MMMM, HH:mm')),
      ),
    );
  }

  Future<void> _invite() async {
    HapticService.lightImpact();
    final sent = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _InviteFriendsSheet(tournament: _t),
    );
    if (sent == null || !mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.inviteSheetSent(sent))),
    );
  }

  Future<void> _edit() async {
    // Cancelling refreshes the tournament, which removes this panel from the
    // screen while the form is still open: keep what outlives it.
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final onChanged = widget.onChanged;
    final result = await AppNavigator.toScreen<CommunityFormResult>(
      context,
      CommunityTournamentFormScreen(
        tournament: _t,
        organizerRegistered: widget.isRegistered ?? true,
      ),
    );
    if (result == null) return;
    if (result == CommunityFormResult.cancelled) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.communityCancelledToast)),
      );
      // Back to the agenda: the cancelled tournament's screen is over.
      navigator.maybePop();
      return;
    }
    await onChanged();
  }

  Future<void> _startNow() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.organizerStartConfirmTitle),
        content: Text(
          l10n.organizerStartConfirmBody(_t.currentParticipants),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.organizerStartAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _starting = true);
    HapticService.mediumImpact();
    // Starting refreshes the tournament to "in progress", which removes this
    // panel from the screen: keep what outlives it.
    final messenger = ScaffoldMessenger.of(context);
    final onChanged = widget.onChanged;
    final provider = context.read<TournamentProvider>();
    final ok = await provider.startCommunityTournament(_t.id);
    if (!ok) {
      if (!mounted) return;
      setState(() => _starting = false);
      final error = provider.error;
      if (error != null) {
        TournamentRegistrationGate.showRegistrationError(context, error);
        provider.clearError();
      }
      return;
    }
    if (mounted) setState(() => _starting = false);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.organizerStartedToast)),
    );
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final missing = kCommunityTournamentMinPlayers - _t.currentParticipants;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DsCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.organizerPanelTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.organizerPanelBody(_when('EEE d MMM · HH:mm')),
                style: AppTheme.caption.copyWith(height: 1.4),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _PanelButton(
                      icon: Icons.ios_share_rounded,
                      label: l10n.organizerShare,
                      onTap: _share,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PanelButton(
                      icon: Icons.person_add_alt_outlined,
                      label: l10n.organizerInvite,
                      onTap: _invite,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PanelButton(
                      icon: Icons.edit_outlined,
                      label: l10n.organizerEdit,
                      onTap: _edit,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // THE filled block of the screen once the bracket can start; disabled
        // with the count of missing players before that.
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: missing > 0 || _starting ? null : _startNow,
            icon: _starting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(l10n.organizerStartNow),
          ),
        ),
        if (missing > 0) ...[
          const SizedBox(height: 6),
          Text(
            l10n.organizerPlayersMissing(missing),
            textAlign: TextAlign.center,
            style: AppTheme.caption,
          ),
        ],
      ],
    );
  }
}

/// 40 px outlined button of the organiser card: icon + one word.
class _PanelButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PanelButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      icon: Icon(icon, size: 16, color: const Color(0xFFCBD5E1)),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// Bottom sheet: the organiser's friends with a checkbox each (already
/// registered ones greyed out), and one button that pushes the invitation.
/// Pops with the number of friends who got it.
class _InviteFriendsSheet extends StatefulWidget {
  final Tournament tournament;

  const _InviteFriendsSheet({required this.tournament});

  @override
  State<_InviteFriendsSheet> createState() => _InviteFriendsSheetState();
}

class _InviteFriendsSheetState extends State<_InviteFriendsSheet> {
  final Set<String> _selected = {};
  Set<String> _registered = {};
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    // loadFriends notifies synchronously: never during this first build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final friends = context.read<FriendsProvider>();
    try {
      await Future.wait([
        if (friends.friends.isEmpty) friends.loadFriends(),
        TournamentService.getRegistrations(widget.tournament.id).then((regs) {
          _registered = regs.map((r) => r.userId).toSet();
        }),
      ]);
    } catch (e) {
      debugPrint('Invite sheet load failed: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _send() async {
    if (_selected.isEmpty || _sending) return;
    setState(() => _sending = true);
    HapticService.mediumImpact();
    final provider = context.read<TournamentProvider>();
    final sent = await provider.inviteFriends(
      widget.tournament.id,
      _selected.toList(),
    );
    if (!mounted) return;
    if (sent == null) {
      setState(() => _sending = false);
      final error = provider.error;
      if (error != null) {
        TournamentRegistrationGate.showRegistrationError(context, error);
        provider.clearError();
      }
      return;
    }
    Navigator.of(context).pop(sent);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final friends = context.watch<FriendsProvider>().friends;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(l10n.inviteSheetTitle, style: AppTheme.titleLarge),
              const SizedBox(height: 10),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: CircularProgressIndicator(color: AppTheme.primary),
                  ),
                )
              else if (friends.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    l10n.inviteSheetEmpty,
                    textAlign: TextAlign.center,
                    style: AppTheme.bodyMedium,
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final friend in friends) _friendRow(l10n, friend),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selected.isEmpty || _sending ? null : _send,
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l10n.inviteSheetSend(_selected.length)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _friendRow(AppLocalizations l10n, User friend) {
    final registered = _registered.contains(friend.id);
    final selected = _selected.contains(friend.id);
    final name = friend.username;
    final initials =
        (name.length >= 2 ? name.substring(0, 2) : name).toUpperCase();

    return InkWell(
      onTap: registered
          ? null
          : () {
              HapticService.selectionClick();
              setState(() {
                if (!_selected.remove(friend.id)) _selected.add(friend.id);
              });
            },
      child: Container(
        height: 56,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppTheme.surfaceLight,
                shape: BoxShape.circle,
              ),
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE2E8F0),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.rowTitle.copyWith(
                  color: registered
                      ? AppTheme.textSecondary
                      : AppTheme.textPrimary,
                ),
              ),
            ),
            if (registered)
              DsPill(label: l10n.agendaRegisteredChip, color: AppTheme.success)
            else
              Checkbox(
                value: selected,
                onChanged: (_) {
                  HapticService.selectionClick();
                  setState(() {
                    if (!_selected.remove(friend.id)) _selected.add(friend.id);
                  });
                },
              ),
          ],
        ),
      ),
    );
  }
}

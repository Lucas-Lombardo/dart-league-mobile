import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tournament.dart';
import '../../providers/tournament_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/tournament_registration_gate.dart';
import '../../widgets/design_system.dart';
import 'stats/stats_widgets.dart' show StatsSegmentedControl;
import 'tournament_detail_screen.dart';

// Keep in sync with the backend (community-tournament.dto.ts and the
// COMMUNITY_* limits of TournamentService).
const List<int> kCommunityTournamentSizes = [8, 16, 64];
const List<int> kCommunityTournamentBestOf = [1, 3, 5];
/// A tournament is organised at least 48 h before it starts.
const Duration _minStartLead = Duration(hours: 48);
const Duration _maxStartLead = Duration(days: 30);
const Duration _registrationCloseLead = Duration(minutes: 15);

/// What the edit form tells the screen that opened it.
enum CommunityFormResult { saved, cancelled }

/// Create or edit a tournament organised by the signed-in player, on one
/// page: a name, ONE start date (registration closes by itself 15 min
/// before), a size and a match format. Open to every player — no visibility,
/// fee, rank or premium setting. Editing works while registration is open and
/// is also where the organiser cancels.
class CommunityTournamentFormScreen extends StatefulWidget {
  /// The tournament to edit; null creates a new one.
  final Tournament? tournament;

  /// Edit mode: whether the organiser is currently registered as a player.
  final bool organizerRegistered;

  const CommunityTournamentFormScreen({
    super.key,
    this.tournament,
    this.organizerRegistered = true,
  });

  @override
  State<CommunityTournamentFormScreen> createState() =>
      _CommunityTournamentFormScreenState();
}

class _CommunityTournamentFormScreenState
    extends State<CommunityTournamentFormScreen> {
  late final TextEditingController _name;
  late DateTime _start;
  late int _size;
  late int _bestOf;
  late bool _plays;
  bool _saving = false;
  String? _nameError;
  String? _startError;
  String? _sizeError;

  bool get _isEdit => widget.tournament != null;

  @override
  void initState() {
    super.initState();
    final t = widget.tournament;
    _name = TextEditingController(text: t?.name ?? '');
    final now = DateTime.now();
    // New tournament: the first full hour past the 48 h minimum.
    _start = t?.scheduledDate.toLocal() ??
        DateTime(now.year, now.month, now.day + 2, now.hour + 1);
    _size = t != null && kCommunityTournamentSizes.contains(t.maxParticipants)
        ? t.maxParticipants
        : kCommunityTournamentSizes.first;
    _bestOf = t != null && kCommunityTournamentBestOf.contains(t.bestOf)
        ? t.bestOf
        : 3;
    _plays = t == null ? true : widget.organizerRegistered;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    HapticService.lightImpact();
    final now = DateTime.now();
    final earliest = now.add(_minStartLead);
    final firstDay = DateTime(earliest.year, earliest.month, earliest.day);
    final date = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(firstDay) ? firstDay : _start,
      firstDate: firstDay,
      lastDate: now.add(_maxStartLead),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
    );
    if (time == null || !mounted) return;
    setState(() {
      _start = DateTime(date.year, date.month, date.day, time.hour, time.minute);
      _startError = null;
    });
  }

  bool _validate(AppLocalizations l10n) {
    final now = DateTime.now();
    final registered = widget.tournament?.currentParticipants ?? 0;
    setState(() {
      _nameError =
          _name.text.trim().length < 3 ? l10n.communityFormNameTooShort : null;
      // An unchanged date on edit stays valid even inside the 30-min margin.
      final startUnchanged = _isEdit &&
          _start.isAtSameMomentAs(widget.tournament!.scheduledDate.toLocal());
      _startError = startUnchanged
          ? null
          : _start.isBefore(now.add(_minStartLead))
              ? l10n.communityFormStartTooSoon
              : _start.isAfter(now.add(_maxStartLead))
                  ? l10n.communityFormStartTooLate
                  : null;
      _sizeError = _isEdit && _size < registered
          ? l10n.communityFormSizeBelowRegistered(registered)
          : null;
    });
    return _nameError == null && _startError == null && _sizeError == null;
  }

  void _showError(TournamentProvider provider) {
    final error = provider.error;
    if (error != null && mounted) {
      TournamentRegistrationGate.showRegistrationError(context, error);
      provider.clearError();
    }
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    if (_saving || !_validate(l10n)) return;
    setState(() => _saving = true);
    HapticService.mediumImpact();
    final provider = context.read<TournamentProvider>();

    // Playing in one's own tournament counts in the monthly quota of players
    // without premium (2 a month): same popup as a registration.
    final joinsNow = _plays && (!_isEdit || !widget.organizerRegistered);
    if (joinsNow &&
        !await TournamentRegistrationGate.checkMonthlyQuota(context, _start)) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (!mounted) return;

    if (!_isEdit) {
      final id = await provider.createCommunityTournament(
        name: _name.text.trim(),
        scheduledDate: _start,
        maxParticipants: _size,
        bestOf: _bestOf,
        organizerPlays: _plays,
      );
      if (!mounted) return;
      if (id == null) {
        setState(() => _saving = false);
        _showError(provider);
        return;
      }
      // Straight to the new tournament: that's where the organiser shares,
      // invites and starts it.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TournamentDetailScreen(tournamentId: id),
        ),
      );
      return;
    }

    final t = widget.tournament!;
    final name = _name.text.trim();
    final startChanged =
        !_start.isAtSameMomentAs(t.scheduledDate.toLocal());
    var ok = await provider.updateCommunityTournament(
      t.id,
      name: name != t.name ? name : null,
      scheduledDate: startChanged ? _start : null,
      maxParticipants: _size != t.maxParticipants ? _size : null,
      bestOf: _bestOf != t.bestOf ? _bestOf : null,
    );
    if (ok && _plays != widget.organizerRegistered) {
      ok = _plays
          ? await provider.registerForTournament(t.id, tournament: t)
          : await provider.unregisterFromTournament(t.id);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      _showError(provider);
      return;
    }
    Navigator.of(context).pop(CommunityFormResult.saved);
  }

  Future<void> _cancelTournament() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.communityCancelConfirmTitle),
        content: Text(l10n.communityCancelConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.communityKeep),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: Text(l10n.communityCancelTournament),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    final provider = context.read<TournamentProvider>();
    final ok = await provider.cancelCommunityTournament(widget.tournament!.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!ok) {
      _showError(provider);
      return;
    }
    Navigator.of(context).pop(CommunityFormResult.cancelled);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final startLabel =
        '${DateFormat('EEE d MMM', locale).format(_start)} · ${DateFormat('HH:mm').format(_start)}';
    final closesAt =
        DateFormat('HH:mm').format(_start.subtract(_registrationCloseLead));

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: DsScreenHeader(
                title: _isEdit
                    ? l10n.communityFormTitleEdit
                    : l10n.communityFormTitleNew,
                showBack: true,
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                children: [
                  _Labeled(
                    label: l10n.communityFormName,
                    error: _nameError,
                    child: TextField(
                      controller: _name,
                      maxLength: 40,
                      textCapitalization: TextCapitalization.sentences,
                      style: AppTheme.bodyLarge.copyWith(
                        color: AppTheme.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.communityFormNameHint,
                        counterText: '',
                      ),
                      onChanged: (_) {
                        if (_nameError != null) {
                          setState(() => _nameError = null);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  _Labeled(
                    label: l10n.communityFormStart,
                    error: _startError,
                    hint: l10n.communityFormRegistrationCloses(closesAt),
                    child: _StartField(label: startLabel, onTap: _pickStart),
                  ),
                  const SizedBox(height: 18),
                  _Labeled(
                    label: l10n.communityFormPlayers,
                    error: _sizeError,
                    child: StatsSegmentedControl(
                      labels: [
                        for (final n in kCommunityTournamentSizes) '$n',
                      ],
                      index: kCommunityTournamentSizes.indexOf(_size),
                      onChanged: (i) {
                        HapticService.selectionClick();
                        setState(() {
                          _size = kCommunityTournamentSizes[i];
                          _sizeError = null;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  _Labeled(
                    label: l10n.communityFormFormat,
                    child: StatsSegmentedControl(
                      labels: [
                        for (final n in kCommunityTournamentBestOf) 'BO$n',
                      ],
                      index: kCommunityTournamentBestOf.indexOf(_bestOf),
                      onChanged: (i) {
                        HapticService.selectionClick();
                        setState(
                          () => _bestOf = kCommunityTournamentBestOf[i],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  DsCard(
                    radius: AppTheme.radiusRow,
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.communityFormIPlay,
                                style: AppTheme.rowTitle,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.communityFormIPlaySub,
                                style: AppTheme.caption,
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _plays,
                          onChanged: (v) => setState(() => _plays = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: AppTheme.textTertiary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          l10n.communityFormNote,
                          style: AppTheme.caption.copyWith(height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _isEdit ? l10n.save : l10n.communityFormCreate,
                            ),
                    ),
                  ),
                  if (_isEdit)
                    TextButton(
                      onPressed: _saving ? null : _cancelTournament,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.error,
                      ),
                      child: Text(l10n.communityCancelTournament),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 12 / 600 label over its control, then either the error (red) or an
/// optional hint (grey) under it.
class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  final String? error;
  final String? hint;

  const _Labeled({
    required this.label,
    required this.child,
    this.error,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final below = error ?? hint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        child,
        if (below != null) ...[
          const SizedBox(height: 6),
          Text(
            below,
            style: AppTheme.caption.copyWith(
              color: error != null ? AppTheme.error : AppTheme.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// The one date field: looks like the app's inputs, opens the date then the
/// time picker.
class _StartField extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _StartField({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        side: const BorderSide(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.event_outlined,
                  size: 18,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: AppTheme.bodyLarge.copyWith(
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppTheme.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

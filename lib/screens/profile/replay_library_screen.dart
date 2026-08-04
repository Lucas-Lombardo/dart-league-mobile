import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/replay_group.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/replay_clips_store.dart';
import '../../services/replay_upload_service.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import 'replay_player_screen.dart';

/// « Mes replays » — the user's cloud library (GET /replays/mine), grouped by
/// MATCH: a clip is never alone, it belongs to a game against someone with a
/// result. Three "100 pts" in a row only make sense once you see they are the
/// same BO3 against the same opponent.
///
/// Free accounts see the 5-clip quota banner once it bites.
class ReplayLibraryScreen extends StatefulWidget {
  const ReplayLibraryScreen({super.key});

  @override
  State<ReplayLibraryScreen> createState() => _ReplayLibraryScreenState();
}

class _ReplayLibraryScreenState extends State<ReplayLibraryScreen> {
  List<ReplayGroup>? _groups;

  /// Freshly captured clips whose overlay render / upload is still running
  /// (the end-of-match pipeline) — shown as dimmed "preparing" rows at the
  /// top so arriving straight from the end screen never reads as "my
  /// replays are gone". Snapshotted together with [_groups] so a pending
  /// row and its cloud replacement swap in a single frame.
  List<ReplayClip> _pending = const [];
  int _total = 0;

  /// How long the backend keeps a clip. Sent with the library; the fallback
  /// only matters against a backend that predates the retention sweep.
  int _retentionDays = 30;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _pending = ReplayClipsStore.preparing();
    // Fires when an upload lands or fails: the cloud list changed, refetch.
    ReplayClipsStore.revision.addListener(_onClipsChanged);
    _load();
  }

  @override
  void dispose() {
    ReplayClipsStore.revision.removeListener(_onClipsChanged);
    super.dispose();
  }

  void _onClipsChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/replays/mine?limit=50');
      if (!mounted) return;
      setState(() {
        _groups = groupReplayClips(
          List<Map<String, dynamic>>.from(data['clips'] as List),
        );
        _pending = ReplayClipsStore.preparing();
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _retentionDays =
            (data['retentionDays'] as num?)?.toInt() ?? _retentionDays;
        _failed = false;
      });
    } catch (e) {
      debugPrint('[ReplayLibrary] load failed: $e');
      if (mounted) {
        setState(() {
          _pending = ReplayClipsStore.preparing();
          _failed = true;
        });
      }
    }
  }

  Future<void> _delete(String id) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(l10n.replayDeleteTitle,
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.replayDelete,
                style: const TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.delete('/replays/$id');
      _load();
    } catch (e) {
      debugPrint('[ReplayLibrary] delete failed: $e');
    }
  }

  Future<void> _rename(ReplayEntry clip) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: clip.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(l10n.replayRename,
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.replayNameHint,
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (name == null) return;
    try {
      await ApiService.patch('/replays/${clip.id}', {'name': name});
      _load();
    } catch (e) {
      debugPrint('[ReplayLibrary] rename failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = context.watch<AuthProvider>();
    final premium = auth.currentUser?.isPremiumActive ?? false;
    final quotaBites =
        !premium && (_total >= 5 || ReplayUploadService.quotaReached);

    return Scaffold(
      appBar: AppBar(title: Text('🎬 ${l10n.myReplays}')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.primary,
        // Pending rows never wait for the network: straight from the end
        // screen, the list shows them before /replays/mine even answers.
        child: _groups == null && _pending.isEmpty
            ? Center(
                child: _failed
                    ? IconButton(
                        icon: const Icon(Icons.refresh,
                            color: AppTheme.textSecondary, size: 32),
                        onPressed: _load,
                      )
                    : const CircularProgressIndicator(color: AppTheme.primary),
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  if (quotaBites) _quotaBanner(l10n),
                  if (_groups?.isNotEmpty ?? false) _retentionNotice(l10n),
                  if (_pending.isNotEmpty) ..._pendingSections(l10n),
                  if (_groups != null && _groups!.isEmpty && _pending.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(children: [
                        const Icon(Icons.videocam_off,
                            size: 44, color: AppTheme.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          l10n.replaysEmpty,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 14),
                        ),
                      ]),
                    )
                  else if (_groups != null)
                    ..._buildGroups(
                      l10n,
                      // The pending sections already printed today's heading.
                      lastDay: _pending.isNotEmpty
                          ? _dayLabel(DateTime.now(), l10n)
                          : null,
                    ),
                ],
              ),
      ),
    );
  }

  /// The clips of the match(es) just played, still rendering/uploading: their
  /// final place in the list, today's heading included, as dimmed rows with a
  /// spinner — each is replaced by its cloud row when its upload lands (the
  /// store notify triggers the refetch).
  List<Widget> _pendingSections(AppLocalizations l10n) {
    final byMatch = <String?, List<ReplayClip>>{};
    for (final clip in _pending) {
      byMatch.putIfAbsent(clip.matchId, () => []).add(clip);
    }
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          _dayLabel(DateTime.now(), l10n).toUpperCase(),
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.4,
          ),
        ),
      ),
      for (final clips in byMatch.values)
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _pendingHeader(clips.first, l10n),
              const SizedBox(height: 10),
              for (var i = 0; i < clips.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                  child: _pendingRow(clips[i], i + 1, l10n),
                ),
            ],
          ),
        ),
    ];
  }

  /// Light twin of [_matchHeader]: the cloud group (opponent, format, result)
  /// does not exist yet, so this shows what the capture knew — the opponent's
  /// name and the time.
  Widget _pendingHeader(ReplayClip clip, AppLocalizations l10n) {
    final title =
        clip.opponent != null ? l10n.replayVs(clip.opponent!) : l10n.replayNoMatch;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            _timeLabel(clip.createdAt),
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  /// Dimmed sibling of [_clipRow]: spinner instead of the play affordance,
  /// « Préparation du clip… » as the subtitle, no tap and no menu — the row
  /// exists to say "it's coming", nothing on it is actionable yet.
  Widget _pendingRow(ReplayClip clip, int position, AppLocalizations l10n) {
    final score = clip.turnTotal != null && clip.turnTotal! > 0
        ? '${clip.turnTotal}'
        : null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppTheme.textSecondary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppTheme.textSecondary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppTheme.textSecondary.withValues(alpha: 0.25)),
            ),
            child: const Center(
              child: SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (score != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                score,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 21,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.replayClipNumber(position),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.replayPreparing,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 11.5,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Groups, with a day heading whenever the date changes. [lastDay] seeds
  /// the dedup when a heading was already printed above (pending sections).
  List<Widget> _buildGroups(AppLocalizations l10n, {String? lastDay}) {
    final widgets = <Widget>[];
    for (final group in _groups!) {
      final day = _dayLabel(group.latestAt, l10n);
      if (day != lastDay) {
        widgets.add(Padding(
          padding: EdgeInsets.only(top: lastDay == null ? 0 : 22, bottom: 10),
          child: Text(
            day.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ));
        lastDay = day;
      }
      widgets.add(_matchSection(group, l10n));
    }
    return widgets;
  }

  Widget _quotaBanner(AppLocalizations l10n) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.workspace_premium, color: AppTheme.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.replayQuotaBanner,
              style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      );

  /// Always on, above the first match: a clip that will be deleted must say
  /// so long before the row starts counting down.
  Widget _retentionNotice(AppLocalizations l10n) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.schedule, color: AppTheme.textSecondary, size: 16),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              l10n.replayRetentionNotice(_retentionDays),
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 12.5, height: 1.35),
            ),
          ),
        ]),
      );

  /// One match: its header, then one full-width row per clip. Rows instead of
  /// thumbnails because there is no thumbnail to show — an empty rectangle
  /// promises an image the clip does not have.
  Widget _matchSection(ReplayGroup group, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _matchHeader(group, l10n),
          const SizedBox(height: 10),
          for (var i = 0; i < group.clips.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: _clipRow(group.clips[i], i + 1, l10n),
            ),
        ],
      ),
    );
  }

  Widget _matchHeader(ReplayGroup group, AppLocalizations l10n) {
    final title = group.opponent != null
        ? l10n.replayVs(group.opponent!)
        : l10n.replayNoMatch;
    final format = _formatLabel(group, l10n);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (format != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    format,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11.5),
                  ),
                ),
            ],
          ),
        ),
        if (group.outcome != null) ...[
          const SizedBox(width: 8),
          _outcomeChip(group, l10n),
        ],
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            _timeLabel(group.latestAt),
            style:
                const TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  Widget _outcomeChip(ReplayGroup group, AppLocalizations l10n) {
    final (label, color) = switch (group.outcome) {
      'won' => (l10n.replayOutcomeWon, AppTheme.success),
      'lost' => (l10n.replayOutcomeLost, AppTheme.error),
      _ => (l10n.replayOutcomePending, AppTheme.textSecondary),
    };
    final score = group.hasLegs && group.outcome != 'pending'
        ? ' ${group.myLegs}–${group.opponentLegs}'
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label$score',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  /// A clip: play affordance, the visit total, then its name (or its rank in
  /// the match) over the duration and the time it was captured. Renaming and
  /// deleting stay on the ⋮ at the end of the row.
  Widget _clipRow(ReplayEntry clip, int position, AppLocalizations l10n) {
    const accent = AppTheme.playerBlue;
    final score = clip.turnTotal != null && clip.turnTotal! > 0
        ? '${clip.turnTotal}'
        : null;
    final expiry = _expiryLabel(clip, l10n);
    final duration = clip.durationLabel;
    final time = _timeLabel(clip.createdAt);
    final subtitle = duration == null ? time : '$duration · $time';

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticService.lightImpact();
          AppNavigator.toScreen(
            context,
            ReplayPlayerScreen(source: clip.url, isLocal: false),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withValues(alpha: 0.38)),
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              if (score != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Text(
                    score,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      height: 1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      clip.hasName
                          ? clip.name!
                          : l10n.replayClipNumber(position),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            clip.hasName ? Colors.white : AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight:
                            clip.hasName ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11.5,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              if (expiry != null) ...[
                const SizedBox(width: 8),
                _expiryBadge(expiry),
              ],
              _clipMenu(clip, l10n),
            ],
          ),
        ),
      ),
    );
  }

  /// Only shown in the last week of a clip's life — a countdown on every row
  /// would be noise, on the ones about to go it is the point.
  static const _expiryWarningDays = 7;

  String? _expiryLabel(ReplayEntry clip, AppLocalizations l10n) {
    final daysLeft = clip.daysLeft(_retentionDays);
    if (daysLeft > _expiryWarningDays) return null;
    return daysLeft <= 0
        ? l10n.replayExpiresToday
        : l10n.replayExpiresIn(daysLeft);
  }

  Widget _expiryBadge(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.error.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          ),
        ),
      );

  Widget _clipMenu(ReplayEntry clip, AppLocalizations l10n) =>
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert,
            color: AppTheme.textSecondary, size: 18),
        padding: EdgeInsets.zero,
        splashRadius: 18,
        color: AppTheme.surface,
        onSelected: (action) {
          if (action == 'rename') _rename(clip);
          if (action == 'delete') _delete(clip.id);
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'rename',
            child: Text(l10n.replayRename,
                style: const TextStyle(color: Colors.white)),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Text(l10n.replayDelete,
                style: const TextStyle(color: AppTheme.error)),
          ),
        ],
      );

  String? _formatLabel(ReplayGroup group, AppLocalizations l10n) {
    if (group.tournamentName != null && group.tournamentName!.isNotEmpty) {
      return group.tournamentName;
    }
    final base = switch (group.matchType) {
      'ranked' => l10n.replayFormatRanked,
      'friendly' => l10n.replayFormatFriendly,
      'placement' => l10n.replayFormatPlacement,
      _ => null,
    };
    if (base == null) return null;
    return group.bestOf != null ? '$base · BO${group.bestOf}' : base;
  }

  String _dayLabel(DateTime when, AppLocalizations l10n) {
    final now = DateTime.now();
    final day = DateTime(when.year, when.month, when.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return l10n.todayLabel;
    if (diff == 1) return l10n.yesterdayLabel;
    return '${when.day.toString().padLeft(2, '0')}/'
        '${when.month.toString().padLeft(2, '0')}';
  }

  String _timeLabel(DateTime when) =>
      '${when.hour.toString().padLeft(2, '0')}:'
      '${when.minute.toString().padLeft(2, '0')}';
}

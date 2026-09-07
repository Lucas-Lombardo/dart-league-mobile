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
import '../../widgets/design_system.dart';
import 'replay_player_screen.dart';

/// « Mes replays » — the user's cloud library (GET /replays/mine), grouped by
/// MATCH: a clip is never alone, it belongs to a game against someone with a
/// result. Three "100 pts" in a row only make sense once you see they are the
/// same BO3 against the same opponent.
///
/// Free accounts see the 5-clip quota line once it bites.
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
        title: Text(l10n.replayDeleteTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: Text(l10n.replayDelete),
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
        title: Text(l10n.replayRename),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
          decoration: InputDecoration(hintText: l10n.replayNameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
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
      appBar: AppBar(title: Text(l10n.myReplays)),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.primary,
        // Pending rows never wait for the network: straight from the end
        // screen, the list shows them before /replays/mine even answers.
        child: _groups == null && _pending.isEmpty
            ? _firstLoadState(l10n)
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  if (quotaBites) ...[
                    _QuietLine(
                      icon: Icons.workspace_premium_outlined,
                      // The one gold on the page: it points at Premium.
                      iconColor: AppTheme.accent,
                      text: l10n.replayQuotaBanner,
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (_groups?.isNotEmpty ?? false) ...[
                    _QuietLine(
                      icon: Icons.schedule_rounded,
                      text: l10n.replayRetentionNotice(_retentionDays),
                    ),
                    const SizedBox(height: 18),
                  ],
                  if (_pending.isNotEmpty) ..._pendingSections(l10n),
                  if (_groups != null && _groups!.isEmpty && _pending.isEmpty)
                    _MessageCard(
                      icon: Icons.videocam_off_outlined,
                      title: l10n.replaysEmptyTitle,
                      subtitle: l10n.replaysEmptyHint,
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

  /// Nothing to show yet: the spinner, or the retry card when the fetch blew
  /// up. Both stay scrollable so pull-to-refresh keeps working.
  Widget _firstLoadState(AppLocalizations l10n) {
    if (!_failed) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        _MessageCard(
          icon: Icons.cloud_off_rounded,
          title: l10n.errorOccurred,
          action: OutlinedButton(onPressed: _load, child: Text(l10n.retry)),
        ),
      ],
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
          style: AppTheme.labelSmall,
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
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
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
            style: AppTheme.sectionTitle,
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(_timeLabel(clip.createdAt), style: AppTheme.caption),
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
    return DsCard(
      radius: AppTheme.radiusRow,
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
      child: Row(
        children: [
          const _ClipThumb(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          if (score != null) ...[
            Text(score, style: _scoreStyle.copyWith(color: AppTheme.textSecondary)),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.replayClipNumber(position),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _clipTitleStyle.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.replayPreparing,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption.copyWith(color: AppTheme.primaryLight),
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
          child: Text(day.toUpperCase(), style: AppTheme.labelSmall),
        ));
        lastDay = day;
      }
      widgets.add(_matchSection(group, l10n));
    }
    return widgets;
  }

  /// One match: its header, then one full-width row per clip. Rows instead of
  /// thumbnails because there is no thumbnail to show — an empty rectangle
  /// promises an image the clip does not have, so the leading square carries
  /// the play affordance instead.
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
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
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
                style: AppTheme.sectionTitle,
              ),
              if (format != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    format,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption,
                  ),
                ),
            ],
          ),
        ),
        if (group.outcome != null) ...[
          const SizedBox(width: 8),
          _outcomePill(group, l10n),
        ],
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(_timeLabel(group.latestAt), style: AppTheme.caption),
        ),
      ],
    );
  }

  Widget _outcomePill(ReplayGroup group, AppLocalizations l10n) {
    final (label, color) = switch (group.outcome) {
      'won' => (l10n.replayOutcomeWon, AppTheme.success),
      'lost' => (l10n.replayOutcomeLost, AppTheme.error),
      _ => (l10n.replayOutcomePending, AppTheme.textSecondary),
    };
    final score = group.hasLegs && group.outcome != 'pending'
        ? ' ${group.myLegs}–${group.opponentLegs}'
        : '';
    return DsPill(label: '$label$score', color: color);
  }

  /// A clip: play affordance, the visit total, then its name (or its rank in
  /// the match) over the duration and the time it was captured. Renaming and
  /// deleting stay on the ⋮ at the end of the row.
  Widget _clipRow(ReplayEntry clip, int position, AppLocalizations l10n) {
    final score = clip.turnTotal != null && clip.turnTotal! > 0
        ? '${clip.turnTotal}'
        : null;
    final expiry = _expiryLabel(clip, l10n);
    final duration = clip.durationLabel;
    final time = _timeLabel(clip.createdAt);
    final subtitle = duration == null ? time : '$duration · $time';

    return DsCard(
      radius: AppTheme.radiusRow,
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      onTap: () => AppNavigator.toScreen(
        context,
        ReplayPlayerScreen(source: clip.url, isLocal: false),
      ),
      child: Row(
        children: [
          const _ClipThumb(
            child: Icon(Icons.play_arrow_rounded, size: 22, color: Color(0xFFE2E8F0)),
          ),
          const SizedBox(width: 12),
          if (score != null) ...[
            Text(score, style: _scoreStyle),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  clip.hasName ? clip.name! : l10n.replayClipNumber(position),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: clip.hasName
                      ? _clipTitleStyle
                      : _clipTitleStyle.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
          if (expiry != null) ...[
            const SizedBox(width: 8),
            DsPill(label: expiry, color: AppTheme.error),
          ],
          _clipMenu(clip, l10n),
        ],
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

  Widget _clipMenu(ReplayEntry clip, AppLocalizations l10n) =>
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded,
            color: AppTheme.textSecondary, size: 20),
        padding: EdgeInsets.zero,
        splashRadius: 18,
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          side: const BorderSide(color: AppTheme.border),
        ),
        onSelected: (action) {
          if (action == 'rename') _rename(clip);
          if (action == 'delete') _delete(clip.id);
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'rename',
            child: Text(l10n.replayRename, style: AppTheme.rowTitle),
          ),
          PopupMenuItem(
            value: 'delete',
            child: Text(
              l10n.replayDelete,
              style: AppTheme.rowTitle.copyWith(color: AppTheme.error),
            ),
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

/// Clip title: 14 / 600, the row's one line of identity.
const TextStyle _clipTitleStyle = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w600,
  color: AppTheme.textPrimary,
);

/// The visit total that makes a clip worth opening, tabular so a column of
/// rows lines up.
const TextStyle _scoreStyle = TextStyle(
  fontSize: 19,
  fontWeight: FontWeight.w700,
  height: 1,
  color: AppTheme.textPrimary,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// Where a thumbnail would go: a 44 px square with a 12 px radius carrying
/// the play affordance (or the upload spinner).
class _ClipThumb extends StatelessWidget {
  final Widget child;

  const _ClipThumb({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: child,
    );
  }
}

/// A quiet note above the list: a 16 px icon and one caption line.
class _QuietLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color iconColor;

  const _QuietLine({
    required this.icon,
    required this.text,
    this.iconColor = AppTheme.textTertiary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: AppTheme.caption.copyWith(height: 1.35)),
        ),
      ],
    );
  }
}

/// Empty / error state: a card with a quiet icon, a title, an optional line
/// and an optional action.
class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const _MessageCard({
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return DsCard(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppTheme.textTertiary),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: AppTheme.rowTitle),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, textAlign: TextAlign.center, style: AppTheme.caption),
          ],
          if (action != null) ...[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}

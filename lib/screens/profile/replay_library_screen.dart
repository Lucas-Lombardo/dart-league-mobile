import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/replay_group.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
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
  int _total = 0;

  /// How long the backend keeps a clip. Sent with the library; the fallback
  /// only matters against a backend that predates the retention sweep.
  int _retentionDays = 30;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/replays/mine?limit=50');
      if (!mounted) return;
      setState(() {
        _groups = groupReplayClips(
          List<Map<String, dynamic>>.from(data['clips'] as List),
        );
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _retentionDays =
            (data['retentionDays'] as num?)?.toInt() ?? _retentionDays;
        _failed = false;
      });
    } catch (e) {
      debugPrint('[ReplayLibrary] load failed: $e');
      if (mounted) setState(() => _failed = true);
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
        child: _groups == null
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
                  if (_groups!.isNotEmpty) _retentionNotice(l10n),
                  if (_groups!.isEmpty)
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
                  else
                    ..._buildGroups(l10n),
                ],
              ),
      ),
    );
  }

  /// Groups, with a day heading whenever the date changes.
  List<Widget> _buildGroups(AppLocalizations l10n) {
    final widgets = <Widget>[];
    String? lastDay;
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
  /// so long before the tile starts counting down.
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

  /// One match: its header, then its clips on a rail — the rail is what says
  /// « these belong together ».
  Widget _matchSection(ReplayGroup group, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _matchHeader(group, l10n),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.only(left: 12),
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: AppTheme.surfaceLight, width: 2),
              ),
            ),
            child: SizedBox(
              height: 132,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: group.clips.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) => _clipTile(group.clips[i], l10n),
              ),
            ),
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

  /// A clip: its total in big, its custom name underneath when it has one —
  /// renaming stays reachable from the ⋮ on the tile.
  Widget _clipTile(ReplayEntry clip, AppLocalizations l10n) {
    const accent = AppTheme.playerBlue;
    final score = clip.turnTotal != null && clip.turnTotal! > 0
        ? '${clip.turnTotal}'
        : null;
    final expiry = _expiryLabel(clip, l10n);
    return SizedBox(
      width: 104,
      child: Material(
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
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withValues(alpha: 0.35)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: 0.12),
                  AppTheme.gameBackground,
                ],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 6,
                  left: 8,
                  child: expiry != null
                      ? _expiryBadge(expiry)
                      : const Icon(Icons.videocam, color: accent, size: 16),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: _tileMenu(clip, l10n),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (score != null)
                        Text(
                          score,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: clip.hasName ? 22 : 30,
                            height: 1,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      if (clip.hasName)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            clip.name!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Only shown in the last week of a clip's life — a countdown on every tile
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

  Widget _tileMenu(ReplayEntry clip, AppLocalizations l10n) =>
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

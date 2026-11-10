import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import 'challenge_api.dart';
import 'challenge_models.dart';
import 'challenge_widgets.dart';

/// « Les N joueurs » of the challenge screen: the whole ranking of the day
/// (50 first + me) in its three views, with each view's count.
class ChallengeLeaderboardScreen extends StatefulWidget {
  final ChallengeToday today;
  final ChallengeView initialView;

  /// The boards the challenge screen already loaded (shown at once).
  final Map<ChallengeView, ChallengeLeaderboard> boards;

  const ChallengeLeaderboardScreen({
    super.key,
    required this.today,
    this.initialView = ChallengeView.rank,
    this.boards = const {},
  });

  @override
  State<ChallengeLeaderboardScreen> createState() => _ChallengeLeaderboardScreenState();
}

class _ChallengeLeaderboardScreenState extends State<ChallengeLeaderboardScreen> {
  late ChallengeView _view = widget.initialView;
  late final Map<ChallengeView, ChallengeLeaderboard> _boards = Map.of(widget.boards);
  final Set<ChallengeView> _loading = {};

  @override
  void initState() {
    super.initState();
    if (!_boards.containsKey(_view)) _load(_view);
  }

  Future<void> _load(ChallengeView view) async {
    if (!_loading.add(view)) return;
    setState(() {});
    try {
      final board = await ChallengeApi.leaderboard(view);
      if (mounted) setState(() => _boards[view] = board);
    } catch (e) {
      debugPrint('ChallengeLeaderboardScreen: $e');
    } finally {
      _loading.remove(view);
      if (mounted) setState(() {});
    }
  }

  Future<void> _refresh() async {
    _boards.remove(_view);
    await _load(_view);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final today = widget.today;
    final board = _boards[_view];
    final counts = board ?? (_boards.values.isEmpty ? null : _boards.values.first);
    final labels = [
      l10n.challengeTabRank(challengeBoardName(l10n, today.board.rank), counts?.countRank ?? today.board.players),
      l10n.challengeTabAll(counts?.countAll ?? today.players),
      l10n.challengeTabFriends(counts?.countFriends ?? 0),
    ];
    final rows = board?.rows ?? const <ChallengeRow>[];
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: DsScreenHeader(title: l10n.challengeLeaderboardTitle, showBack: true),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: ChallengeTabs(
                labels: labels,
                selected: _view.index,
                onSelect: (i) {
                  final view = ChallengeView.values[i];
                  setState(() => _view = view);
                  if (!_boards.containsKey(view)) _load(view);
                },
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppTheme.primary,
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                  children: [
                    if (_view == ChallengeView.rank && today.board.merged) ...[
                      Text(
                        l10n.challengeMergedWith(
                          today.board.ranks.where((r) => r != today.board.rank).map((r) => challengeBoardName(l10n, r)).join(', '),
                        ),
                        style: AppTheme.caption,
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (board == null && _loading.contains(_view))
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5)),
                      )
                    else if (rows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          _view == ChallengeView.friends ? l10n.challengeEmptyFriends : l10n.challengeEmptyBoard,
                          style: AppTheme.caption.copyWith(fontSize: 13),
                        ),
                      )
                    else
                      for (final row in rows) ...[
                        ChallengeRowTile(row: row, format: today.format),
                        const SizedBox(height: 6),
                      ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

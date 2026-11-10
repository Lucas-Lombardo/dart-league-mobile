import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/progression_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/rank_utils.dart';
import '../../widgets/design_system.dart';
import '../../widgets/progression/player_showcase_card.dart' show PremiumCrown;
import '../../widgets/progression/progression_widgets.dart' show FramedAvatar;
import 'challenge_api.dart';
import 'challenge_leaderboard_screen.dart';
import 'challenge_mini_board.dart';
import 'challenge_models.dart';
import 'challenge_play_screen.dart';
import 'challenge_podium_screen.dart';
import 'challenge_proof_uploader.dart';
import 'challenge_result_screen.dart';
import 'challenge_widgets.dart';
import 'logic/challenge_strategy.dart';

/// XP of the ranked try when the content does not say (XP_RULES.challenge).
const int kChallengeDefaultXp = 50;

/// XP of a top 10 % finish (backend CHALLENGE_TOP10_XP, not served).
const int kChallengeTop10Xp = 50;

/// The daily challenge, screen B (mockups ecrans/DefB1 before the ranked try,
/// DefB2 after): the format in one line with its small board, the score to
/// beat (or my duel with the n°1), one button, the top 5. Everything else is
/// one tap away: the full rule (ⓘ), the week of the streak (header pill), the
/// whole ranking and yesterday's n°1 (links under the top 5).
class ChallengeScreen extends StatefulWidget {
  const ChallengeScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChallengeScreen()));

  @override
  State<ChallengeScreen> createState() => _ChallengeScreenState();
}

class _ChallengeScreenState extends State<ChallengeScreen> {
  ChallengeView _view = ChallengeView.rank;
  final Map<ChallengeView, ChallengeLeaderboard> _boards = {};
  final Set<ChallengeView> _loading = {};
  bool _failed = false;
  bool _starting = false;
  Timer? _tick;
  Timer? _dayEnd;
  DateTime? _dayEndAt;

  ChallengeStore get _store => ChallengeStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    // The "ends in" of the format card.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _watchDayEnd();
    unawaited(ChallengeProofUploader.sweepPending());
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    _tick?.cancel();
    _dayEnd?.cancel();
    super.dispose();
  }

  void _onStore() {
    if (!mounted) return;
    _watchDayEnd();
    setState(() {});
  }

  String? get _userId {
    try {
      return context.read<AuthProvider>().currentUser?.id;
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// Null once the day is over: the store never hands out an expired day.
  ChallengeToday? get _today => _store.todayFor(_userId) ?? _store.today;

  /// When the day ends with the screen open, yesterday's « Jouer » goes away
  /// and today's challenge is fetched.
  void _watchDayEnd() {
    final end = _today?.endsAt;
    if (end == _dayEndAt) return;
    _dayEnd?.cancel();
    _dayEndAt = end;
    if (end == null) return;
    final wait = end.difference(DateTime.now());
    _dayEnd = Timer(wait.isNegative ? Duration.zero : wait + const Duration(seconds: 1), () {
      if (!mounted) return;
      _dayEndAt = null;
      _reload();
    });
  }

  Future<void> _reload() async {
    setState(() => _failed = false);
    await _store.refresh(userId: _userId);
    if (!mounted) return;
    _watchDayEnd();
    if (_today == null) {
      setState(() => _failed = true);
      return;
    }
    _boards.clear();
    await Future.wait({ChallengeView.rank, _view}.map(_loadBoard));
  }

  Future<void> _loadBoard(ChallengeView view) async {
    if (!_loading.add(view)) return;
    if (mounted) setState(() {});
    try {
      final board = await ChallengeApi.leaderboard(view);
      if (mounted) setState(() => _boards[view] = board);
    } catch (e) {
      debugPrint('ChallengeScreen: leaderboard failed: $e');
    } finally {
      _loading.remove(view);
      if (mounted) setState(() {});
    }
  }

  void _selectView(ChallengeView view) {
    HapticService.selectionClick();
    setState(() => _view = view);
    if (!_boards.containsKey(view)) _loadBoard(view);
  }

  Future<void> _play() async {
    if (_starting) return;
    // A day that ended while the button was on screen: fetch today's first.
    if (_today == null) {
      await _reload();
      return;
    }
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    HapticService.mediumImpact();
    setState(() => _starting = true);
    try {
      final start = await ChallengeApi.start(_newAttemptId());
      if (!mounted) return;
      await navigator.push(MaterialPageRoute(builder: (_) => ChallengePlayScreen(attempt: start)));
      if (mounted) await _reload();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.challengeStartFailed)));
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _openMyResult(ChallengeRanked ranked) async {
    try {
      final result = await ChallengeApi.attempt(ranked.id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChallengeResultScreen(result: result)));
    } catch (e) {
      debugPrint('ChallengeScreen: result failed: $e');
    }
  }

  Future<void> _toggleRemind(ChallengeToday today) async {
    final value = !today.remind;
    final l10n = AppLocalizations.of(context);
    HapticService.selectionClick();
    _store.patch(today.copyWith(remind: value));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(value ? l10n.challengeSRemindOn : l10n.challengeSRemindOff),
        duration: const Duration(seconds: 2),
      ));
    try {
      await ChallengeApi.setRemind(value);
    } catch (_) {
      final now = _store.today;
      if (now != null) _store.patch(now.copyWith(remind: !value));
    }
  }

  void _openLeaderboard(ChallengeToday today) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ChallengeLeaderboardScreen(today: today, initialView: _view, boards: Map.of(_boards)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final today = _today;
    final xp = maybeWatchProgression(context)?.content?.xp?.challenge ?? kChallengeDefaultXp;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: DsScreenHeader(
                title: l10n.challengeTitle,
                showBack: true,
                actions: [
                  if (today != null) ...[
                    ChallengeRemindBell(on: today.remind, onTap: () => _toggleRemind(today)),
                    ChallengeStreakPill(
                      days: today.streak.current,
                      onTap: () => ChallengeStreakSheet.show(context, today.streak),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: today == null
                  ? _buildEmpty(l10n)
                  : RefreshIndicator(
                      color: AppTheme.primary,
                      onRefresh: _reload,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        children: _buildDay(context, l10n, today, xp),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(AppLocalizations l10n) {
    if (!_failed) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.challengeLoadFailed, style: AppTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _reload, child: Text(l10n.challengeRetry)),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDay(BuildContext context, AppLocalizations l10n, ChallengeToday today, int xp) {
    final f = today.format;
    final ranked = today.ranked;
    final rankBoard = _boards[ChallengeView.rank];
    final rankRows = rankBoard?.rows ?? const <ChallengeRow>[];
    final shown = _boards[_view];
    final anyBoard = shown ?? (_boards.values.isEmpty ? null : _boards.values.first);
    return [
      ChallengeFormatCard(today: today, onRule: () => ChallengeRuleSheet.show(context, today, xp: xp)),
      const SizedBox(height: 12),
      if (ranked == null) ...[
        _ToBeatCard(
          format: f,
          leader: rankRows.isEmpty ? null : rankRows.first,
          // Not loaded (yet, or it failed) while someone played: a dash.
          unknown: rankBoard == null && today.board.players > 0,
        ),
        const SizedBox(height: 12),
        if (f.playable) _PlayButton(xp: xp, busy: _starting, onTap: _play) else const _UpdateAppNote(),
        const SizedBox(height: 8),
        Text(
          today.board.open
              ? l10n.challengeSPrizeLine(today.board.eloBonus, kChallengeTop10Xp)
              : l10n.challengeSNotOpen(today.board.players),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ChallengeColors.muted),
        ),
      ] else ...[
        _DuelCard(
          ranked: ranked,
          format: f,
          rows: rankRows,
          xp: xp,
          onTap: ranked.submitted ? () => _openMyResult(ranked) : null,
        ),
        const SizedBox(height: 12),
        if (f.playable) _PracticeButton(busy: _starting, onTap: _play) else const _UpdateAppNote(),
      ],
      const SizedBox(height: 16),
      _TopBoard(
        today: today,
        view: _view,
        board: shown,
        counts: anyBoard,
        loading: _loading.contains(_view),
        onView: _selectView,
        onAll: () => _openLeaderboard(today),
        onYesterday: today.yesterday == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ChallengePodiumScreen())),
      ),
    ];
  }
}

String _newAttemptId() {
  // RFC 4122 v4 — the server only checks the shape.
  final r = math.Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final h = List.generate(16, hex).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// « fin dans 14 h » / « fin dans 25 min »: whole hours, then minutes.
String challengeEndsInShort(AppLocalizations l10n, DateTime end) {
  final d = end.difference(DateTime.now());
  final left = d.inHours >= 1 ? l10n.challengeSHours(d.inHours) : l10n.challengeMinutes(math.max(0, d.inMinutes));
  return l10n.challengeEndsIn(left);
}

const _toBeatBorder = Color(0x7338BDF8); // rgba(56,189,248,.45)
const _meWash = Color(0x1F38BDF8); // rgba(56,189,248,.12)

/// The format in one line: small board, name, brief + ⓘ, « 1 essai · caméra
/// IA · fin dans 14 h ». The whole card opens the full rule.
class ChallengeFormatCard extends StatelessWidget {
  final ChallengeToday today;
  final VoidCallback onRule;
  const ChallengeFormatCard({super.key, required this.today, required this.onRule});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final f = today.format;
    final brief = f.brief?.resolve(context);
    final line = brief == null || brief.isEmpty ? f.short.resolve(context) : brief;
    final end = today.endsAt;
    return Semantics(
      button: true,
      hint: l10n.challengeSRuleLabel,
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onRule,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              children: [
                ChallengeMiniBoard(spec: f.board, size: 78, semanticLabel: line),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.name.resolve(context),
                        style: const TextStyle(fontSize: 20, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: line),
                            const WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Icon(Icons.info_outline_rounded, size: 16, color: AppTheme.textTertiary),
                              ),
                            ),
                          ],
                        ),
                        style: const TextStyle(fontSize: 14, height: 1.3, color: ChallengeColors.soft),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        end == null ? l10n.challengeSMeta : '${l10n.challengeSMeta} · ${challengeEndsInShort(l10n, end)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ChallengeColors.muted),
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
}

/// Before the ranked try: the score of the n°1 of my board, their avatar
/// and name; « Personne n'a encore joué » when the board is empty.
class _ToBeatCard extends StatelessWidget {
  final ChallengeFormat format;
  final ChallengeRow? leader;
  final bool unknown;
  const _ToBeatCard({required this.format, required this.leader, required this.unknown});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final leader = this.leader;
    final Widget body;
    if (leader == null && !unknown) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.challengeSNobodyYet, style: _label),
          const SizedBox(height: 4),
          Text(
            l10n.challengeSBeFirst,
            style: const TextStyle(fontSize: 30, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.6),
          ),
        ],
      );
    } else {
      final score = leader == null
          ? '—'
          : challengeScoreText(format, leader.score, finished: leader.finished, unfinished: l10n.challengeUnfinished);
      final unit = leader == null || score == l10n.challengeUnfinished ? '' : challengeUnit(context, format);
      body = Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.challengeSToBeat, style: _label),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        score,
                        style: const TextStyle(
                          fontSize: 52,
                          height: 1,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (unit.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(unit, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ChallengeColors.soft)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (leader != null) ...[
            const SizedBox(width: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      FramedAvatar(rank: leader.rank, cosmetics: leader.cosmetics, size: 48),
                      if (leader.crown)
                        Positioned(top: -9, child: PremiumCrown(size: 16, semanticLabel: l10n.challengeCrownLabel)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    leader.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ],
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _toBeatBorder, width: 1.5),
      ),
      child: body,
    );
  }

  static const _label = TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ChallengeColors.accentLight);
}

class _PlayButton extends StatelessWidget {
  final int xp;
  final bool busy;
  final VoidCallback onTap;
  const _PlayButton({required this.xp, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: ChallengeColors.accent,
          foregroundColor: AppTheme.background,
          disabledBackgroundColor: ChallengeColors.accent.withValues(alpha: 0.6),
          disabledForegroundColor: AppTheme.background,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: busy ? null : onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l10n.challengeSPlay, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            Text(l10n.homeXpGain(xp), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0C4A6E))),
          ],
        ),
      ),
    );
  }
}

class _PracticeButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onTap;
  const _PracticeButton({required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: ChallengeColors.text,
          side: const BorderSide(color: ChallengeColors.slate700, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        onPressed: busy ? null : onTap,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.repeat_rounded, size: 18),
            const SizedBox(width: 8),
            Text(l10n.challengeSPractice, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.challengeSOffBoard,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ChallengeColors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A format this version cannot play (a newer engine mode).
class _UpdateAppNote extends StatelessWidget {
  const _UpdateAppNote();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(AppLocalizations.of(context).challengeUpdateApp, style: AppTheme.bodyMedium, textAlign: TextAlign.center),
      );
}

/// After the ranked try (mockup DefB2): « Toi » against the n°1 of my board
/// (the n°2 when I am first; alone when nobody else played), then the XP
/// earned and « Revoir mon essai ». Opens my result.
class _DuelCard extends StatelessWidget {
  final ChallengeRanked ranked;
  final ChallengeFormat format;
  final List<ChallengeRow> rows;
  final int xp;
  final VoidCallback? onTap;
  const _DuelCard({required this.ranked, required this.format, required this.rows, required this.xp, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final others = rows.where((r) => !r.me).toList();
    final first = rows.isNotEmpty && rows.first.me;
    final rival = others.isEmpty ? null : others.first;

    final Widget mine;
    if (ranked.submitted) {
      mine = _DuelTile(
        label: l10n.challengeSYou,
        score: challengeScoreText(format, ranked.score ?? 0, finished: ranked.finished, unfinished: l10n.challengeUnfinished),
        sub: ranked.position != null && ranked.total != null
            ? l10n.challengeSPlace(challengeOrdinal(context, ranked.position!), ranked.total!)
            : null,
        mine: true,
      );
    } else {
      final text = ranked.excluded
          ? (ranked.excludedReason == 'rejected' ? l10n.challengeExcludedRejected : l10n.challengeExcluded)
          : l10n.challengeAbandoned;
      mine = _DuelTile(label: l10n.challengeSYou, note: text, mine: true);
    }

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: mine),
                    if (rival != null) ...[
                      const SizedBox(width: 8),
                      Center(
                        child: Text(
                          l10n.challengeSVs,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppTheme.textTertiary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _DuelTile(
                          label: first ? l10n.challengeSSecond : l10n.challengeSFirst,
                          score: challengeScoreText(format, rival.score, finished: rival.finished, unfinished: l10n.challengeUnfinished),
                          sub: rival.username,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!ranked.abandoned) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline_rounded, size: 15, color: ChallengeColors.success),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                l10n.challengeSXpEarned(xp),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ChallengeColors.success),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (ranked.submitted) ...[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  l10n.challengeSReview,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ChallengeColors.accentLight),
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.chevron_right_rounded, size: 16, color: ChallengeColors.accentLight),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DuelTile extends StatelessWidget {
  final String label;
  final String? score;
  final String? sub;
  final String? note;
  final bool mine;
  const _DuelTile({required this.label, this.score, this.sub, this.note, this.mine = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: mine ? _meWash : AppTheme.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: mine ? ChallengeColors.accentLight : ChallengeColors.muted,
            ),
          ),
          const SizedBox(height: 2),
          if (score != null)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                score!,
                style: const TextStyle(
                  fontSize: 44,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.3,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                note!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w600, color: ChallengeColors.soft),
              ),
            ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ChallengeColors.soft),
            ),
          ],
        ],
      ),
    );
  }
}

/// The top 5 of the selected view (+ my line, 6th, when I am further down),
/// then « Les N joueurs › » and « N°1 d'hier › ».
class _TopBoard extends StatelessWidget {
  final ChallengeToday today;
  final ChallengeView view;
  final ChallengeLeaderboard? board;

  /// Any loaded board, for the counts.
  final ChallengeLeaderboard? counts;
  final bool loading;
  final ValueChanged<ChallengeView> onView;
  final VoidCallback onAll;
  final VoidCallback? onYesterday;

  const _TopBoard({
    required this.today,
    required this.view,
    required this.board,
    required this.counts,
    required this.loading,
    required this.onView,
    required this.onAll,
    required this.onYesterday,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = board?.rows ?? const <ChallengeRow>[];
    final shown = rows.take(5).toList();
    final me = rows.where((r) => r.me).firstOrNull;
    if (me != null && !shown.contains(me)) shown.add(me);
    final count = switch (view) {
      ChallengeView.rank => counts?.countRank ?? today.board.players,
      ChallengeView.all => counts?.countAll ?? today.players,
      ChallengeView.friends => counts?.countFriends ?? 0,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(l10n.challengeSLeaderboard, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
            ChallengeSegmented(
              labels: [challengeBoardName(l10n, today.board.rank), l10n.challengeSAll, l10n.challengeSFriends],
              selected: view.index,
              onSelect: (i) => onView(ChallengeView.values[i]),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (board == null && loading)
          const SizedBox(
            height: 90,
            child: Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5)),
          )
        else if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(
              view == ChallengeView.friends ? l10n.challengeEmptyFriends : l10n.challengeSNoScores,
              style: AppTheme.caption.copyWith(fontSize: 13),
            ),
          )
        else
          for (final row in shown) ...[
            ChallengeCompactRow(row: row, format: today.format),
            const SizedBox(height: 6),
          ],
        SizedBox(
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (count > 0) Flexible(child: _FooterLink(label: l10n.challengeSPlayers(count), onTap: onAll)) else const SizedBox(),
              if (onYesterday != null) ...[
                const SizedBox(width: 12),
                Flexible(child: _FooterLink(label: l10n.challengeSYesterday, onTap: onYesterday!)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _FooterLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ChallengeColors.accentLight),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right_rounded, size: 16, color: ChallengeColors.accentLight),
          ],
        ),
      ),
    );
  }
}

/// The short segmented control of the top 5 (rank name, All, Friends).
class ChallengeSegmented extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const ChallengeSegmented({super.key, required this.labels, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            Semantics(
              selected: i == selected,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onSelect(i),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? ChallengeColors.slate700 : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: i == selected ? ChallengeColors.text : ChallengeColors.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A 42 pt line of the top 5: place (1 in gold), the player's rank, name,
/// score. Mine is washed in blue.
class ChallengeCompactRow extends StatelessWidget {
  final ChallengeRow row;
  final ChallengeFormat? format;
  const ChallengeCompactRow({super.key, required this.row, this.format});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: row.me ? _meWash : AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: row.me ? _toBeatBorder : Colors.transparent),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${row.position}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: row.position == 1 ? ChallengeColors.crown : ChallengeColors.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          RankUtils.getRankBadge(row.rank, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.me ? l10n.challengeSMeRow(row.username) : row.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            challengeScoreText(format, row.score, finished: row.finished, unfinished: l10n.challengeUnfinished),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

/// ⓘ of the format card: everything the screen no longer spells out.
class ChallengeRuleSheet extends StatelessWidget {
  final ChallengeToday today;
  final int xp;
  const ChallengeRuleSheet({super.key, required this.today, required this.xp});

  static Future<void> show(BuildContext context, ChallengeToday today, {required int xp}) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppTheme.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => ChallengeRuleSheet(today: today, xp: xp),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final f = today.format;
    final board = today.board;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.challengeSRuleLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ChallengeColors.accentLight)),
              const SizedBox(height: 4),
              Text(f.name.resolve(context), style: const TextStyle(fontSize: 22, height: 1.15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Text(f.rule.resolve(context), style: const TextStyle(fontSize: 15, height: 1.45, color: ChallengeColors.soft)),
              const SizedBox(height: 16),
              _SheetLine(icon: Icons.looks_one_outlined, text: l10n.challengeSRuleOneTry),
              _SheetLine(icon: Icons.videocam_outlined, text: l10n.challengeSRuleCamera),
              const SizedBox(height: 10),
              Text(l10n.challengeSRewardsTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              _SheetLine(icon: Icons.add_circle_outline_rounded, text: l10n.challengeSRewardPlay(xp)),
              _SheetLine(icon: Icons.trending_up_rounded, text: l10n.challengeSRewardTop10(kChallengeTop10Xp)),
              _SheetLine(
                leading: const PremiumCrown(size: 18),
                text: '${l10n.challengePrizeRank(challengeBoardName(l10n, board.rank))} ${l10n.challengePrizeReward(board.eloBonus)}',
              ),
              if (!board.open)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(l10n.challengeBoardNotOpen(board.players), style: AppTheme.caption.copyWith(fontSize: 13)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetLine extends StatelessWidget {
  final IconData? icon;
  final Widget? leading;
  final String text;
  const _SheetLine({this.icon, this.leading, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: leading ?? Icon(icon, size: 19, color: ChallengeColors.accentLight),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4, color: ChallengeColors.softer))),
        ],
      ),
    );
  }
}

/// The streak pill of the header: the week and the freeze.
class ChallengeStreakSheet extends StatelessWidget {
  final ChallengeStreak streak;
  const ChallengeStreakSheet({super.key, required this.streak});

  static Future<void> show(BuildContext context, ChallengeStreak streak) => showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppTheme.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => ChallengeStreakSheet(streak: streak),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: _StreakBlock(streak: streak),
        ),
      );
}

class _StreakBlock extends StatelessWidget {
  final ChallengeStreak streak;
  const _StreakBlock({required this.streak});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Text(l10n.challengeYourStreak, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            const Icon(Icons.ac_unit_rounded, size: 15, color: ChallengeColors.accentLight),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                streak.freezeAvailable ? l10n.challengeFreezeAvailable : l10n.challengeFreezeUsed,
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChallengeColors.soft),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final d in streak.days)
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: d.played ? ChallengeColors.accent : (d.today ? Colors.transparent : AppTheme.background),
                        border: d.today && !d.played ? Border.all(color: ChallengeColors.accent, width: 2) : null,
                      ),
                      child: d.played ? const Icon(Icons.check_rounded, size: 18, color: AppTheme.background) : null,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _weekdayLetter(d.date, locale),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ChallengeColors.muted),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  static String _weekdayLetter(String date, String locale) {
    final d = DateTime.tryParse(date);
    if (d == null) return '';
    const fr = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    const en = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return (locale.startsWith('fr') ? fr : en)[d.weekday - 1];
  }
}

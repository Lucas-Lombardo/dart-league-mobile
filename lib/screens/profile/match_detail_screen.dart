import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friends_provider.dart';
import '../../services/match_service.dart';
import '../../models/match.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/notification_service.dart';
import '../../widgets/design_system.dart';
import '../../widgets/premium_badge.dart';
import '../../widgets/recent_matches_widget.dart';
import '../../l10n/app_localizations.dart';
import 'replay_library_screen.dart';

/// One match: summary card (result, the two players in their in-match
/// colours, score, context line), the friend action, the legs of a BO3, the
/// duel of figures and the round-by-round table.
class MatchDetailScreen extends StatefulWidget {
  final String matchId;

  const MatchDetailScreen({super.key, required this.matchId});

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen> {
  Match? _match;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMatchDetail();
  }

  Future<void> _loadMatchDetail() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final userId = auth.currentUser?.id ?? '';

      final response = await MatchService.getMatchDetail(widget.matchId);
      final match = Match.fromJson(response, userId);
      setState(() {
        _match = match;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final userId = auth.currentUser?.id ?? '';
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.matchDetails)),
      body: _buildBody(l10n, userId),
    );
  }

  Widget _buildBody(AppLocalizations l10n, String userId) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: DsCard(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          child: Column(
            children: [
              const Icon(Icons.error_outline_rounded, size: 32, color: AppTheme.textTertiary),
              const SizedBox(height: 12),
              Text(
                l10n.errorWithMessage.replaceAll('{message}', _error ?? ''),
                textAlign: TextAlign.center,
                style: AppTheme.rowTitle,
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _loadMatchDetail, child: Text(l10n.retry)),
            ],
          ),
        ),
      );
    }
    final match = _match;
    if (match == null) {
      return Center(child: Text(l10n.matchNotFound, style: AppTheme.bodyMedium));
    }

    final series = match.series;
    final rounds = match.rounds;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MatchSummaryCard(match: match, userId: userId),
          _FriendAction(match: match, userId: userId),
          if (series != null) ...[
            const SizedBox(height: 28),
            DsSectionHeader(title: dsSentence(l10n.bestOfN(series.bestOf))),
            const SizedBox(height: 12),
            _LegsCard(match: match, userId: userId, currentLegId: widget.matchId),
          ],
          if (match.statistics != null) ...[
            const SizedBox(height: 14),
            MatchDuelStatsCard(match: match, userId: userId),
          ],
          if (rounds != null && rounds.isNotEmpty) ...[
            const SizedBox(height: 28),
            DsSectionHeader(title: l10n.roundHistory),
            const SizedBox(height: 12),
            _RoundsCard(match: match, userId: userId),
          ],
          const SizedBox(height: 20),
          Center(
            child: TextButton.icon(
              onPressed: () => AppNavigator.toScreen(context, const ReplayLibraryScreen()),
              style: TextButton.styleFrom(
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              icon: const Icon(Icons.movie_outlined, size: 18),
              label: Text(l10n.myReplays),
            ),
          ),
        ],
      ),
    );
  }
}

/// The summary: a result pill and the ELO delta, then me (blue) and the
/// opponent (rose) around the score — legs won for a series, 501 remainders
/// otherwise — and the "Classé · Au meilleur de 3 · date" line.
class MatchSummaryCard extends StatelessWidget {
  final Match match;
  final String userId;

  const MatchSummaryCard({super.key, required this.match, required this.userId});

  static String _longDate(BuildContext context, DateTime when) {
    final at = when.toLocal();
    try {
      return DateFormat('EEEE d MMMM y, HH:mm', Localizations.localeOf(context).languageCode).format(at);
    } catch (_) {
      return DateFormat('d MMM y, HH:mm').format(at);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inProgress = match.isInProgress;
    final isWin = match.isWinner(userId);
    final eloChange = match.getEloChange(userId);
    final isPlacement = match.isPlacement;
    final opponent = isPlacement
        ? l10n.botWithAvg((match.botDifficulty ?? 1) * 10)
        : match.getOpponentUsername(userId);
    final opponentIsPremium = !isPlacement && match.getOpponentIsPremium(userId);
    final series = match.series;
    final iAmPlayer1 = userId == match.player1Id;
    final myScore = series != null
        ? (iAmPlayer1 ? series.player1LegsWon : series.player2LegsWon)
        : match.getMyScore(userId);
    final oppScore = series != null
        ? (iAmPlayer1 ? series.player2LegsWon : series.player1LegsWon)
        : match.getOpponentScore(userId);
    final showDelta = !inProgress && !isPlacement && (eloChange != 0 || match.matchType == 'ranked');
    final deltaColor = eloChange >= 0 ? AppTheme.success : AppTheme.error;
    final (String resultLabel, Color resultColor) = inProgress
        ? (dsSentence(l10n.matchStatusInProgress), AppTheme.primaryLight)
        : isWin
            ? (dsSentence(l10n.win), AppTheme.success)
            : (dsSentence(l10n.loss), AppTheme.error);
    final details = [
      MatchRowTile.kindLabel(l10n, match),
      if (series != null) dsSentence(l10n.bestOfN(series.bestOf)),
      _longDate(context, match.createdAt),
    ].join(' · ');

    const scoreStyle = TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w800,
      height: 1,
      letterSpacing: -0.5,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    return DsCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DsPill(label: resultLabel, color: resultColor),
              const Spacer(),
              if (showDelta)
                Text(
                  '${eloChange >= 0 ? '+' : ''}$eloChange ${l10n.eloLabel}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: deltaColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _PlayerName(
                  name: l10n.youLabel,
                  isPremium: false,
                  color: AppTheme.playerBlueBright,
                  alignEnd: false,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text.rich(
                  TextSpan(
                    style: scoreStyle,
                    children: [
                      TextSpan(text: '$myScore', style: const TextStyle(color: AppTheme.playerBlueBright)),
                      const TextSpan(text: ' – ', style: TextStyle(color: AppTheme.textTertiary)),
                      TextSpan(text: '$oppScore', style: const TextStyle(color: AppTheme.opponentPinkBright)),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: _PlayerName(
                  name: opponent,
                  isPremium: opponentIsPremium,
                  color: AppTheme.opponentPinkBright,
                  alignEnd: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            details,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption,
          ),
        ],
      ),
    );
  }
}

/// A player's name in its identity colour, the premium crown after it.
class _PlayerName extends StatelessWidget {
  final String name;
  final bool isPremium;
  final Color color;
  final bool alignEnd;

  const _PlayerName({
    required this.name,
    required this.isPremium,
    required this.color,
    required this.alignEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.end : TextAlign.start,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color),
          ),
        ),
        PremiumBadge(isPremium: isPremium, size: 12, color: AppTheme.accent),
      ],
    );
  }
}

/// Add the opponent as a friend from the match (or nothing when they already
/// are, or when the opponent was a bot). A request already sent either way
/// shows as a disabled "En attente".
class _FriendAction extends StatefulWidget {
  final Match match;
  final String userId;

  const _FriendAction({required this.match, required this.userId});

  @override
  State<_FriendAction> createState() => _FriendActionState();
}

class _FriendActionState extends State<_FriendAction> {
  bool _busy = false;

  Future<void> _sendRequest(String friendId, String username) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await context.read<FriendsProvider>().sendFriendRequest(friendId);
      if (mounted) {
        NotificationService.showSuccess(
          context,
          l10n.friendRequestSent.replaceAll('{username}', username),
        );
      }
    } catch (e) {
      if (mounted) {
        NotificationService.showError(context, e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final opponentId = match.getOpponentId(widget.userId);
    if (match.isPlacement || match.matchType == 'bot' || opponentId.isEmpty || opponentId == widget.userId) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final status = context.watch<FriendsProvider>().getFriendshipStatus(opponentId);
    if (status == 'friends') return const SizedBox.shrink();

    final pending = status == 'pending_sent' || status == 'pending_received';
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: OutlinedButton.icon(
        onPressed: pending || _busy
            ? null
            : () => _sendRequest(opponentId, match.getOpponentUsername(widget.userId)),
        icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
        label: Text(pending ? l10n.pendingStatus : l10n.addFriendButton),
      ),
    );
  }
}

/// The legs of a BO3, one row each: number, result score coloured by who
/// took it, a chevron on the legs that open their own detail. The leg being
/// displayed reads in primaryLight and stays put.
class _LegsCard extends StatelessWidget {
  final Match match;
  final String userId;
  final String currentLegId;

  const _LegsCard({required this.match, required this.userId, required this.currentLegId});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final legs = match.series!.legs;
    final iAmPlayer1 = userId == match.player1Id;

    return DsCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < legs.length; i++) ...[
            if (i > 0) const Divider(indent: 16, endIndent: 16),
            _legRow(context, l10n, legs[i], iAmPlayer1),
          ],
        ],
      ),
    );
  }

  Widget _legRow(BuildContext context, AppLocalizations l10n, SeriesLeg leg, bool iAmPlayer1) {
    final isCurrent = leg.id == currentLegId;
    final iWonLeg = leg.winnerId != null && leg.winnerId == userId;
    final finished = leg.status == 'finished' || leg.status == 'forfeit';
    final myScore = iAmPlayer1 ? leg.player1Score : leg.player2Score;
    final oppScore = iAmPlayer1 ? leg.player2Score : leg.player1Score;

    return InkWell(
      onTap: isCurrent
          ? null
          : () => AppNavigator.toScreen(context, MatchDetailScreen(matchId: leg.id)),
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.legNumber(leg.legNumber),
                  style: AppTheme.rowTitle.copyWith(
                    color: isCurrent ? AppTheme.primaryLight : AppTheme.textPrimary,
                  ),
                ),
              ),
              if (finished)
                Text(
                  '${myScore ?? '—'} – ${oppScore ?? '—'}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: iWonLeg ? AppTheme.success : AppTheme.error,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                )
              else
                const Icon(Icons.hourglass_empty_rounded, size: 16, color: AppTheme.textTertiary),
              if (!isCurrent) ...[
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textTertiary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The figures of the match, me against the opponent, in the same duel
/// layout as the end-of-match card: my value left in bright blue, theirs
/// right in bright rose, the label between, a 4 px two-tone bar split in
/// proportion. Fed by the match's own statistics, no extra request.
class MatchDuelStatsCard extends StatelessWidget {
  final Match match;
  final String userId;

  const MatchDuelStatsCard({super.key, required this.match, required this.userId});

  @override
  Widget build(BuildContext context) {
    final stats = match.statistics;
    if (stats == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final isPlayer1 = userId == match.player1Id;
    final me = isPlayer1 ? stats.player1 : stats.player2;
    final them = isPlayer1 ? stats.player2 : stats.player1;
    final opponent = match.isPlacement
        ? l10n.botWithAvg((match.botDifficulty ?? 1) * 10)
        : match.getOpponentUsername(userId);

    return DsCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(l10n.matchStatistics, style: AppTheme.sectionTitle)),
              _Legend(label: l10n.youLabel, color: AppTheme.playerBlueDim),
              const SizedBox(width: 12),
              Flexible(
                child: _Legend(
                  label: opponent.isEmpty ? '—' : opponent,
                  color: AppTheme.opponentPink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _DuelRow(label: l10n.avgScoreRound, mine: me.average, theirs: them.average),
          _DuelRow(
            label: l10n.highestRound,
            mine: me.highest.toDouble(),
            theirs: them.highest.toDouble(),
            decimals: 0,
          ),
          _DuelRow(
            label: l10n.perfect180s,
            mine: me.total180s.toDouble(),
            theirs: them.total180s.toDouble(),
            decimals: 0,
          ),
          _DuelRow(
            label: l10n.finishingDoubles,
            mine: me.doublePercentage,
            theirs: them.doublePercentage,
            suffix: ' %',
          ),
          _DuelRow(
            label: l10n.bestCheckout,
            mine: me.checkout > 0 ? me.checkout.toDouble() : null,
            theirs: them.checkout > 0 ? them.checkout.toDouble() : null,
            decimals: 0,
            showBars: false,
          ),
          _DuelRow(
            label: l10n.totalRounds,
            mine: me.rounds.toDouble(),
            theirs: them.rounds.toDouble(),
            decimals: 0,
            showBars: false,
          ),
        ],
      ),
    );
  }
}

String _format(double value) =>
    value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

/// "● Vous" / "● DODO180": 7 px identity dot + 11 / 600 secondary label.
class _Legend extends StatelessWidget {
  final String label;
  final Color color;

  const _Legend({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
        ),
      ],
    );
  }
}

class _DuelRow extends StatelessWidget {
  final String label;
  final double? mine;
  final double? theirs;
  final int decimals;
  final String suffix;
  final bool showBars;

  const _DuelRow({
    required this.label,
    required this.mine,
    required this.theirs,
    this.decimals = 1,
    this.suffix = '',
    this.showBars = true,
  });

  String _value(double? value) {
    if (value == null) return '—';
    final text = decimals == 0 ? value.toStringAsFixed(0) : _format(value);
    return '$text$suffix';
  }

  Widget _side({required bool mine}) {
    final value = mine ? this.mine : theirs;
    return SizedBox(
      width: 70,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
        child: Text(
          _value(value),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: mine ? AppTheme.playerBlueBright : AppTheme.opponentPinkBright,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = mine ?? 0;
    final b = theirs ?? 0;
    final total = a + b;
    final mineFlex = total > 0 ? (a / total * 1000).round() : 500;
    final theirsFlex = total > 0 ? (b / total * 1000).round() : 500;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _side(mine: true),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              _side(mine: false),
            ],
          ),
          if (showBars) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 4,
              child: Row(
                children: [
                  Expanded(
                    flex: mineFlex.clamp(1, 1000),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.playerBlueDim,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: theirsFlex.clamp(1, 1000),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.opponentPink.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Round by round: the number, my visit (score over the three darts) in
/// blue, the opponent's in rose, one hairline between rounds.
class _RoundsCard extends StatelessWidget {
  final Match match;
  final String userId;

  const _RoundsCard({required this.match, required this.userId});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rounds = match.rounds!;
    final roundNumbers = rounds.map((r) => r.roundNumber).toSet().toList()..sort();
    final opponent = match.isPlacement
        ? l10n.botWithAvg((match.botDifficulty ?? 1) * 10)
        : match.getOpponentUsername(userId);

    return DsCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(width: 56),
              Expanded(child: _Legend(label: l10n.youLabel, color: AppTheme.playerBlueDim)),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _Legend(label: opponent.isEmpty ? '—' : opponent, color: AppTheme.opponentPink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final roundNum in roundNumbers) ...[
            const Divider(),
            _roundRow(
              l10n,
              roundNum,
              rounds.firstWhere(
                (r) => r.roundNumber == roundNum && r.playerId == userId,
                orElse: () => MatchRound(roundNumber: roundNum, playerId: '', throws: [], roundScore: 0),
              ),
              rounds.firstWhere(
                (r) => r.roundNumber == roundNum && r.playerId != userId,
                orElse: () => MatchRound(roundNumber: roundNum, playerId: '', throws: [], roundScore: 0),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _roundRow(AppLocalizations l10n, int number, MatchRound mine, MatchRound theirs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(
              dsSentence(l10n.roundLabel.replaceAll('{number}', '$number')),
              style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: _visit(mine, AppTheme.playerBlueBright, alignEnd: false)),
          Expanded(child: _visit(theirs, AppTheme.opponentPinkBright, alignEnd: true)),
        ],
      ),
    );
  }

  Widget _visit(MatchRound round, Color color, {required bool alignEnd}) {
    return Column(
      crossAxisAlignment: alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          '${round.roundScore}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.1,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (round.throws.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            round.throws.join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppTheme.textTertiary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
  }
}

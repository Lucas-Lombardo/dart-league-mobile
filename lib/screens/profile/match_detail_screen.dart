import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../services/match_service.dart';
import '../../models/match.dart';
import '../../utils/app_theme.dart';
import '../../widgets/premium_badge.dart';
import '../../l10n/app_localizations.dart';

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

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).matchDetails),
        backgroundColor: AppTheme.surface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: AppTheme.error),
                      const SizedBox(height: 16),
                      Text(AppLocalizations.of(context).errorWithMessage.replaceAll('{message}', _error ?? ''), style: const TextStyle(color: AppTheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadMatchDetail,
                        child: Text(AppLocalizations.of(context).retry),
                      ),
                    ],
                  ),
                )
              : _match == null
                  ? Center(child: Text(AppLocalizations.of(context).matchNotFound))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildMatchHeader(_match!, userId),
                          if (_match!.series != null) ...[
                            const SizedBox(height: 24),
                            _buildSeriesCard(_match!, userId),
                          ],
                          const SizedBox(height: 24),
                          _buildScoreCard(_match!, userId),
                          const SizedBox(height: 24),
                          _buildMatchStats(_match!, userId),
                          if (_match!.rounds != null && _match!.rounds!.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _buildRoundHistory(_match!, userId),
                          ],
                        ],
                      ),
                    ),
    );
  }

  Widget _buildMatchHeader(Match match, String userId) {
    final isWin = match.isWinner(userId);
    final eloChange = match.getEloChange(userId);
    final dateFormat = DateFormat('EEEE, MMMM d, y • h:mm a');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isWin
              ? [AppTheme.success.withValues(alpha: 0.2), AppTheme.success.withValues(alpha: 0.05)]
              : [AppTheme.error.withValues(alpha: 0.2), AppTheme.error.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isWin ? AppTheme.success : AppTheme.error,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: isWin ? AppTheme.success : AppTheme.error,
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              isWin ? AppLocalizations.of(context).victoryEmoji : AppLocalizations.of(context).defeatEmoji,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                AppLocalizations.of(context).eloChange,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: (eloChange >= 0 ? AppTheme.success : AppTheme.error).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${eloChange >= 0 ? '+' : ''}$eloChange',
                  style: TextStyle(
                    color: eloChange >= 0 ? AppTheme.success : AppTheme.error,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            dateFormat.format(match.createdAt),
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// BO3 series breakdown: series score in legs + one result row per leg.
  /// The leg currently displayed is highlighted; the others open their own
  /// detail screen (each leg is a full match with rounds and stats).
  Widget _buildSeriesCard(Match match, String userId) {
    final l10n = AppLocalizations.of(context);
    final series = match.series!;
    final iAmPlayer1 = userId == match.player1Id;
    final myLegs = iAmPlayer1 ? series.player1LegsWon : series.player2LegsWon;
    final oppLegs = iAmPlayer1 ? series.player2LegsWon : series.player1LegsWon;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  l10n.bestOfN(series.bestOf).toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$myLegs – $oppLegs',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...series.legs.map((leg) => _buildLegRow(match, leg, userId)),
        ],
      ),
    );
  }

  Widget _buildLegRow(Match match, SeriesLeg leg, String userId) {
    final l10n = AppLocalizations.of(context);
    final iAmPlayer1 = userId == match.player1Id;
    final isCurrent = leg.id == widget.matchId;
    final iWonLeg = leg.winnerId != null && leg.winnerId == userId;
    final finished = leg.status == 'finished' || leg.status == 'forfeit';
    final myScore = iAmPlayer1 ? leg.player1Score : leg.player2Score;
    final oppScore = iAmPlayer1 ? leg.player2Score : leg.player1Score;

    final row = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isCurrent ? AppTheme.primary.withValues(alpha: 0.12) : AppTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent
              ? AppTheme.primary
              : AppTheme.surfaceLight.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Text(
            l10n.legNumber(leg.legNumber),
            style: TextStyle(
              color: isCurrent ? AppTheme.primary : AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (finished) ...[
            Icon(
              iWonLeg ? Icons.emoji_events : Icons.close,
              color: iWonLeg ? AppTheme.success : AppTheme.error,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              '${myScore ?? '—'} – ${oppScore ?? '—'}',
              style: TextStyle(
                color: iWonLeg ? AppTheme.success : AppTheme.error,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ] else
            const Icon(Icons.hourglass_empty, color: AppTheme.textSecondary, size: 16),
          if (!isCurrent) ...[
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 18),
          ],
        ],
      ),
    );

    if (isCurrent) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MatchDetailScreen(matchId: leg.id),
          ),
        );
      },
      child: row,
    );
  }

  Widget _buildScoreCard(Match match, String userId) {
    final myScore = match.getMyScore(userId);
    final opponentScore = match.getOpponentScore(userId);
    final opponentUsername = match.getOpponentUsername(userId);
    final opponentIsPremium = !match.isPlacement && match.getOpponentIsPremium(userId);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(
            child: _buildPlayerInfo(AppLocalizations.of(context).you.toUpperCase(), myScore, true),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              AppLocalizations.of(context).vs,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: _buildPlayerInfo(opponentUsername, opponentScore, false, isPremium: opponentIsPremium),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerInfo(String name, int score, bool isMe, {bool isPremium = false}) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                name,
                style: TextStyle(
                  color: isMe ? AppTheme.primary : Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            PremiumBadge(isPremium: isPremium, size: 14),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '$score',
          style: TextStyle(
            color: isMe ? AppTheme.primary : Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildMatchStats(Match match, String userId) {
    // Use statistics from backend if available
    if (match.statistics == null) return const SizedBox.shrink();

    final stats = match.statistics!;
    final isPlayer1 = userId == match.player1Id;
    final myStats = isPlayer1 ? stats.player1 : stats.player2;
    final opponentStats = isPlayer1 ? stats.player2 : stats.player1;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).matchStatistics,
            style: AppTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          _buildStatRow(AppLocalizations.of(context).totalRounds, '${myStats.rounds}', '${opponentStats.rounds}'),
          const Divider(height: 24, color: AppTheme.surfaceLight),
          _buildStatRow(
            AppLocalizations.of(context).avgScoreRound,
            myStats.average.toStringAsFixed(1),
            opponentStats.average.toStringAsFixed(1),
          ),
          const Divider(height: 24, color: AppTheme.surfaceLight),
          _buildStatRow(AppLocalizations.of(context).highestRound, '${myStats.highest}', '${opponentStats.highest}'),
          const Divider(height: 24, color: AppTheme.surfaceLight),
          _buildStatRow(AppLocalizations.of(context).perfect180s, '${myStats.total180s}', '${opponentStats.total180s}'),
          const Divider(height: 24, color: AppTheme.surfaceLight),
          _buildStatRow(
            AppLocalizations.of(context).bestCheckout,
            myStats.checkout > 0 ? '${myStats.checkout}' : '—',
            opponentStats.checkout > 0 ? '${opponentStats.checkout}' : '—',
          ),
          const Divider(height: 24, color: AppTheme.surfaceLight),
          _buildStatRow(
            AppLocalizations.of(context).finishingDoubles,
            '${myStats.doublePercentage.toStringAsFixed(1)}%',
            '${opponentStats.doublePercentage.toStringAsFixed(1)}%',
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String myValue, String opponentValue) {
    return Row(
      children: [
        Expanded(
          child: Text(
            myValue,
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: Text(
            opponentValue,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildRoundHistory(Match match, String userId) {
    final rounds = match.rounds!;
    final roundNumbers = rounds.map((r) => r.roundNumber).toSet().toList()..sort();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocalizations.of(context).roundHistory,
            style: AppTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          ...roundNumbers.map((roundNum) {
            final myRound = rounds.firstWhere(
              (r) => r.roundNumber == roundNum && r.playerId == userId,
              orElse: () => MatchRound(roundNumber: roundNum, playerId: '', throws: [], roundScore: 0),
            );
            final opponentRound = rounds.firstWhere(
              (r) => r.roundNumber == roundNum && r.playerId != userId,
              orElse: () => MatchRound(roundNumber: roundNum, playerId: '', throws: [], roundScore: 0),
            );

            return _buildRoundCard(roundNum, myRound, opponentRound);
          }),
        ],
      ),
    );
  }

  Widget _buildRoundCard(int roundNumber, MatchRound myRound, MatchRound opponentRound) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            AppLocalizations.of(context).roundLabel.replaceAll('{number}', roundNumber.toString()),
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      myRound.throws.join(' • '),
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${myRound.roundScore}',
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 30,
                color: AppTheme.surfaceLight,
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      opponentRound.throws.join(' • '),
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${opponentRound.roundScore}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

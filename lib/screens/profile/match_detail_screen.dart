import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../services/user_service.dart';
import '../../models/match.dart';

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
      final match = await UserService.getMatchDetail(widget.matchId);
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
      appBar: AppBar(
        title: const Text('Match Details'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF)))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadMatchDetail,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _match == null
                  ? const Center(child: Text('Match not found'))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildMatchHeader(_match!, userId),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isWin
              ? [Colors.green.withValues(alpha: 0.3), Colors.green.withValues(alpha: 0.1)]
              : [Colors.red.withValues(alpha: 0.3), Colors.red.withValues(alpha: 0.1)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isWin ? Colors.green : Colors.red,
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isWin ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              isWin ? '🏆 VICTORY' : '💔 DEFEAT',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'ELO Change: ',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: eloChange >= 0
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.red.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${eloChange >= 0 ? '+' : ''}$eloChange',
                  style: TextStyle(
                    color: eloChange >= 0 ? Colors.green : Colors.red,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            dateFormat.format(match.createdAt),
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCard(Match match, String userId) {
    final myScore = match.getMyScore(userId);
    final opponentScore = match.getOpponentScore(userId);
    final opponentUsername = match.getOpponentUsername(userId);
    final isWin = match.isWinner(userId);
    final auth = context.read<AuthProvider>();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00E5FF)),
      ),
      child: Column(
        children: [
          const Text(
            'Final Score',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: Column(
                  children: [
                    Text(
                      auth.currentUser?.username ?? 'You',
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$myScore',
                      style: TextStyle(
                        color: isWin ? Colors.green : Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'vs',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      opponentUsername,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$opponentScore',
                      style: TextStyle(
                        color: !isWin ? Colors.red : Colors.white,
                        fontSize: 48,
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

  Widget _buildMatchStats(Match match, String userId) {
    final rounds = match.rounds ?? [];
    final myRounds = rounds.where((r) => r.playerId == userId).toList();
    final opponentRounds = rounds.where((r) => r.playerId != userId).toList();

    final myAvgScore = myRounds.isEmpty
        ? 0.0
        : myRounds.map((r) => r.roundScore).reduce((a, b) => a + b) / myRounds.length;
    final opponentAvgScore = opponentRounds.isEmpty
        ? 0.0
        : opponentRounds.map((r) => r.roundScore).reduce((a, b) => a + b) / opponentRounds.length;

    final myHighestRound = myRounds.isEmpty ? 0 : myRounds.map((r) => r.roundScore).reduce((a, b) => a > b ? a : b);
    final opponentHighestRound = opponentRounds.isEmpty
        ? 0
        : opponentRounds.map((r) => r.roundScore).reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Match Statistics',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _buildStatRow('Total Rounds', '${rounds.length ~/ 2}', '${rounds.length ~/ 2}'),
          const SizedBox(height: 12),
          _buildStatRow(
            'Average Score/Round',
            myAvgScore.toStringAsFixed(1),
            opponentAvgScore.toStringAsFixed(1),
          ),
          const SizedBox(height: 12),
          _buildStatRow('Highest Round', '$myHighestRound', '$opponentHighestRound'),
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
              color: Color(0xFF00E5FF),
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          child: Text(
            opponentValue,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
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
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Round History',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
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
        color: const Color(0xFF0A0A0A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          Text(
            'Round $roundNumber',
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 14,
              fontWeight: FontWeight.bold,
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
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${myRound.roundScore} pts',
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white12,
                margin: const EdgeInsets.symmetric(horizontal: 16),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      opponentRound.throws.join(' • '),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${opponentRound.roundScore} pts',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
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

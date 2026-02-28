import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/friends_provider.dart';
import '../../services/user_service.dart';
import '../../models/match.dart';
import '../../l10n/app_localizations.dart';
import 'match_detail_screen.dart';
import '../../utils/app_theme.dart';

class MatchHistoryScreen extends StatefulWidget {
  const MatchHistoryScreen({super.key});

  @override
  State<MatchHistoryScreen> createState() => _MatchHistoryScreenState();
}

class _MatchHistoryScreenState extends State<MatchHistoryScreen> {
  List<Match> _matches = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadMatches();
  }

  Future<void> _loadMatches() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final userId = auth.currentUser?.id;

      if (userId != null) {
        final matches = await UserService.getUserMatches(userId);
        setState(() {
          _matches = matches;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _sendFriendRequest(String friendId, String username) async {
    final l10n = AppLocalizations.of(context);
    try {
      await context.read<FriendsProvider>().sendFriendRequest(friendId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.friendRequestSent.replaceAll('{username}', username)),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final userId = auth.currentUser?.id ?? '';
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.matchHistoryTitle),
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
                      Text(
                        'Error: $_error', style: const TextStyle(color: AppTheme.error)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadMatches,
                        child: Text(l10n.retry),
                      ),
                    ],
                  ),
                )
              : _matches.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 64, color: AppTheme.textSecondary),
                          const SizedBox(height: 16),
                          Text(
                            l10n.noMatchesYet,
                            style: AppTheme.titleLarge.copyWith(color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.playGameToSeeHistory,
                            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadMatches,
                      color: AppTheme.primary,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _matches.length,
                        itemBuilder: (context, index) {
                          final match = _matches[index];
                          return _buildMatchCard(match, userId);
                        },
                      ),
                    ),
    );
  }

  Widget _buildMatchCard(Match match, String userId) {
    final l10n = AppLocalizations.of(context);
    final isWin = match.isWinner(userId);
    final eloChange = match.getEloChange(userId);
    final opponentUsername = match.getOpponentUsername(userId);
    final myScore = match.getMyScore(userId);
    final opponentScore = match.getOpponentScore(userId);
    final dateFormat = DateFormat('MMM d, y • h:mm a');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isWin 
              ? AppTheme.success.withValues(alpha: 0.3) 
              : AppTheme.error.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => MatchDetailScreen(matchId: match.id),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: isWin ? AppTheme.success.withValues(alpha: 0.1) : AppTheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isWin ? AppTheme.success : AppTheme.error,
                        ),
                      ),
                      child: Text(
                        isWin ? l10n.win.toUpperCase() : l10n.loss.toUpperCase(),
                        style: TextStyle(
                          color: isWin ? AppTheme.success : AppTheme.error,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${l10n.vs} $opponentUsername',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (eloChange >= 0 ? AppTheme.success : AppTheme.error).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${eloChange >= 0 ? '+' : ''}$eloChange',
                        style: TextStyle(
                          color: eloChange >= 0 ? AppTheme.success : AppTheme.error,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildScoreColumn(l10n.youLabel, '$myScore', AppTheme.primary),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        '-',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _buildScoreColumn(l10n.opponentLabel, '$opponentScore', Colors.white),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      dateFormat.format(match.createdAt),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    Consumer<FriendsProvider>(
                      builder: (context, friendsProvider, _) {
                        final opponentId = match.getOpponentId(userId);
                        final isFriend = friendsProvider.isFriend(opponentId);
                        
                        if (isFriend) {
                          return Row(
                            children: [
                              Icon(Icons.check_circle, color: AppTheme.success, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                l10n.friendsStatus,
                                style: TextStyle(color: AppTheme.success, fontSize: 12),
                              ),
                            ],
                          );
                        }
                        
                        return TextButton.icon(
                          onPressed: () => _sendFriendRequest(opponentId, opponentUsername),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          ),
                          icon: const Icon(Icons.person_add, size: 16),
                          label: Text(l10n.addFriendButton, style: const TextStyle(fontSize: 12)),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScoreColumn(String label, String score, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          score,
          style: TextStyle(
            color: color,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

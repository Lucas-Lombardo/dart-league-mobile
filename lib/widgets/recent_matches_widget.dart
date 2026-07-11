import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/match.dart';
import '../screens/profile/match_detail_screen.dart';
import '../utils/app_navigator.dart';
import '../utils/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'premium_badge.dart';

class RecentMatchesWidget extends StatelessWidget {
  final List<Match> matches;
  final String userId;

  const RecentMatchesWidget({
    super.key,
    required this.matches,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
        ),
        child: Center(
          child: Text(
            AppLocalizations.of(context).noRecentMatches,
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
        ),
      );
    }

    return Column(
      children: _collapseSeriesLegs(matches)
          .take(3)
          .map((entry) => _buildMatchItem(context, entry))
          .toList(),
    );
  }

  /// Collapse BO3 legs (same seriesId) into one entry, keyed on the newest
  /// leg (its winner is the series winner and it carries the series ELO).
  /// Same logic as the full history screen.
  List<_RecentEntry> _collapseSeriesLegs(List<Match> source) {
    final entries = <_RecentEntry>[];
    final bySeries = <String, List<Match>>{};
    for (final match in source) {
      final seriesId = match.seriesId;
      if (seriesId == null) {
        entries.add(_RecentEntry(match));
      } else {
        bySeries.putIfAbsent(seriesId, () => []).add(match);
      }
    }
    for (final legs in bySeries.values) {
      legs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final newest = legs.first;
      // Server tally first (see match_history_screen._collapseSeriesLegs);
      // row-counting is only the fallback for older backends.
      entries.add(_RecentEntry(
        newest,
        seriesP1Legs: newest.seriesPlayer1LegsWon ??
            legs.where((m) => m.winnerId.isNotEmpty && m.winnerId == m.player1Id).length,
        seriesP2Legs: newest.seriesPlayer2LegsWon ??
            legs.where((m) => m.winnerId.isNotEmpty && m.winnerId == m.player2Id).length,
      ));
    }
    entries.sort((a, b) => b.match.createdAt.compareTo(a.match.createdAt));
    return entries;
  }

  Widget _buildMatchItem(BuildContext context, _RecentEntry entry) {
    final match = entry.match;
    final l10n = AppLocalizations.of(context);
    final isWin = match.isWinner(userId);
    final eloChange = match.getEloChange(userId);
    final isPlacement = match.isPlacement;
    final opponentUsername = isPlacement
        ? l10n.botWithAvg((match.botDifficulty ?? 1) * 10)
        : match.getOpponentUsername(userId);
    final opponentIsPremium = !isPlacement && match.getOpponentIsPremium(userId);
    // BO3 series entry: show legs won instead of 501 remainders.
    final iAmPlayer1 = userId == match.player1Id;
    final myScore = entry.isSeries
        ? (iAmPlayer1 ? entry.seriesP1Legs! : entry.seriesP2Legs!)
        : match.getMyScore(userId);
    final opponentScore = entry.isSeries
        ? (iAmPlayer1 ? entry.seriesP2Legs! : entry.seriesP1Legs!)
        : match.getOpponentScore(userId);
    final dateFormat = DateFormat('MMM d');

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
            AppNavigator.toScreen(context, MatchDetailScreen(matchId: match.id));
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isWin ? AppTheme.success : AppTheme.error,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isWin ? AppTheme.success : AppTheme.error,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isWin ? l10n.winUpper : l10n.lossUpper,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isPlacement) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                l10n.placementUpper,
                                style: const TextStyle(
                                  color: AppTheme.accent,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    '${l10n.vs} $opponentUsername',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                PremiumBadge(isPremium: opponentIsPremium, size: 14),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dateFormat.format(match.createdAt),
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      entry.isSeries
                          ? '$myScore - $opponentScore ${l10n.legsShort}'
                          : '$myScore - $opponentScore',
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (isPlacement)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.placementCapitalized,
                          style: const TextStyle(
                            color: AppTheme.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (eloChange >= 0 ? AppTheme.success : AppTheme.error).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${eloChange >= 0 ? '+' : ''}$eloChange',
                          style: TextStyle(
                            color: eloChange >= 0 ? AppTheme.success : AppTheme.error,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
}

/// A recent-matches row: a plain match, or a collapsed BO3 series represented
/// by its newest (deciding) leg plus the legs tally.
class _RecentEntry {
  final Match match;
  final int? seriesP1Legs;
  final int? seriesP2Legs;

  _RecentEntry(this.match, {this.seriesP1Legs, this.seriesP2Legs});

  bool get isSeries => seriesP1Legs != null && seriesP2Legs != null;
}

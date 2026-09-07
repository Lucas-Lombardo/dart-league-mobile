import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/match.dart';
import '../screens/profile/match_detail_screen.dart';
import '../utils/app_navigator.dart';
import '../utils/app_theme.dart';
import '../l10n/app_localizations.dart';
import 'design_system.dart';
import 'premium_badge.dart';

/// The home "Matchs récents" list: one [MatchRowTile] per match (or per BO3
/// series), 10 px apart, capped at four.
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
      return DsCard(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            AppLocalizations.of(context).noRecentMatches,
            style: AppTheme.bodyLarge,
          ),
        ),
      );
    }

    final entries = _collapseSeriesLegs(matches).take(4).toList();
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          MatchRowTile(
            match: entries[i].match,
            userId: userId,
            seriesP1Legs: entries[i].seriesP1Legs,
            seriesP2Legs: entries[i].seriesP2Legs,
          ),
        ],
      ],
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
}

/// The match row of the system, 60 px: result square, "vs Name" + premium
/// crown, "Classé · date, heure", score 16 / 700 tabular, ELO delta 12 / 700.
///
/// A BO3 series is passed as its newest leg plus the legs tally
/// ([seriesP1Legs] / [seriesP2Legs]) and shows legs won instead of the 501
/// remainders. A match still in progress swaps the square for a play glyph
/// and the score for an "En cours" pill. Tapping opens the match detail
/// unless [onTap] says otherwise.
class MatchRowTile extends StatelessWidget {
  final Match match;
  final String userId;
  final int? seriesP1Legs;
  final int? seriesP2Legs;
  final VoidCallback? onTap;

  const MatchRowTile({
    super.key,
    required this.match,
    required this.userId,
    this.seriesP1Legs,
    this.seriesP2Legs,
    this.onTap,
  });

  bool get isSeries => seriesP1Legs != null && seriesP2Legs != null;

  /// "Classé" / "Amical" / "Tournoi" / "Bot" / "Placement". Unknown kinds
  /// read as ranked, which they are.
  static String kindLabel(AppLocalizations l10n, Match match) {
    switch (match.matchType) {
      case 'placement':
        return l10n.placementCapitalized;
      case 'friendly':
        return l10n.statsModeFriendly;
      case 'tournament':
        return l10n.statsModeTournament;
      case 'bot':
        return l10n.statsModeBot;
      default:
        return l10n.statsModeRanked;
    }
  }

  /// "Aujourd’hui, 09:12" / "Hier, 18:40" / "ven. 4 sept., 12:02".
  static String relativeDate(BuildContext context, DateTime when) {
    final l10n = AppLocalizations.of(context);
    final at = when.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final time = DateFormat('HH:mm').format(at);
    String label;
    if (day == today) {
      label = l10n.todayLabel;
    } else if (day == today.subtract(const Duration(days: 1))) {
      label = l10n.yesterdayLabel;
    } else {
      try {
        label = DateFormat('EEE d MMM', Localizations.localeOf(context).languageCode).format(at);
      } catch (_) {
        label = DateFormat('MMM d').format(at);
      }
    }
    return '$label, $time';
  }

  /// "Classé · Aujourd’hui, 09:12" — the match kind and a short date.
  static String contextLine(BuildContext context, Match match) {
    final l10n = AppLocalizations.of(context);
    return '${kindLabel(l10n, match)} · ${relativeDate(context, match.createdAt)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inProgress = match.isInProgress;
    final isWin = match.isWinner(userId);
    final eloChange = match.getEloChange(userId);
    final isPlacement = match.isPlacement;
    final opponentUsername = isPlacement
        ? l10n.botWithAvg((match.botDifficulty ?? 1) * 10)
        : match.getOpponentUsername(userId);
    final opponentIsPremium = !isPlacement && match.getOpponentIsPremium(userId);
    final iAmPlayer1 = userId == match.player1Id;
    final myScore = isSeries
        ? (iAmPlayer1 ? seriesP1Legs! : seriesP2Legs!)
        : match.getMyScore(userId);
    final opponentScore = isSeries
        ? (iAmPlayer1 ? seriesP2Legs! : seriesP1Legs!)
        : match.getOpponentScore(userId);
    // Friendly and bot matches never move the ELO; "+0" on every one of them
    // would read as noise.
    final showDelta = !isPlacement && (eloChange != 0 || match.matchType == 'ranked');
    final deltaColor = eloChange >= 0 ? AppTheme.success : AppTheme.error;

    return SizedBox(
      height: 60,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        onTap: onTap ??
            () => AppNavigator.toScreen(context, MatchDetailScreen(matchId: match.id)),
        child: Row(
          children: [
            if (inProgress)
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.play_arrow_rounded, size: 18, color: AppTheme.primaryLight),
              )
            else
              DsResultSquare(
                won: isWin,
                letter: isWin ? l10n.formWinLetter : l10n.formLossLetter,
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '${l10n.vs} $opponentUsername',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.rowTitle,
                        ),
                      ),
                      PremiumBadge(
                        isPremium: opponentIsPremium,
                        size: 12,
                        color: AppTheme.accent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contextLine(context, match),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (inProgress)
              DsPill(
                label: dsSentence(l10n.matchStatusInProgress),
                color: AppTheme.primaryLight,
              )
            else ...[
              Text(
                '$myScore–$opponentScore',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 10),
              // Fixed column so the scores of a list line up even when a row
              // has no delta to show.
              SizedBox(
                width: 34,
                child: showDelta
                    ? Text(
                        '${eloChange >= 0 ? '+' : ''}$eloChange',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: deltaColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ],
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
}

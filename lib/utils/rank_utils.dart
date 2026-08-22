import 'package:flutter/material.dart';

/// Rank tiers ordered from lowest to highest. Index == comparable rank level.
/// Mirrors the backend's RANK_ORDER (EloService / TournamentService).
const List<String> kRankOrder = [
  'unranked',
  'bronze',
  'silver',
  'gold',
  'platinum',
  'diamond',
  'master',
];

/// Comparable level for a rank string (case-insensitive). Unknown -> 0.
int rankOrder(String? rank) {
  if (rank == null) return 0;
  final i = kRankOrder.indexOf(rank.toLowerCase());
  return i < 0 ? 0 : i;
}

/// ELO floor of each rank. MUST mirror the backend's EloService
/// (getRankFromElo / getRankFloor): 800 / 1200 / 1600 / 2000 / 2400 since the
/// 2026-08-13 rebase. The home ring, the season screens and the "new ELO"
/// band all read these — never hard-code thresholds in a screen.
const Map<String, int> kRankThresholds = {
  'bronze': 0,
  'silver': 800,
  'gold': 1200,
  'platinum': 1600,
  'diamond': 2000,
  'master': 2400,
};

/// Ranks that have an ELO floor, lowest first (no 'unranked').
const List<String> kRankedTiers = [
  'bronze',
  'silver',
  'gold',
  'platinum',
  'diamond',
  'master',
];

/// The rank a rating maps to; 0 is the unranked sentinel (placement).
String rankFromElo(int elo) {
  if (elo <= 0) return 'unranked';
  String rank = 'bronze';
  for (final tier in kRankedTiers) {
    if (elo >= kRankThresholds[tier]!) rank = tier;
  }
  return rank;
}

/// The rank above [rank] — 'master' stays 'master', unknown → 'bronze'.
String nextRank(String? rank) {
  final i = kRankedTiers.indexOf((rank ?? '').toLowerCase());
  if (i < 0) return 'bronze';
  return kRankedTiers[(i + 1).clamp(0, kRankedTiers.length - 1)];
}

/// Points missing to reach the next rank (0 or negative once there).
int eloNeededForNextRank(String? rank, int elo) {
  final next = nextRank(rank);
  return (kRankThresholds[next] ?? kRankThresholds['silver']!) - elo;
}

/// 0..1 progress of [elo] inside its current rank band (1 for Master).
double rankProgress(String? rank, int elo) {
  final r = (rank ?? '').toLowerCase();
  if (r == 'master') return 1.0;
  final current = kRankThresholds[r] ?? 0;
  final next = kRankThresholds[nextRank(r)] ?? kRankThresholds['silver']!;
  final range = next - current;
  if (range <= 0) return 1.0;
  return ((elo - current) / range).clamp(0.0, 1.0);
}

/// Human label for a rank string, e.g. 'gold' -> 'Gold'.
String rankLabel(String? rank) {
  if (rank == null || rank.isEmpty) return '';
  final r = rank.toLowerCase();
  return r[0].toUpperCase() + r.substring(1);
}

class RankUtils {
  static String getRankIcon(String rank) {
    final rankLower = rank.toLowerCase();
    
    switch (rankLower) {
      case 'bronze':
        return 'assets/ranks/bronze.png';
      case 'silver':
        return 'assets/ranks/silver.png';
      case 'gold':
        return 'assets/ranks/gold.png';
      case 'platinum':
        return 'assets/ranks/plat.png';
      case 'diamond':
        return 'assets/ranks/diamond.png';
      case 'master':
        return 'assets/ranks/master.png';
      case 'unranked':
        return 'assets/ranks/unranked.png';
      default:
        return 'assets/ranks/bronze.png';
    }
  }
  
  static Widget getRankBadge(String rank, {double size = 64}) {
    return Image.asset(
      getRankIcon(rank),
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Icon(
          Icons.shield,
          size: size,
          color: Colors.grey,
        );
      },
    );
  }
}

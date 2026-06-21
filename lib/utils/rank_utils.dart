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

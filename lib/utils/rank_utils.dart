import 'package:flutter/material.dart';

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
      default:
        return 'assets/ranks/bronze.png'; // Default to bronze
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

import 'package:flutter/material.dart';

class RankBadge extends StatelessWidget {
  final String rank;
  final double size;
  final bool showLabel;

  const RankBadge({
    super.key,
    required this.rank,
    this.size = 40,
    this.showLabel = true,
  });

  Color get rankColor {
    switch (rank.toLowerCase()) {
      case 'bronze':
        return const Color(0xFFCD7F32);
      case 'silver':
        return const Color(0xFFC0C0C0);
      case 'gold':
        return const Color(0xFFFFD700);
      case 'platinum':
        return const Color(0xFFE5E4E2);
      case 'diamond':
        return const Color(0xFFB9F2FF);
      case 'master':
        return const Color(0xFFFF1744);
      default:
        return Colors.grey;
    }
  }

  IconData get rankIcon {
    switch (rank.toLowerCase()) {
      case 'master':
        return Icons.emoji_events;
      case 'diamond':
      case 'platinum':
        return Icons.workspace_premium;
      default:
        return Icons.military_tech;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                rankColor,
                rankColor.withValues(alpha: 0.6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: rankColor.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            rankIcon,
            color: Colors.black87,
            size: size * 0.6,
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: 4),
          Text(
            rank.toUpperCase(),
            style: TextStyle(
              color: rankColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ],
      ],
    );
  }
}

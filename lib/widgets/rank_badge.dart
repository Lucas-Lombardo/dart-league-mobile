import 'package:flutter/material.dart';
import '../utils/rank_utils.dart';

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

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RankUtils.getRankBadge(rank, size: size),
        if (showLabel) ...[
          const SizedBox(height: 4),
          Text(
            rank.toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
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

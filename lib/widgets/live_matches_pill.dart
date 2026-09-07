import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../screens/spectate/spectate_hub_screen.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import 'design_system.dart';

/// Home row shown while spectatable matches are running: a pulsing live dot,
/// "3 matchs en direct", and "Regarder ›". Opens the "En direct" hub.
class LiveMatchesPill extends StatefulWidget {
  final int count;

  const LiveMatchesPill({super.key, required this.count});

  @override
  State<LiveMatchesPill> createState() => _LiveMatchesPillState();
}

class _LiveMatchesPillState extends State<LiveMatchesPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 52,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        onTap: () {
          HapticService.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const SpectateHubScreen()),
          );
        },
        child: Row(
          children: [
            RepaintBoundary(
              child: SizedBox(
                width: 16,
                height: 16,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final t = _controller.value;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 8 + 8 * t,
                          height: 8 + 8 * t,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.secondary
                                .withValues(alpha: (1 - t) * 0.3),
                          ),
                        ),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.secondary,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${widget.count} ${l10n.spectateMatchesLive(widget.count)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            Text(
              l10n.spectateWatch,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryLight,
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: AppTheme.primaryLight),
          ],
        ),
      ),
    );
  }
}

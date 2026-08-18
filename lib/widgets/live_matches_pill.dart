import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../screens/spectate/spectate_hub_screen.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';

/// The activity pill's live twin: shown on the home screen while spectatable
/// matches are running, opens the "En direct" hub. Same silhouette as
/// ActivityPill, but keyed on the live (pink) identity.
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
    return Center(
      child: InkWell(
        onTap: () {
          HapticService.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const SpectateHubScreen()),
          );
        },
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppTheme.opponentPink.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
                            width: 7 + 9 * t,
                            height: 7 + 9 * t,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.opponentPink
                                  .withValues(alpha: (1 - t) * 0.35),
                            ),
                          ),
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.opponentPink,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Text(
                '${widget.count}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                l10n.spectateMatchesLive(widget.count),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right,
                  size: 16, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

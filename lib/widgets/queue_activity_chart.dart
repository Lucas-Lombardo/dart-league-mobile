import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/matchmaking_service.dart';
import '../utils/app_theme.dart';

/// Small bar chart on the queue screen showing at which hours (device-local)
/// ranked matches usually get played, so a player waiting in a quiet queue
/// knows when opponents are most likely to be around.
class QueueActivityChart extends StatefulWidget {
  const QueueActivityChart({super.key});

  @override
  State<QueueActivityChart> createState() => _QueueActivityChartState();
}

class _QueueActivityChartState extends State<QueueActivityChart> {
  // Below this many matches in the window the histogram is mostly noise, so
  // the card stays hidden (also covers brand-new deployments).
  static const _minSampleSize = 20;

  List<int>? _localHourCounts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final activity = await MatchmakingService.getActivity();
    if (!mounted ||
        activity == null ||
        activity.totalMatches < _minSampleSize) {
      return;
    }
    setState(() => _localHourCounts = activity.localHourCounts());
  }

  @override
  Widget build(BuildContext context) {
    final counts = _localHourCounts;
    if (counts == null) return const SizedBox.shrink();

    final loc = AppLocalizations.of(context);
    final maxCount = counts.reduce((a, b) => a > b ? a : b);
    final nowHour = DateTime.now().hour;
    var peakHour = 0;
    for (var h = 1; h < 24; h++) {
      if (counts[h] > counts[peakHour]) peakHour = h;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                loc.peakHours,
                style: AppTheme.labelLarge.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                loc.peakHoursNow,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(24, (hour) {
                // 2px stub for empty hours so they read as "measured: none"
                // rather than a gap in the chart.
                final barHeight = counts[hour] == 0
                    ? 2.0
                    : 4.0 + 44.0 * counts[hour] / maxCount;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: Container(
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: hour == nowHour
                            ? AppTheme.accent
                            : AppTheme.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final h in const [0, 6, 12, 18])
                Expanded(
                  child: Text(
                    '${h}h',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 9,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            loc.peakHoursHint(peakHour),
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            loc.peakHoursGrowing,
            style: TextStyle(
              color: AppTheme.textPrimary.withValues(alpha: 0.9),
              fontSize: 11,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

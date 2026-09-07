import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/matchmaking_service.dart';
import '../utils/app_theme.dart';
import 'design_system.dart';

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

  static const _barsHeight = 56.0;

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

    return DsCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dsSentence(loc.peakHours),
                  style: AppTheme.sectionTitle,
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                loc.peakHoursNow,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: _barsHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(24, (hour) {
                // 2px stub for empty hours so they read as "measured: none"
                // rather than a gap in the chart.
                final barHeight = counts[hour] == 0
                    ? 2.0
                    : 3.0 + (_barsHeight - 3.0) * counts[hour] / maxCount;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Container(
                      height: barHeight,
                      decoration: BoxDecoration(
                        color: hour == nowHour
                            ? AppTheme.primary
                            : AppTheme.primary.withValues(alpha: 0.30),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final h in const [0, 6, 12, 18, 24])
                Text(
                  loc.queueAxisHour(h),
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            loc.peakHoursHint(peakHour),
            style: AppTheme.caption.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }
}

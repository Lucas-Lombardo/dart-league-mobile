import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/presence_service.dart';
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';

/// Homescreen "pulse" card (design option 3): the day's activity curve drawn
/// directly on the card, with the active count and a live online chip.
/// Tapping opens the detail sheet.
class ActivityPulseCard extends StatelessWidget {
  final ActivitySnapshot snapshot;

  /// Live count from PresenceProvider; falls back to the snapshot's value.
  final int? onlineNow;

  const ActivityPulseCard({
    super.key,
    required this.snapshot,
    this.onlineNow,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final online = onlineNow ?? snapshot.onlineNow;
    final counts = snapshot.hourly.map((h) => h.count).toList();

    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        showActivitySheet(context, snapshot: snapshot, onlineNow: online);
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.18),
              blurRadius: 26,
              spreadRadius: -12,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  '${snapshot.matches24h}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  l10n.activityMatchesLabel(24).toLowerCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
                const Spacer(),
                if (online > 0) ...[
                  const _LiveDot(),
                  const SizedBox(width: 5),
                  Text(
                    l10n.activityNowChip(online),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.success,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 42,
              child: CustomPaint(
                painter: _PulsePainter(counts: counts),
                size: Size.infinite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.success,
        boxShadow: [
          BoxShadow(
            color: AppTheme.success.withValues(alpha: 0.55),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}

/// Area-line chart of the hourly activity counts. Used small on the card and
/// larger (with baseline) in the sheet.
class _PulsePainter extends CustomPainter {
  final List<int> counts;
  final bool showBaseline;

  const _PulsePainter({required this.counts, this.showBaseline = false});

  @override
  void paint(Canvas canvas, Size size) {
    if (counts.length < 2) return;

    final maxCount = counts.fold(1, (m, c) => c > m ? c : m);
    // Insets keep the stroke, dots and halo inside the paint area instead of
    // hugging the card edges (a flat stretch otherwise reads as a border).
    const leftPad = 4.0;
    const rightPad = 4.0;
    const topPad = 9.0;
    final baseY = size.height - 3;
    final stepX = (size.width - leftPad - rightPad) / (counts.length - 1);

    Offset pointAt(int i) {
      final t = counts[i] / maxCount;
      return Offset(leftPad + i * stepX, baseY - t * (baseY - topPad));
    }

    final points = [for (var i = 0; i < counts.length; i++) pointAt(i)];

    // Midpoint-smoothed curve: each data point becomes the control of a
    // quadratic segment ending halfway to the next, so sparse spiky data
    // renders as soft hills instead of sawteeth.
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length - 1; i++) {
      final mid = Offset(
        (points[i].dx + points[i + 1].dx) / 2,
        (points[i].dy + points[i + 1].dy) / 2,
      );
      line.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    line.lineTo(points.last.dx, points.last.dy);

    final area = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    if (showBaseline) {
      canvas.drawLine(
        Offset(0, baseY),
        Offset(size.width, baseY),
        Paint()
          ..color = AppTheme.surfaceLight
          ..strokeWidth = 1,
      );
    }

    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.primary.withValues(alpha: 0.28),
            AppTheme.primary.withValues(alpha: 0.0),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = AppTheme.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    Offset clamped(Offset p) => Offset(
          p.dx.clamp(7.0, size.width - 7.0),
          p.dy.clamp(7.0, size.height - 7.0),
        );

    // Emphasized peak point (halo + dot) and a small marker on "now".
    final peakIndex = counts.indexOf(maxCount);
    final peak = clamped(points[peakIndex]);
    canvas.drawCircle(
      peak,
      6,
      Paint()..color = AppTheme.primary.withValues(alpha: 0.25),
    );
    canvas.drawCircle(peak, 3, Paint()..color = AppTheme.primary);

    if (peakIndex != counts.length - 1) {
      canvas.drawCircle(
        clamped(points.last),
        2.5,
        Paint()..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) =>
      oldDelegate.showBaseline != showBaseline ||
      !_listEquals(oldDelegate.counts, counts);

  static bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Detail bottom sheet: big chart with annotated peak, three stat tiles, and
/// the peak / queue-notification tips.
Future<void> showActivitySheet(
  BuildContext context, {
  required ActivitySnapshot snapshot,
  required int onlineNow,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _ActivitySheet(snapshot: snapshot, onlineNow: onlineNow),
  );
}

class _ActivitySheet extends StatelessWidget {
  final ActivitySnapshot snapshot;
  final int onlineNow;

  const _ActivitySheet({required this.snapshot, required this.onlineNow});

  String _hourLabel(DateTime hourUtc) => '${hourUtc.toLocal().hour}h';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final counts = snapshot.hourly.map((h) => h.count).toList();
    final peakHour = snapshot.peakHour;
    final peakLabel = peakHour != null ? _hourLabel(peakHour) : '—';

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text(l10n.activityPulseTitle, style: AppTheme.titleLarge),
                  const SizedBox(width: 8),
                  const _LiveChip(),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                l10n.activitySheetSubtitle(snapshot.windowHours),
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Stack(
                children: [
                  SizedBox(
                    height: 120,
                    child: CustomPaint(
                      painter: _PulsePainter(counts: counts, showBaseline: true),
                      size: Size.infinite,
                    ),
                  ),
                  if (peakHour != null)
                    Positioned(
                      top: 0,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.background,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          '${snapshot.peakCount} · $peakLabel',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 5),
              _AxisLabels(
                hourly: snapshot.hourly,
                nowLabel: l10n.activityNowAxisLabel,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _StatTile(
                    value: '$onlineNow',
                    label: l10n.activityOnlineNowLabel,
                    showDot: onlineNow > 0,
                  ),
                  const SizedBox(width: 8),
                  _StatTile(
                    value: '${snapshot.activeCount}',
                    label: l10n.activityActiveLabel(snapshot.windowHours),
                  ),
                  const SizedBox(width: 8),
                  _StatTile(value: peakLabel, label: l10n.activityPeakLabel),
                ],
              ),
              const SizedBox(height: 12),
              if (peakHour != null)
                _InsightRow(
                  emoji: '💡',
                  text: l10n.activityPeakTip(peakLabel),
                  withDivider: false,
                ),
              _InsightRow(
                emoji: '🔔',
                text: l10n.activityQueueTip,
                withDivider: peakHour != null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  const _LiveChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.success.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.success,
            ),
          ),
          const SizedBox(width: 5),
          const Text(
            'LIVE',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppTheme.success,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sparse x-axis: a label every 3 buckets plus "now" under the last one.
class _AxisLabels extends StatelessWidget {
  final List<ActivityHour> hourly;
  final String nowLabel;

  const _AxisLabels({required this.hourly, required this.nowLabel});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 8.5,
      fontWeight: FontWeight.w600,
      color: AppTheme.textSecondary.withValues(alpha: 0.7),
    );
    return Row(
      children: [
        for (var i = 0; i < hourly.length; i++)
          Expanded(
            child: Text(
              i == hourly.length - 1
                  ? nowLabel
                  : (i % 3 == 0 ? '${hourly[i].hour.toLocal().hour}h' : ''),
              textAlign: TextAlign.center,
              style: style,
            ),
          ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String value;
  final String label;
  final bool showDot;

  const _StatTile({
    required this.value,
    required this.label,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (showDot) ...[
                  const _LiveDot(),
                  const SizedBox(width: 5),
                ],
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: AppTheme.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  final String emoji;
  final String text;
  final bool withDivider;

  const _InsightRow({
    required this.emoji,
    required this.text,
    required this.withDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: withDivider
          ? BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                ),
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

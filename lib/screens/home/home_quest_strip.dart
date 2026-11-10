import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../providers/progression_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../progression/progression_format.dart';
import '../progression/progression_screen.dart';

/// The quest the home strip shows: the daily quest closest to done (the
/// first one on a tie); once they are all done, the weekly one closest to
/// done; null when both are done.
class HomeQuestPick {
  final UserQuest? quest;
  final bool weekly;
  final int dailyDone;
  final int dailyTotal;
  const HomeQuestPick({this.quest, this.weekly = false, this.dailyDone = 0, this.dailyTotal = 0});

  static UserQuest? _closest(List<UserQuest> quests) {
    UserQuest? best;
    for (final q in quests) {
      if (q.isDone) continue;
      if (best == null || q.fraction > best.fraction) best = q;
    }
    return best;
  }

  /// The journal tab of the quest shown (null when none is: the journal then
  /// opens on its first tab with a quest to do).
  QuestTab? get tab => quest == null ? null : (weekly ? QuestTab.week : QuestTab.day);

  factory HomeQuestPick.of(QuestsSnapshot snapshot) {
    final daily = snapshot.daily;
    final today = _closest(daily.quests);
    final week = today == null ? _closest(snapshot.weekly.quests) : null;
    return HomeQuestPick(
      quest: today ?? week,
      weekly: today == null && week != null,
      dailyDone: daily.done,
      dailyTotal: daily.quests.length,
    );
  }
}

/// Under the player card, on the home only (mockup AccFinal): the 4 pt XP
/// bar across the card, then the 36 pt quest strip — « Quête : … · 3/5 »,
/// « +40 XP », the daily quests done « 2/3 » and a chevron to the quest
/// journal. Each part waits for its API (nothing drawn rather than zeros).
class HomeQuestStrip extends StatelessWidget {
  final ProgressionSummary? summary;
  final QuestsSnapshot? quests;
  const HomeQuestStrip({super.key, this.summary, this.quests});

  /// From the progression provider (nothing without one).
  static Widget fromProvider(BuildContext context) {
    final p = maybeWatchProgression(context);
    if (p == null) return const SizedBox.shrink();
    return HomeQuestStrip(summary: p.summary, quests: p.quests);
  }

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final q = quests;
    if (s == null && q == null) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 4,
          child: ColoredBox(
            color: AppTheme.surface,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: s?.progress ?? 0,
                heightFactor: 1,
                child: const ColoredBox(color: AppTheme.primaryLight),
              ),
            ),
          ),
        ),
        if (q != null) _QuestLine(pick: HomeQuestPick.of(q)),
      ],
    );
  }
}

const TextStyle _lineStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.textPrimary);

class _QuestLine extends StatelessWidget {
  final HomeQuestPick pick;
  const _QuestLine({required this.pick});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final quest = pick.quest;
    const muted = AppTheme.textSecondary;
    return Material(
      color: const Color(0xFF0B1220),
      child: InkWell(
        onTap: () {
          HapticService.lightImpact();
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProgressionScreen(initialTab: pick.tab)));
        },
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                _ProgressRing(value: quest?.fraction ?? 1),
                const SizedBox(width: 10),
                // The quest's text gives way (ellipsis) before its progress.
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          quest == null
                              ? l10n.homeQuestsAllDone
                              : pick.weekly
                                  ? l10n.homeQuestWeekly(quest.text.resolve(context))
                                  : l10n.homeQuestDaily(quest.text.resolve(context)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _lineStyle,
                        ),
                      ),
                      if (quest != null)
                        Text(
                          ' · ${formatXp(quest.progress)}/${formatXp(quest.threshold)}',
                          maxLines: 1,
                          style: _lineStyle.copyWith(color: muted),
                        ),
                    ],
                  ),
                ),
                if (quest != null && quest.xp > 0) ...[
                  const SizedBox(width: 10),
                  Text(
                    l10n.homeXpGain(quest.xp),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF7DD3FC)),
                  ),
                ],
                if (pick.dailyTotal > 0) ...[
                  const SizedBox(width: 10),
                  Text(
                    '${pick.dailyDone}/${pick.dailyTotal}',
                    semanticsLabel: l10n.homeQuestsDoneLabel(pick.dailyDone, pick.dailyTotal),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: muted),
                  ),
                ],
                const SizedBox(width: 10),
                const Icon(Icons.chevron_right_rounded, size: 16, color: muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A 16 pt ring: the quest's progress in blue on a slate track.
class _ProgressRing extends StatelessWidget {
  final double value;
  const _ProgressRing({required this.value});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size.square(16), painter: _RingPainter(value.clamp(0.0, 1.0)));
}

class _RingPainter extends CustomPainter {
  final double value;
  _RingPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    // The mockup's 18-unit view box: r 7, stroke 2.5.
    final k = size.width / 18;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: 7 * k);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5 * k;
    canvas.drawArc(rect, 0, 2 * math.pi, false, stroke..color = const Color(0xFF475569));
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value,
        false,
        stroke
          ..color = AppTheme.primaryLight
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value;
}

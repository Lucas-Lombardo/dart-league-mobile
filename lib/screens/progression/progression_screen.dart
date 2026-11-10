import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../providers/progression_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/fit_text.dart';
import 'levels_path_screen.dart';
import 'locker_unlock.dart' show lockerEvent;
import 'progression_format.dart';

/// The quest journal's tabs; [event] only while an event sends quests.
enum QuestTab { day, week, discover, event }

/// Level, XP and quests in tabs (piste A, mockup docs/progression/ecrans/R6A,
/// generator svg/gen_revue56.py `p6a`, `qrow`, `done_row`, `lvl_card`,
/// `ring`): a compact level card, the segmented tabs « Jour 1/3 · Semaine 1/3
/// · Découvrir 3/6 » (+ « Événement » during an event), one info line, then
/// only the quests left to do; the quests done fold into one line. A swap
/// icon sits on each quest that can be changed today.
class ProgressionScreen extends StatefulWidget {
  /// The tab to open on (the home strip's quest, the locker's event item);
  /// null = the first tab with a quest left to do.
  final QuestTab? initialTab;
  const ProgressionScreen({super.key, this.initialTab});

  /// Day, week, discover, and event while the server sends event quests.
  static List<QuestTab> tabsFor(QuestsSnapshot? quests) => [
        QuestTab.day,
        QuestTab.week,
        QuestTab.discover,
        if (eventQuests(quests).isNotEmpty) QuestTab.event,
      ];

  /// The first tab with a quest left to do; day when everything is done.
  static QuestTab defaultTab(QuestsSnapshot? quests) {
    for (final tab in tabsFor(quests)) {
      if (questsOf(quests, tab).any((q) => !q.isDone)) return tab;
    }
    return QuestTab.day;
  }

  /// The quests of every running event that has not ended yet.
  static List<UserQuest> eventQuests(QuestsSnapshot? quests, {DateTime? now}) {
    final t = now ?? DateTime.now();
    return [
      for (final e in quests?.events ?? const <EventQuests>[])
        if (e.endsAt == null || e.endsAt!.isAfter(t)) ...e.quests,
    ];
  }

  static List<UserQuest> questsOf(QuestsSnapshot? quests, QuestTab tab) => switch (tab) {
        QuestTab.day => quests?.daily.quests ?? const [],
        QuestTab.week => quests?.weekly.quests ?? const [],
        QuestTab.discover => quests?.discovery.quests ?? const [],
        QuestTab.event => eventQuests(quests),
      };

  /// A quest the server lets me change today: a daily one, not done, while
  /// the day's change is unused (POST /progression/quests/:id/reroll).
  static bool canChange(QuestsSnapshot? quests, UserQuest quest) =>
      quests != null && quests.daily.rerollAvailable && !quest.isDone && quests.daily.quests.any((q) => q.id == quest.id);

  @override
  State<ProgressionScreen> createState() => _ProgressionScreenState();
}

class _ProgressionScreenState extends State<ProgressionScreen> {
  /// The tab the player touched; wins over everything else.
  QuestTab? _picked;

  /// The first tab with a quest to do, frozen on the first quests seen.
  QuestTab? _auto;

  /// Tabs whose « N terminées » line is unfolded.
  final _doneOpen = <QuestTab>{};
  bool _changing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<ProgressionProvider>();
      p.refreshSummary();
      p.refreshQuests();
    });
  }

  QuestTab _tab(QuestsSnapshot? quests) {
    final tabs = ProgressionScreen.tabsFor(quests);
    final picked = _picked;
    if (picked != null && tabs.contains(picked)) return picked;
    final wanted = widget.initialTab;
    if (wanted != null && tabs.contains(wanted)) return wanted;
    if (quests == null) return QuestTab.day;
    return _auto ??= ProgressionScreen.defaultTab(quests);
  }

  Future<void> _change(UserQuest quest) async {
    if (_changing) return;
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.questsChangeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(quest.text.resolve(ctx), style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.textPrimary)),
            const SizedBox(height: 10),
            Text(l10n.questsChangeBody),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(l10n.questsChangeConfirm)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _changing = true);
    final done = await context.read<ProgressionProvider>().reroll(quest.id);
    if (!mounted) return;
    setState(() => _changing = false);
    if (!done) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.questsRerollFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.watch<ProgressionProvider>();
    final summary = p.summary ?? const ProgressionSummary();
    final quests = p.quests;
    final tabs = ProgressionScreen.tabsFor(quests);
    final tab = _tab(quests);
    final list = ProgressionScreen.questsOf(quests, tab);
    final todo = list.where((q) => !q.isDone).toList();
    final done = list.where((q) => q.isDone).toList();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: DsScreenHeader(
                title: l10n.progressionTitle,
                showBack: true,
                actions: [
                  _HeaderLink(
                    label: l10n.progressionPath,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LevelsPathScreen())),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppTheme.primary,
                onRefresh: () => Future.wait([p.refreshSummary(), p.refreshQuests()]),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  children: [
                    _LevelCard(summary: summary),
                    const SizedBox(height: 10),
                    _QuestTabs(
                      tabs: tabs,
                      selected: tab,
                      count: (t) {
                        final all = ProgressionScreen.questsOf(quests, t);
                        return quests == null ? null : '${all.where((q) => q.isDone).length}/${all.length}';
                      },
                      onSelect: (t) => setState(() => _picked = t),
                    ),
                    const SizedBox(height: 10),
                    if (quests != null) ...[
                      _InfoLine(tab: tab, quests: quests, content: p.content),
                      const SizedBox(height: 10),
                    ],
                    if (quests == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator(color: AppTheme.primaryLight)),
                      )
                    else
                      _QuestCard(
                        key: ValueKey('quests-${tab.name}'),
                        todo: todo,
                        done: done,
                        doneOpen: _doneOpen.contains(tab),
                        onToggleDone: () => setState(() => _doneOpen.contains(tab) ? _doneOpen.remove(tab) : _doneOpen.add(tab)),
                        canChange: (q) => !_changing && ProgressionScreen.canChange(quests, q),
                        onChange: _change,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// « Parcours » on the right of the header (14/800 #7DD3FC).
class _HeaderLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _HeaderLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppTheme.playerBlueBright),
          ),
        ),
      ),
    );
  }
}

/// The compact level card (mockup `lvl_card`): the big number, « Niveau 23 »,
/// « 806 / 1 580 XP » and the bar.
class _LevelCard extends StatelessWidget {
  final ProgressionSummary summary;
  const _LevelCard({required this.summary});

  static const _meta = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: AppTheme.textSecondary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Text(
            '${summary.level}',
            style: const TextStyle(
              fontSize: 26,
              height: 1.2,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: AppTheme.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(l10n.xpLevel(summary.level), maxLines: 1, style: _meta)),
                    Text(
                      l10n.xpProgressValue(formatXp(summary.xpIntoLevel), formatXp(summary.xpToNext)),
                      style: _meta,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _Track(value: summary.progress, height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Track extends StatelessWidget {
  final double value;
  final double height;
  const _Track({required this.value, required this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: AppTheme.surfaceLight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              heightFactor: 1,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.primaryLight,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The segmented control: « Jour 1/3 », « Semaine 1/3 », « Découvrir 3/6 »
/// (done / total), « Événement » during an event.
class _QuestTabs extends StatelessWidget {
  final List<QuestTab> tabs;
  final QuestTab selected;
  final String? Function(QuestTab) count;
  final ValueChanged<QuestTab> onSelect;
  const _QuestTabs({required this.tabs, required this.selected, required this.count, required this.onSelect});

  static String label(AppLocalizations l10n, QuestTab tab) => switch (tab) {
        QuestTab.day => l10n.questsTabDay,
        QuestTab.week => l10n.questsTabWeek,
        QuestTab.discover => l10n.questsTabDiscover,
        QuestTab.event => l10n.questsTabEvent,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(13)),
      child: Row(
        children: [
          for (final t in tabs)
            Expanded(
              child: _TabButton(
                key: Key('quest-tab-${t.name}'),
                label: label(l10n, t),
                count: count(t),
                selected: t == selected,
                // Four tabs (an event): one smaller size for all of them.
                compact: tabs.length > 3,
                onTap: () => onSelect(t),
              ),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final String? count;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;
  const _TabButton({
    super.key,
    required this.label,
    required this.count,
    required this.selected,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: [label, ?count].join(' '),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 36,
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
          decoration: BoxDecoration(
            color: selected ? AppTheme.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          // A long label shrinks as a whole, never cut.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: compact ? 12.5 : 14,
                    fontWeight: FontWeight.w800,
                    color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                  ),
                ),
                if (count != null) ...[
                  SizedBox(width: compact ? 4 : 6),
                  Text(
                    count!,
                    style: TextStyle(
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppTheme.playerBlueBright : AppTheme.textTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The line under the tabs: when the quests renew (day, week), « Une seule
/// fois » (discover), the event's dates; on the day tab, the change left.
class _InfoLine extends StatelessWidget {
  final QuestTab tab;
  final QuestsSnapshot quests;
  final ProgressionContent? content;
  const _InfoLine({required this.tab, required this.quests, required this.content});

  static const _style = TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.textSecondary);

  String? _text(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    switch (tab) {
      case QuestTab.day:
        final end = quests.daily.endsAt;
        return end == null ? null : l10n.questsNewQuestsIn(formatRemaining(l10n, end.difference(now)));
      case QuestTab.week:
        final end = quests.weekly.endsAt;
        return end == null ? null : l10n.questsWeekLeft(formatRemaining(l10n, end.difference(now)));
      case QuestTab.discover:
        return l10n.questsOnce;
      case QuestTab.event:
        return eventDates(context, quests, content);
    }
  }

  /// « Du 11 déc. au 3 janv. » from the content's event (its last day is the
  /// one before `endsAt`), else « Jusqu'au 3 janv. » from the quests' end.
  static String? eventDates(BuildContext context, QuestsSnapshot quests, ProgressionContent? content) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final day = DateFormat('d MMM', locale);
    final now = DateTime.now();
    final running = quests.events.where((e) => e.quests.isNotEmpty && (e.endsAt == null || e.endsAt!.isAfter(now)));
    final event = running.firstOrNull;
    if (event == null) return null;
    final def = lockerEvent(content, event.eventId);
    final start = def == null ? null : DateTime.tryParse('${def['startsAt']}')?.toLocal();
    final end = (def == null ? null : DateTime.tryParse('${def['endsAt']}')?.toLocal()) ?? event.endsAt?.toLocal();
    if (end == null) return null;
    final last = day.format(end.subtract(const Duration(minutes: 1)));
    return start == null ? l10n.questsEventUntil(last) : l10n.lockerSHowEventDates(day.format(start), last);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = _text(context);
    final icon = switch (tab) {
      QuestTab.day || QuestTab.week => Icons.schedule_rounded,
      QuestTab.discover => Icons.explore_outlined,
      QuestTab.event => Icons.event_outlined,
    };
    final changeable = tab == QuestTab.day && quests.daily.quests.any((q) => !q.isDone);
    final left = quests.daily.rerollAvailable ? 1 : 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
      child: Row(
        children: [
          if (text != null) ...[
            Icon(icon, size: 14, color: AppTheme.textSecondary),
            const SizedBox(width: 6),
            Expanded(child: FitText(text, minFontSize: 11, style: _style)),
          ] else
            const Spacer(),
          if (changeable) ...[
            const SizedBox(width: 8),
            Icon(Icons.repeat_rounded, size: 14, color: left > 0 ? AppTheme.playerBlueBright : AppTheme.textTertiary),
            const SizedBox(width: 5),
            Text(
              l10n.questsChanges(left),
              key: const Key('quests-changes-left'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: left > 0 ? AppTheme.playerBlueBright : AppTheme.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The quests left to do, then « N terminées · +X XP gagnés », which unfolds
/// the quests done.
class _QuestCard extends StatelessWidget {
  final List<UserQuest> todo;
  final List<UserQuest> done;
  final bool doneOpen;
  final VoidCallback onToggleDone;
  final bool Function(UserQuest) canChange;
  final ValueChanged<UserQuest> onChange;
  const _QuestCard({
    super.key,
    required this.todo,
    required this.done,
    required this.doneOpen,
    required this.onToggleDone,
    required this.canChange,
    required this.onChange,
  });

  static const _divider = Divider(height: 1, thickness: 1, color: Color(0x8C334155));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <Widget>[
      for (final q in todo) QuestRow(key: Key('quest-${q.id}'), quest: q, onChange: canChange(q) ? () => onChange(q) : null),
      if (done.isNotEmpty) _DoneLine(count: done.length, xp: done.fold(0, (s, q) => s + q.xp), open: doneOpen, onTap: onToggleDone),
      if (done.isNotEmpty && doneOpen)
        for (final q in done) QuestRow(key: Key('quest-${q.id}'), quest: q),
    ];
    return Container(
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(18)),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: rows.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 14),
                child: Text(
                  l10n.questsNothing,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) _divider,
                    rows[i],
                  ],
                ],
              ),
      ),
    );
  }
}

/// « 1 terminée · +40 XP gagnés » with a green tick and a chevron.
class _DoneLine extends StatelessWidget {
  final int count;
  final int xp;
  final bool open;
  final VoidCallback onTap;
  const _DoneLine({required this.count, required this.xp, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = l10n.questsDoneSummary(count, formatXp(xp));
    return Semantics(
      button: true,
      expanded: open,
      label: text,
      excludeSemantics: true,
      child: InkWell(
        key: const Key('quests-done-line'),
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(color: Color(0x2E22C55E), shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 14, color: Color(0xFF4ADE80)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FitText(
                    text,
                    minFontSize: 11,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppTheme.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One quest (mockup `qrow`): progress ring, the text on two lines at most
/// (never cut inside a word), « a / b », « +XP », and the swap icon when it
/// can be changed today. A quest done is muted.
class QuestRow extends StatelessWidget {
  final UserQuest quest;

  /// Set when the quest can be changed: shows the swap icon.
  final VoidCallback? onChange;
  const QuestRow({super.key, required this.quest, this.onChange});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final done = quest.isDone;
    final change = onChange;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 62),
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 8, change == null ? 14 : 4, 8),
        child: Row(
          children: [
            QuestRing(value: quest.fraction),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FitText(
                    quest.text.resolve(context),
                    maxLines: 2,
                    minFontSize: 11,
                    wholeWords: true,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: done ? AppTheme.textSecondary : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${formatXp(quest.progress)} / ${formatXp(quest.threshold)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textSecondary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              l10n.questXp(quest.xp),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: done ? AppTheme.textTertiary : AppTheme.playerBlueBright,
              ),
            ),
            if (change != null)
              Semantics(
                button: true,
                label: l10n.questsChangeLabel,
                excludeSemantics: true,
                child: InkResponse(
                  key: Key('quest-change-${quest.id}'),
                  radius: 20,
                  onTap: change,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.repeat_rounded, size: 18, color: AppTheme.textTertiary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A 34 pt progress ring (mockup `ring`: r 14, stroke 3.5, slate track, blue
/// arc from the top with round caps).
class QuestRing extends StatelessWidget {
  final double value;
  final double size;
  const QuestRing({super.key, required this.value, this.size = 34});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _RingPainter(value.clamp(0.0, 1.0)));
}

class _RingPainter extends CustomPainter {
  final double value;
  _RingPainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 34;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: 14 * k);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5 * k;
    canvas.drawArc(rect, 0, 2 * math.pi, false, stroke..color = AppTheme.surfaceLight);
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

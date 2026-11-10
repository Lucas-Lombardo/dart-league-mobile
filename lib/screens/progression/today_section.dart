import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/progression_provider.dart';
import '../../utils/app_theme.dart';
import 'progression_screen.dart';

/// The home "Today" block (mockup Accueil): the daily challenge row (passed
/// by Agent 2 in [leading]) and the daily quests row. Hidden while there is
/// nothing to show, so an empty or failing API never leaves a blank card.
class TodaySection extends StatelessWidget {
  final List<Widget> leading;
  /// Rows after the quests row (the weekly league row of Agent 4).
  final List<Widget> trailing;
  const TodaySection({super.key, this.leading = const [], this.trailing = const []});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final daily = maybeWatchProgression(context)?.quests?.daily;
    final rows = <Widget>[
      ...leading,
      if (daily != null && daily.quests.isNotEmpty) _QuestsRow(done: daily.done, total: daily.quests.length, xpLeft: daily.xpLeft),
      ...trailing,
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.questsToday, style: AppTheme.sectionTitle.copyWith(color: const Color(0xFFCBD5E1))),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, thickness: 1, color: AppTheme.border),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One 60 px row of the "Today" block, for the challenge row of Agent 2 too.
class TodayRow extends StatelessWidget {
  final IconData icon;
  final bool accent;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const TodayRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.accent = false,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 60,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent ? AppTheme.primaryLight.withValues(alpha: 0.14) : AppTheme.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 18, color: accent ? const Color(0xFF7DD3FC) : const Color(0xFFE2E8F0)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTheme.rowTitle.copyWith(fontWeight: FontWeight.w700)),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.caption.copyWith(fontSize: 13)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestsRow extends StatelessWidget {
  final int done;
  final int total;
  final int xpLeft;
  const _QuestsRow({required this.done, required this.total, required this.xpLeft});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TodayRow(
      icon: Icons.task_alt_rounded,
      title: l10n.questsRow,
      subtitle: done >= total ? l10n.questsAllDone : l10n.questsRowSubtitle(done, total, xpLeft),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            Container(
              width: 14,
              height: 6,
              margin: const EdgeInsets.only(left: 3),
              decoration: BoxDecoration(
                color: i < done ? AppTheme.primaryLight : AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
        ],
      ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProgressionScreen())),
    );
  }
}


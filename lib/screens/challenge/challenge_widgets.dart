import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../utils/rank_translation.dart';
import '../../widgets/progression/progression_widgets.dart';
import 'challenge_models.dart';
import 'logic/challenge_strategy.dart';

/// Tokens of the challenge mockups (design system D).
class ChallengeColors {
  static const text = Color(0xFFF8FAFC);
  static const soft = Color(0xFFCBD5E1);
  static const softer = Color(0xFFE2E8F0);
  static const muted = Color(0xFF94A3B8);
  static const accent = Color(0xFF38BDF8);
  static const accentLight = Color(0xFF7DD3FC);
  static const accentWash = Color(0x2438BDF8); // rgba(56,189,248,.14)
  static const slate700 = Color(0xFF334155);
  static const success = Color(0xFF4ADE80);
  static const successWash = Color(0x2922C55E);
  /// Gold is reserved for the crown.
  static const crown = Color(0xFFEAB308);
  static const story = Color(0xFF0B1222);
}

/// "Lundi 10 novembre" / "Monday 10 November" from a YYYY-MM-DD key.
String challengeDayLabel(BuildContext context, String date, {bool short = false}) {
  final d = DateTime.tryParse(date);
  if (d == null) return date;
  final locale = Localizations.localeOf(context).toString();
  final text = DateFormat(short ? 'd MMM' : 'EEEE d MMMM', locale).format(d);
  return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}

/// "2ᵉ" / "2nd".
String challengeOrdinal(BuildContext context, int n) {
  if (Localizations.localeOf(context).languageCode == 'fr') {
    return n == 1 ? '1ᵉʳ' : '$nᵉ';
  }
  final mod100 = n % 100;
  final suffix = (mod100 >= 11 && mod100 <= 13)
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}

/// Name of a board: "Platinum", or "Diamond · Master" (they play together).
String challengeBoardName(AppLocalizations l10n, String rank) {
  if (rank == 'diamond' || rank == 'master') {
    return '${RankTranslation.translate(l10n, 'diamond')} · ${RankTranslation.translate(l10n, 'master')}';
  }
  return RankTranslation.translate(l10n, rank);
}

/// "14 h 22" until [end].
String challengeTimeLeft(AppLocalizations l10n, DateTime? end) {
  if (end == null) return '';
  final d = end.difference(DateTime.now());
  if (d.isNegative) return l10n.challengeMinutes(0);
  if (d.inHours >= 1) return l10n.challengeHoursMinutes(d.inHours, d.inMinutes % 60);
  return l10n.challengeMinutes(d.inMinutes);
}

/// A rounded tag of the mockups ("+50 XP", "session filmée").
class ChallengeChip extends StatelessWidget {
  final String label;
  final bool accent;
  final IconData? icon;
  final double fontSize;
  const ChallengeChip({super.key, required this.label, this.accent = false, this.icon, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    final color = accent ? ChallengeColors.accentLight : ChallengeColors.soft;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * 0.85, vertical: fontSize * 0.42),
      decoration: BoxDecoration(
        color: accent ? ChallengeColors.accentWash : AppTheme.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: fontSize + 1, color: color), const SizedBox(width: 5)],
          Text(label, style: TextStyle(fontSize: fontSize, fontWeight: accent ? FontWeight.w800 : FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}

/// Flame + "12 j" (the streak), a 40 pt header button (mockup DefB1).
class ChallengeStreakPill extends StatelessWidget {
  final int days;
  final VoidCallback? onTap;
  const ChallengeStreakPill({super.key, required this.days, this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: onTap != null,
      label: l10n.challengeSStreakLabel(days),
      excludeSemantics: true,
      child: Material(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_fire_department_outlined, size: 17, color: ChallengeColors.accent),
                const SizedBox(width: 6),
                Text(
                  l10n.challengeStreakDays(days),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 18:00 reminder in the header: a full bell when on, struck through when off.
class ChallengeRemindBell extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;
  const ChallengeRemindBell({super.key, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      toggled: on,
      label: l10n.challengeRemind,
      excludeSemantics: true,
      child: Material(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox.square(
            dimension: 40,
            child: Icon(
              on ? Icons.notifications_rounded : Icons.notifications_off_outlined,
              size: 19,
              color: on ? ChallengeColors.accentLight : ChallengeColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// The three-way switch of the leaderboard (rank / all / friends).
class ChallengeTabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const ChallengeTabs({super.key, required this.labels, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: i == selected,
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onSelect(i),
                  child: Container(
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? ChallengeColors.slate700 : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: i == selected ? ChallengeColors.text : ChallengeColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One line of a challenge leaderboard (46 px, mockup DefiEcran).
class ChallengeRowTile extends StatelessWidget {
  final ChallengeRow row;
  final ChallengeFormat? format;
  const ChallengeRowTile({super.key, required this.row, this.format});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: row.me ? Border.all(color: ChallengeColors.accent, width: 1.5) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '${row.position}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ChallengeColors.muted, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
          FramedAvatar(rank: row.rank, cosmetics: row.cosmetics, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(row.username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                if (row.crown) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.workspace_premium_outlined, size: 16, color: ChallengeColors.crown, semanticLabel: l10n.challengeCrownLabel),
                ],
              ],
            ),
          ),
          Text(
            challengeScoreText(format, row.score, finished: row.finished, unfinished: l10n.challengeUnfinished),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ChallengeColors.softer, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}

/// The square header buttons of the mockups (back, close).
class ChallengeHeaderButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  const ChallengeHeaderButton({super.key, required this.icon, required this.semanticLabel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Icon(icon, size: 20, color: ChallengeColors.text),
        ),
      ),
    );
  }
}

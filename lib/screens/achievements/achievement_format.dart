import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../progression/progression_format.dart';
import 'achievement_models.dart';

/// "Bronze" / "Argent" / "Or" (a unique achievement reads "Débloqué").
String achievementTierName(AppLocalizations l10n, String? tier) => switch (tier) {
      'bronze' => l10n.achievementTierBronze,
      'silver' => l10n.achievementTierSilver,
      'gold' => l10n.achievementTierGold,
      'unique' => l10n.achievementTierUnique,
      _ => l10n.achievementLocked,
    };

bool _isFr(BuildContext context) => Localizations.localeOf(context).languageCode == 'fr';

/// A counter value as the achievement reads it: "1 000", "52,4", "60 %".
String formatAchievementValue(BuildContext context, double value, String format) {
  final fr = _isFr(context);
  switch (format) {
    case 'decimal':
      final s = (value * 10).round() / 10;
      final text = s == s.roundToDouble() ? s.round().toString() : s.toStringAsFixed(1);
      return fr ? text.replaceAll('.', ',') : text;
    case 'percent':
      return fr ? '${value.round()} %' : '${value.round()}%';
    default:
      return formatXp(value.round());
  }
}

/// The share of active players: "9", "0,4" (one decimal under 1 %).
String formatRarity(BuildContext context, double pct) {
  final text = pct < 1 ? pct.toStringAsFixed(1) : pct.round().toString();
  return _isFr(context) ? text.replaceAll('.', ',') : text;
}

/// What a step asks for: its label for a league / rank, else its number.
String achievementStepTarget(BuildContext context, AchievementStep step, String format) =>
    step.label?.resolve(context) ?? formatAchievementValue(context, step.threshold, format);

String achievementNextTarget(BuildContext context, AchievementNext next, String format) =>
    next.label?.resolve(context) ?? formatAchievementValue(context, next.threshold, format);

/// "37 / 100", "best 287 / 300", the reached league for ordinal ones, and
/// "16 → 15" (my best, then the target) when lower is better.
String achievementProgress(BuildContext context, Achievement a) {
  final l10n = AppLocalizations.of(context);
  final next = a.next;
  final value = formatAchievementValue(context, a.value, a.format);
  if (a.format == 'ordinal') {
    final reached = a.steps.where((s) => s.done).toList();
    return reached.isEmpty ? '—' : (reached.last.label?.resolve(context) ?? value);
  }
  if (next == null) return value;
  final target = achievementNextTarget(context, next, a.format);
  if (a.lowerIsBetter) return '${a.value > 0 ? value : '—'} → $target';
  if (a.aggregate == 'streak' && (a.best ?? 0) > a.value) {
    return '$value / $target · ${l10n.achievementRecord(formatAchievementValue(context, a.best!, a.format))}';
  }
  return '$value / $target';
}

/// The tile's last line in the collection: progress towards the next tier,
/// else how rare the tier I hold is. Written for two lines: no-break spaces
/// keep "412 / 1 000" and "pour l'Or" whole, so the line breaks between
/// them, never inside.
String achievementTileNote(BuildContext context, Achievement a) {
  final l10n = AppLocalizations.of(context);
  final next = a.next;
  final rarity = a.tierRarity;
  if (next == null || (!a.unlocked && a.value <= 0 && !a.lowerIsBetter)) {
    if (rarity != null) return l10n.achievementRarity(formatRarity(context, rarity)).replaceAll(' %', '\u00A0%');
    return next == null ? '' : _unbroken('0 / ${achievementNextTarget(context, next, a.format)}');
  }
  final progress = _unbroken(achievementProgress(context, a));
  if (a.lowerIsBetter || !a.unlocked || a.format == 'ordinal') return progress;
  final note = switch (next.tier) {
    'silver' => l10n.achievementForSilver(progress),
    'gold' => l10n.achievementForGold(progress),
    _ => l10n.achievementForBronze(progress),
  };
  // The words around the value ("pour l'Or") stay together too; the spaces
  // next to the value are the only breaks left.
  final at = note.indexOf(progress);
  if (at < 0) return note;
  return '${_unbroken(note.substring(0, at), keepEnds: true)}$progress'
      '${_unbroken(note.substring(at + progress.length), keepEnds: true)}';
}

/// [s] with no-break spaces: one word for the line breaker. " · " stays a
/// break ("6 / 7 · record 31"), and so do the outer spaces with [keepEnds].
String _unbroken(String s, {bool keepEnds = false}) {
  if (keepEnds) {
    final lead = s.length - s.trimLeft().length;
    final tail = s.length - s.trimRight().length;
    if (lead + tail >= s.length) return s;
    return s.substring(0, lead) + _unbroken(s.trim()) + s.substring(s.length - tail);
  }
  return s.split(' · ').map((part) => part.replaceAll(' ', '\u00A0')).join(' · ');
}

/// "4 October" / "4 octobre".
String formatAchievementDate(BuildContext context, DateTime date) =>
    DateFormat('d MMMM', Localizations.localeOf(context).toString()).format(date);

/// "yesterday, 21:14"-like stamp for the latest occurrences.
String formatAchievementWhen(BuildContext context, DateTime date) {
  final locale = Localizations.localeOf(context).toString();
  return '${DateFormat('EEE d MMM', locale).format(date)} · ${DateFormat('HH:mm', locale).format(date)}';
}

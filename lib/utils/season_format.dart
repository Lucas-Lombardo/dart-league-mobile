import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

/// Shared formatting for the season screens: countdown and dates, in the
/// user's locale (dates are stored in UTC and shown in local time).

/// "9 j 14 h" / "3 h 05 min" / "12 min". Null duration → "end to be announced".
String formatSeasonCountdown(AppLocalizations l10n, Duration? left) {
  if (left == null) return l10n.seasonEndToBeAnnounced;
  final d = left.inDays;
  final h = left.inHours % 24;
  final m = left.inMinutes % 60;
  if (d > 0) return l10n.seasonDurationDaysHours(d, h);
  if (left.inHours > 0) return l10n.seasonDurationHoursMinutes(left.inHours, m);
  return l10n.seasonDurationMinutes(m);
}

String _locale(BuildContext context) =>
    Localizations.localeOf(context).toLanguageTag();

/// The instant the next season starts, for display: an end set at 23:59
/// reads as "starts on the 1st", not "on the 31st". Same instant, next
/// minute.
DateTime seasonStartAfter(DateTime end) => end.add(const Duration(minutes: 1));

/// "22 août" / "Aug 22".
String formatSeasonDay(BuildContext context, DateTime date) =>
    DateFormat.MMMd(_locale(context)).format(date.toLocal());

/// "1er sept." — short month, used where space is tight.
String formatSeasonDayShort(BuildContext context, DateTime date) {
  final local = date.toLocal();
  final text = DateFormat.MMMd(_locale(context)).format(local);
  return _ordinalizeFirst(context, local, text);
}

/// "31 juillet 2026" / "July 31, 2026".
String formatSeasonDate(BuildContext context, DateTime date) =>
    DateFormat.yMMMMd(_locale(context)).format(date.toLocal());

/// "1er septembre" / "September 1".
String formatSeasonDayLong(BuildContext context, DateTime date) {
  final local = date.toLocal();
  final text = DateFormat.MMMMd(_locale(context)).format(local);
  return _ordinalizeFirst(context, local, text);
}

/// "1 → 31 août" when both ends share a month, else "22 août → 30 sept.".
String formatSeasonRange(BuildContext context, DateTime start, DateTime end) {
  final s = start.toLocal();
  final e = end.toLocal();
  if (s.year == e.year && s.month == e.month) {
    return '${s.day} → ${formatSeasonDay(context, e)}';
  }
  return '${formatSeasonDay(context, s)} → ${formatSeasonDay(context, e)}';
}

// French says "1er septembre", never "1 septembre".
String _ordinalizeFirst(BuildContext context, DateTime local, String text) {
  if (local.day != 1) return text;
  if (Localizations.localeOf(context).languageCode != 'fr') return text;
  return text.replaceFirst(RegExp(r'^1(?=\s)'), '1er');
}

import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';

/// 1040 → "1 040" (French spacing in both languages keeps the UI uniform).
String formatXp(int value) {
  final s = value.abs().toString();
  final b = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// "9 h", "3 d", "12 min".
String formatRemaining(AppLocalizations l10n, Duration d) {
  if (d.inDays >= 1) return l10n.durationDaysShort(d.inDays);
  if (d.inHours >= 1) return l10n.durationHoursShort(d.inHours);
  return l10n.durationMinutesShort(d.inMinutes < 1 ? 1 : d.inMinutes);
}

/// "card frame" / "cadre de carte", for "Level 15: card frame Brass".
String itemKindLabel(AppLocalizations l10n, ItemType type) => switch (type) {
      ItemType.avatar => l10n.itemKindAvatar,
      ItemType.frame => l10n.itemKindFrame,
      ItemType.background => l10n.itemKindBackground,
      ItemType.title => l10n.itemKindTitle,
      ItemType.flight => l10n.itemKindFlight,
      ItemType.badge => l10n.itemKindBadge,
      ItemType.unknown => '',
    };

String itemKindAndName(BuildContext context, ItemDef item) {
  final l10n = AppLocalizations.of(context);
  return '${itemKindLabel(l10n, item.type)} ${item.name.resolve(context)}';
}

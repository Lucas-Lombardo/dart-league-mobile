import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../widgets/home_tiles.dart';

/// « Jouer autrement » on the home (mockup AccFinal, CONTRACT §14.12): three
/// tiles of the same 56 pt height — « Contre un ami » and « Match local » on
/// the first row, « Entraînement » across the second. No ghost tile: the
/// ghost is only offered by the ranked queue after 5 min without an
/// opponent. Each tile shows the XP it pays (GET /progression/content → xp).
class HomeOtherModes extends StatelessWidget {
  final XpRules? xp;

  /// Premium (or the Free Play window) is required to invite a friend: the
  /// crown says so before the tap, which opens the paywall.
  final bool friendLocked;
  final VoidCallback? onFriend;
  final VoidCallback? onLocal;
  final VoidCallback? onTraining;

  const HomeOtherModes({
    super.key,
    this.xp,
    this.friendLocked = false,
    this.onFriend,
    this.onLocal,
    this.onTraining,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String? gain(int? v) => v == null ? null : l10n.homeXpGain(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HomeSectionTitle(l10n.homePlayOtherWays),
        HomeTileRow(
          children: [
            HomeModeTile(
              icon: const Icon(Icons.people_outline_rounded),
              label: l10n.friendModeTitle,
              xp: gain(xp?.friendly),
              premium: friendLocked,
              onTap: onFriend,
            ),
            HomeModeTile(
              icon: const Icon(Icons.smartphone_outlined),
              label: l10n.localModeTitle,
              xp: l10n.homeNoXp,
              mutedXp: true,
              onTap: onLocal,
            ),
          ],
        ),
        const SizedBox(height: 10),
        HomeTileRow(
          children: [
            HomeModeTile(
              icon: const Icon(Icons.fitness_center_rounded),
              label: l10n.trainingPlayCardTitle,
              xp: gain(xp?.training),
              onTap: onTraining,
            ),
          ],
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../spectate/spectate_hub_screen.dart';

/// The blue of the Compétitif block — the one blue block of the home.
const Color kCompetitiveBlue = Color(0xFF0369A1);

/// « Compétitif » on the home (mockup AccFinal, generator `k1()`): 134 pt,
/// the only blue block. The top part is the play slot — rank badge,
/// « Compétitif · #17 », the ELO, a white bar to the next rank and
/// « Platine dans 191 pts », a white « Jouer » with its XP under it — and
/// the 40 pt strip at the bottom shows the live ranked matches.
///
/// Every state that takes the play slot (placement, a match to resume, a
/// tournament match, a friend's invite, ranked locked) renders through the
/// same geometry: [leading] is the rank badge or an icon disc, [value] the
/// ELO (large) or a short title.
class CompetitiveCard extends StatelessWidget {
  final Widget leading;
  final String label;
  final String value;

  /// 24 / 800 for a number (ELO, « 2 / 4 »), 18 / 800 for a title.
  final bool largeValue;

  /// The white bar; null hides it.
  final double? progress;
  final String? caption;
  final String actionLabel;

  /// « +60 XP » under the button; null leaves it out.
  final String? actionXp;

  /// Null: the slot is locked (no button press, a lock instead of the arrow).
  final VoidCallback? onTap;

  /// Live ranked series, and every live match (tournaments too).
  final int liveRanked;
  final int liveTotal;

  const CompetitiveCard({
    super.key,
    required this.leading,
    required this.label,
    required this.value,
    this.largeValue = true,
    this.progress,
    this.caption,
    required this.actionLabel,
    this.actionXp,
    this.onTap,
    this.liveRanked = 0,
    this.liveTotal = 0,
  });

  static const double height = 134;

  /// The rank badge, 58 pt, pulled into the left padding like the mockup.
  static Widget rankImage(String asset) => Transform.translate(
        offset: const Offset(-6, 0),
        child: Image.asset(
          asset,
          width: 58,
          height: 58,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const SizedBox.square(dimension: 58),
        ),
      );

  /// A white icon in a translucent disc, for the event states.
  static Widget iconDisc(IconData icon) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.16)),
        child: Icon(icon, size: 22, color: Colors.white),
      );

  @override
  Widget build(BuildContext context) {
    final locked = onTap == null;
    final top = InkWell(
      onTap: locked
          ? null
          : () {
              HapticService.mediumImpact();
              onTap!();
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            SizedBox(width: 48, child: OverflowBox(maxWidth: 58, maxHeight: 58, alignment: Alignment.centerLeft, child: leading)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFBAE6FD)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: largeValue ? 24 : 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: largeValue ? -0.48 : -0.2,
                      height: 1.1,
                      color: Colors.white,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: SizedBox(
                        height: 4,
                        child: ColoredBox(
                          color: Colors.white.withValues(alpha: 0.25),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: progress!.clamp(0.0, 1.0),
                              heightFactor: 1,
                              child: const ColoredBox(color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (caption != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFE0F2FE)),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PlayButton(label: actionLabel, locked: locked),
                if (actionXp != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    actionXp!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFE0F2FE)),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
    return SizedBox(
      height: height,
      child: Material(
        color: kCompetitiveBlue,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: top),
            _LiveStrip(ranked: liveRanked, total: liveTotal),
          ],
        ),
      ),
    );
  }
}

/// The white button (decorative: the whole top part is the tap target).
class _PlayButton extends StatelessWidget {
  final String label;
  final bool locked;
  const _PlayButton({required this.label, required this.locked});

  @override
  Widget build(BuildContext context) {
    final fg = locked ? Colors.white : kCompetitiveBlue;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: locked ? Colors.white.withValues(alpha: 0.18) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: fg)),
          const SizedBox(width: 4),
          Icon(locked ? Icons.lock_outline_rounded : Icons.chevron_right_rounded, size: locked ? 15 : 18, color: fg),
        ],
      ),
    );
  }
}

/// « 3 matchs classés en direct · Regarder › » → the live hub; with nothing
/// live, the same 40 pt with a quiet line (not tappable).
class _LiveStrip extends StatelessWidget {
  final int ranked;
  final int total;
  const _LiveStrip({required this.ranked, required this.total});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final live = total > 0 || ranked > 0;
    final text = ranked > 0
        ? l10n.homeLiveRanked(ranked)
        : total > 0
            ? '$total ${l10n.spectateMatchesLive(total)}'
            : l10n.homeLiveNone;
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: live ? AppTheme.secondary : Colors.white.withValues(alpha: 0.35),
              boxShadow: live ? [BoxShadow(color: AppTheme.secondary.withValues(alpha: 0.25), spreadRadius: 4)] : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: live ? Colors.white : Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
          if (live) ...[
            const SizedBox(width: 10),
            Text(l10n.spectateWatch, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
            const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white),
          ],
        ],
      ),
    );
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0x29020617),
        border: Border(top: BorderSide(color: Color(0x2EFFFFFF))),
      ),
      child: live
          ? InkWell(
              onTap: () {
                HapticService.lightImpact();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SpectateHubScreen()));
              },
              child: row,
            )
          : row,
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/rank_utils.dart';
import 'metal.dart';
import 'progression_widgets.dart';

/// The player card validated on 8 nov. 2026 (mockups AccFinal / AccFierte,
/// direction « S1 · Carte de collection », generator `s1()` in
/// docs/progression/svg/gen_accueil8.py).
///
/// 150 pt high at any width: a 3 pt rim in the gradient of the equipped
/// frame's metal (steel without a frame), the equipped background in full
/// under a dark veil (90 % on the left, 12 % on the right), the avatar in a
/// 92 pt ring of the same metal, the name (22 / 800, crown when premium),
/// the title on a plate of the metal, up to 3 pinned badges, and the level
/// in a hexagon of the metal with the prestige stars above it. [onEdit]
/// adds « Modifier » (own card only). [footer] goes under the art, inside
/// the rim (the home's XP bar and quest strip).
///
/// Sober on purpose: no glow, nothing animates; gold only comes from the
/// equipped metal or the premium crown.
class PlayerShowcaseCard extends StatelessWidget {
  final String username;

  /// The rank badge stands in for a missing avatar; null when the rank is
  /// unknown (a wrong badge is worse than none): the name's initial then.
  final String? rank;
  final PublicCosmetics? cosmetics;
  final bool isPremium;

  /// The level in the hexagon; defaults to [cosmetics]' level. No hexagon
  /// when neither is known (a server without progression).
  final int? level;
  final VoidCallback? onEdit;
  final Widget? footer;

  /// The validated size: 358 × 150 on a 390 pt screen.
  static const double designWidth = 358;
  static const double artHeight = 150;
  static const double rim = 3;

  const PlayerShowcaseCard({
    super.key,
    required this.username,
    this.rank,
    this.cosmetics,
    this.isPremium = false,
    this.level,
    this.onEdit,
    this.footer,
  });

  /// Light text on a dark metal (obsidian), dark text on a light one: by the
  /// mean luminance of the three stops.
  static bool isDarkMetal(List<Color> metal) =>
      metal.fold<double>(0, (s, c) => s + c.computeLuminance()) / metal.length < 0.2;

  @override
  Widget build(BuildContext context) {
    final content = watchProgressionContent(context);
    final c = cosmetics;
    final frame = content?.item(c?.frame);
    final frameItem = frame?.type == ItemType.frame ? frame : null;
    final metal = MetalPalette.of(content, frameItem?.metal ?? 'acier');
    final background = content?.item(c?.background);
    final shownLevel = level ?? c?.level;
    final stars = shownLevel == null ? 0 : (content?.prestigeStars(frameItem?.id, shownLevel) ?? 0);
    final title = TitleText.nameOf(context, c?.title);
    final badges = (c?.badges ?? const <PublicBadge>[]).take(3).toList();

    final art = SizedBox(
      height: artHeight,
      child: Stack(
        // The row takes the full 150 pt, so the avatar stays centred even
        // without a level hexagon (cosmetics unknown: an older server, or
        // match_found's cosmetics lookup timing out).
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: background != null && background.type == ItemType.background
                ? ProgressionAssetView(
                    item: background,
                    fit: BoxFit.cover,
                    fallback: CustomPaint(painter: TexturePainter.of(background)),
                  )
                : const ColoredBox(color: AppTheme.surface),
          ),
          if (background != null && background.type == ItemType.background)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xE60A0E18), Color(0xB30A0E18), Color(0x1F0A0E18)],
                    stops: [0, 0.5, 1],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _ShowcaseAvatar(username: username, rank: rank, cosmetics: c, metal: metal),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.44,
                                height: 1.15,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (isPremium) ...[
                            const SizedBox(width: 6),
                            PremiumCrown(
                              size: 15,
                              semanticLabel: AppLocalizations.of(context).premiumBadgeLabel,
                            ),
                          ],
                        ],
                      ),
                      if (title != null) ...[
                        const SizedBox(height: 7),
                        _TitlePlate(title: title, metal: metal),
                      ],
                      if (badges.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            for (var i = 0; i < badges.length; i++) ...[
                              if (i > 0) const SizedBox(width: 6),
                              _PinnedBadge(badge: badges[i], ring: metal[1]),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (shownLevel != null) ...[
                  const SizedBox(width: 14),
                  SizedBox(
                    height: artHeight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        children: [
                          if (stars > 0) ...[
                            PrestigeStars(count: stars, metal: frameItem?.metal, size: 14, maxDrawn: 3),
                            const SizedBox(height: 2),
                          ],
                          LevelHexagon(level: shownLevel, metal: metal),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onEdit != null)
            Positioned(right: 10, bottom: 10, child: _EditButton(onTap: onEdit!)),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(rim),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        gradient: metalGradient(metal),
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 28, offset: Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard - rim),
        child: ColoredBox(
          color: const Color(0xFF0B1220),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [art, ?footer],
          ),
        ),
      ),
    );
  }
}

/// The metal of the mockups: 3 stops at 0 / 52 / 100 %, 135° by default.
LinearGradient metalGradient(
  List<Color> metal, {
  Alignment begin = Alignment.topLeft,
  Alignment end = Alignment.bottomRight,
}) =>
    LinearGradient(begin: begin, end: end, colors: metal, stops: const [0, 0.52, 1]);

class _ShowcaseAvatar extends StatelessWidget {
  final String username;
  final String? rank;
  final PublicCosmetics? cosmetics;
  final List<Color> metal;
  const _ShowcaseAvatar({required this.username, required this.rank, required this.cosmetics, required this.metal});

  static const double size = 92;
  static const double inner = size - 8;

  @override
  Widget build(BuildContext context) {
    final item = watchProgressionContent(context)?.item(cosmetics?.avatar);
    final Widget face;
    if (item != null && item.type == ItemType.avatar) {
      face = PlayerAvatar(rank: rank ?? 'unranked', cosmetics: cosmetics, size: inner);
    } else if (rank != null) {
      // No avatar: the rank badge, on the card's dark ground.
      face = DecoratedBox(
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0B1220)),
        child: Center(child: RankUtils.getRankBadge(rank!, size: inner * 0.74)),
      );
    } else {
      face = InitialAvatar(name: username, size: inner);
    }
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: metalGradient(metal),
        boxShadow: const [BoxShadow(color: Color(0x73000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: ClipOval(child: SizedBox.square(dimension: inner, child: face)),
    );
  }
}

/// The equipped title on a small plate of the metal (gradient top → bottom,
/// a light hairline on its top edge).
class _TitlePlate extends StatelessWidget {
  final String title;
  final List<Color> metal;
  const _TitlePlate({required this.title, required this.metal});

  @override
  Widget build(BuildContext context) {
    final dark = PlayerShowcaseCard.isDarkMetal(metal);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: metalGradient(metal, begin: Alignment.topCenter, end: Alignment.bottomCenter),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                  color: dark ? AppTheme.textPrimary : const Color(0xFF1A1406),
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 1,
            child: ColoredBox(color: Color(0x66FFFFFF)),
          ),
        ],
      ),
    );
  }
}

/// A pinned badge (24 pt) with a hairline of the metal around it.
class _PinnedBadge extends StatelessWidget {
  final PublicBadge badge;
  final Color ring;
  const _PinnedBadge({required this.badge, required this.ring});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: ring, spreadRadius: 1.5),
          const BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: BadgeMedal(badge: badge, size: 24),
    );
  }
}

class _EditButton extends StatelessWidget {
  final VoidCallback onTap;
  const _EditButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: l10n.homeEditCardLabel,
      excludeSemantics: true,
      child: Material(
        color: const Color(0xB80A0E18),
        shape: const StadiumBorder(side: BorderSide(color: Color(0x4DF8FAFC))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticService.lightImpact();
            onTap();
          },
          child: SizedBox(
            height: 28,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.edit_outlined, size: 12, color: AppTheme.textPrimary),
                  const SizedBox(width: 5),
                  Text(
                    l10n.homeEditCard,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The level in a hexagon of the metal: the number, then « NIV. » in the
/// metal's light stop (the mockup's 100 × 110 view box, at 58 × 64).
class LevelHexagon extends StatelessWidget {
  final int level;
  final List<Color> metal;
  final double width;
  const LevelHexagon({super.key, required this.level, required this.metal, this.width = 58});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      label: l10n.xpLevelShort(level),
      excludeSemantics: true,
      child: CustomPaint(
        size: Size(width, width * 1.1),
        painter: _HexPainter(level: level, metal: metal, levelLabel: l10n.homeLevelHexLabel),
      ),
    );
  }
}

class _HexPainter extends CustomPainter {
  final int level;
  final List<Color> metal;
  final String levelLabel;
  _HexPainter({required this.level, required this.metal, required this.levelLabel});

  Path _poly(List<double> pts, double s) {
    final p = Path()..moveTo(pts[0] * s, pts[1] * s);
    for (var i = 2; i < pts.length; i += 2) {
      p.lineTo(pts[i] * s, pts[i + 1] * s);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final rect = Offset.zero & size;
    final outer = _poly(const [50, 3, 95, 28, 95, 82, 50, 107, 5, 82, 5, 28], s);
    final inner = _poly(const [50, 12, 87, 33, 87, 77, 50, 98, 13, 77, 13, 33], s);
    canvas.drawPath(
      outer,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: metal,
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );
    canvas.drawPath(inner, Paint()..color = const Color(0xEB0B1220));

    void text(String t, double fontSize, Color color, double baseline, {double spacing = 0}) {
      final tp = TextPainter(
        text: TextSpan(
          text: t,
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: spacing,
            color: color,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Wider than the inner hexagon (a level of 3+ digits): scaled down.
      final maxWidth = 70 * s;
      final k = tp.width > maxWidth ? maxWidth / tp.width : 1.0;
      canvas.save();
      final base = tp.computeDistanceToActualBaseline(TextBaseline.alphabetic);
      canvas.translate(size.width / 2, baseline * s);
      canvas.scale(k);
      tp.paint(canvas, Offset(-tp.width / 2 + spacing / 2, -base));
      canvas.restore();
    }

    text('$level', 36 * s, AppTheme.textPrimary, 64);
    text(levelLabel, 11 * s, metal.first, 83, spacing: 2 * s);
  }

  @override
  bool shouldRepaint(covariant _HexPainter old) =>
      old.level != level || old.metal != metal || old.levelLabel != levelLabel;
}

/// The premium crown of the mockups (Lucide « crown », stroked in the
/// premium gold): the one gold, with the equipped metal, a card may show.
class PremiumCrown extends StatelessWidget {
  final double size;
  final Color color;
  final String? semanticLabel;
  const PremiumCrown({super.key, this.size = 15, this.color = AppTheme.accent, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final crown = CustomPaint(size: Size.square(size), painter: _CrownPainter(color: color));
    if (semanticLabel == null) return ExcludeSemantics(child: crown);
    return Semantics(label: semanticLabel, child: crown);
  }
}

class _CrownPainter extends CustomPainter {
  final Color color;
  _CrownPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    canvas.scale(s);
    // m2 4 3 12h14l3-12-6 7-4-7-4 7-6-7zm3 16h14
    final path = Path()
      ..moveTo(2, 4)
      ..lineTo(5, 16)
      ..lineTo(19, 16)
      ..lineTo(22, 4)
      ..lineTo(16, 11)
      ..lineTo(12, 4)
      ..lineTo(8, 11)
      ..close()
      ..moveTo(5, 20)
      ..lineTo(19, 20);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(2.2, 1 / s)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _CrownPainter old) => old.color != color;
}

import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import 'progression/player_showcase_card.dart';

const Color _soft = Color(0xFF7DD3FC);
const Color _muted = Color(0xFF94A3B8);

/// « Aujourd'hui », « Jouer autrement »: 15 / 700 in slate 300 (mockup AccFinal).
class HomeSectionTitle extends StatelessWidget {
  final String title;
  const HomeSectionTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(title, style: AppTheme.sectionTitle.copyWith(color: const Color(0xFFCBD5E1))),
      );
}

/// Two tiles side by side (10 pt apart); one alone takes the whole width.
class HomeTileRow extends StatelessWidget {
  final List<Widget> children;
  const HomeTileRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

const TextStyle _detailStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: _muted);

/// A 60 pt tile of « Aujourd'hui »: icon square, title, then « detail · +50 XP ».
/// [accent] draws the blue border and icon (the challenge not played yet).
class HomeTodayTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String? xp;
  final bool accent;
  final VoidCallback? onTap;

  const HomeTodayTile({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
    this.xp,
    this.accent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      height: 60,
      padding: 10,
      border: accent ? const Color(0x8C38BDF8) : Colors.transparent,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accent ? AppTheme.primaryLight.withValues(alpha: 0.14) : AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 18, color: accent ? _soft : const Color(0xFFE2E8F0)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 1),
                _TodayDetail(detail: detail, xp: xp),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// « detail · +50 XP » on one line of a 60 pt tile: the line shrinks a little
/// (12 pt down to 10) rather than cut the detail ("Cricket · 3…"); past that
/// the detail gives way (ellipsis) before the XP does.
class _TodayDetail extends StatelessWidget {
  final String detail;
  final String? xp;
  const _TodayDetail({required this.detail, this.xp});

  static const double _minSize = 10;

  @override
  Widget build(BuildContext context) {
    final head = xp == null || detail.isEmpty ? detail : '$detail · ';
    final xpStyle = _detailStyle.copyWith(fontWeight: FontWeight.w800, color: _soft);
    return LayoutBuilder(
      builder: (context, constraints) {
        var scale = 1.0;
        if (constraints.maxWidth.isFinite) {
          final painter = TextPainter(
            text: TextSpan(
              // The inherited family (Manrope), as the Texts below get it.
              style: DefaultTextStyle.of(context).style,
              children: [
                TextSpan(text: head, style: _detailStyle),
                if (xp != null) TextSpan(text: xp, style: xpStyle),
              ],
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final width = painter.width;
          painter.dispose();
          if (width > constraints.maxWidth) {
            // A hair under the exact ratio: rounding never brings the ellipsis back.
            final fit = (constraints.maxWidth - 0.5) / width;
            scale = fit < _minSize / 12 ? _minSize / 12 : fit;
          }
        }
        TextStyle sized(TextStyle s) => scale == 1 ? s : s.copyWith(fontSize: s.fontSize! * scale);
        return Row(
          children: [
            Flexible(child: Text(head, maxLines: 1, overflow: TextOverflow.ellipsis, style: sized(_detailStyle))),
            if (xp != null) Text(xp!, maxLines: 1, style: sized(xpStyle)),
          ],
        );
      },
    );
  }
}

/// A 56 pt tile of « Jouer autrement »: icon square, the mode, its XP under
/// it (grey when [mutedXp], « sans XP »), and the premium crown after the
/// XP when [premium].
class HomeModeTile extends StatelessWidget {
  final Widget icon;
  final String label;
  final String? xp;
  final bool mutedXp;
  final bool premium;
  final VoidCallback? onTap;

  const HomeModeTile({
    super.key,
    required this.icon,
    required this.label,
    this.xp,
    this.mutedXp = false,
    this.premium = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      height: 56,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(10)),
            child: IconTheme(
              data: const IconThemeData(size: 17, color: Color(0xFFE2E8F0)),
              child: Center(child: icon),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
                ),
                if (xp != null || premium) ...[
                  const SizedBox(height: 1),
                  // The premium crown follows the XP: never over the label,
                  // whatever its length.
                  Row(
                    children: [
                      if (xp != null)
                        Text(
                          xp!,
                          maxLines: 1,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: mutedXp ? _muted : _soft),
                        ),
                      if (premium) ...[
                        if (xp != null) const SizedBox(width: 6),
                        const PremiumCrown(size: 13),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TileShell extends StatelessWidget {
  final double height;
  final double padding;
  final Color border;
  final VoidCallback? onTap;
  final Widget child;
  const _TileShell({
    required this.height,
    this.padding = 12,
    this.border = Colors.transparent,
    this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Material(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusRow),
          side: BorderSide(color: border, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  HapticService.lightImpact();
                  onTap!();
                },
          child: Padding(padding: EdgeInsets.symmetric(horizontal: padding), child: child),
        ),
      ),
    );
  }
}

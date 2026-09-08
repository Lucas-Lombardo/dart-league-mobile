import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';

/// Building blocks of the visual system (2026-09). Every screen is assembled
/// from these so the app reads as one product: 40 px round icon buttons, a
/// brand header on the home tab and a "‹ Title" header elsewhere, flat cards
/// with a hairline, one gradient primary row per screen, quiet tiles, list
/// rows, status pills and a 3 px progress bar.

/// Sentence-cases a legacy ALL-CAPS label ("REJOINDRE LE MATCH" →
/// "Rejoindre le match"); the system writes everything in sentence case and
/// many l10n strings predate it. Mixed-case input is returned untouched.
String dsSentence(String s) {
  if (s.isEmpty || s != s.toUpperCase()) return s;
  final lower = s.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}

/// 40 px circular icon button on a surface disc (header actions, camera
/// controls). [badge] sits on the top-right corner.
class DsIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Widget? badge;
  final double size;
  final Color? iconColor;

  const DsIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.badge,
    this.size = 40,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = Material(
      color: AppTheme.surface,
      shape: const CircleBorder(side: BorderSide(color: AppTheme.border)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap == null
            ? null
            : () {
                HapticService.lightImpact();
                onTap!();
              },
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(icon, size: size / 2, color: iconColor ?? const Color(0xFFCBD5E1)),
          ),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    if (badge == null) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(top: -3, right: -3, child: badge!),
      ],
    );
  }
}

/// Small red counter used on icon buttons and tab items.
class DsBadge extends StatelessWidget {
  final int count;
  const DsBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.error,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.background, width: 2),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

/// Home tab header: the shield and the wordmark, actions on the right.
class DsBrandHeader extends StatelessWidget {
  final List<Widget> actions;
  const DsBrandHeader({super.key, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Image.asset(
            'assets/logo/logo-without-letters.png',
            width: 28,
            height: 28,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 10),
          const Text(
            'DART RIVALS',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
              color: AppTheme.textPrimary,
              height: 1,
            ),
          ),
          const Spacer(),
          ..._spaced(actions),
        ],
      ),
    );
  }
}

/// Every other screen: optional back chevron, a 24 / 800 title, actions.
class DsScreenHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final bool showBack;
  final VoidCallback? onBack;

  const DsScreenHeader({
    super.key,
    required this.title,
    this.actions = const [],
    this.showBack = false,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          if (showBack)
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: InkResponse(
                radius: 22,
                onTap: onBack ?? () => Navigator.of(context).maybePop(),
                child: const SizedBox(
                  width: 36,
                  height: 40,
                  child: Icon(Icons.arrow_back_ios_new_rounded,
                      size: 20, color: AppTheme.textPrimary),
                ),
              ),
            ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.displayMedium
                  .copyWith(fontSize: showBack ? 22 : 24),
            ),
          ),
          ..._spaced(actions),
        ],
      ),
    );
  }
}

List<Widget> _spaced(List<Widget> actions) {
  final out = <Widget>[];
  for (var i = 0; i < actions.length; i++) {
    if (i > 0) out.add(const SizedBox(width: 8));
    out.add(actions[i]);
  }
  return out;
}

/// Flat surface card, 20 px radius, hairline border. Tappable when [onTap]
/// is given.
class DsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final BorderSide? side;
  final double radius;

  const DsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.side,
    this.radius = AppTheme.radiusCard,
  });

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: side ?? const BorderSide(color: AppTheme.border),
    );
    return Material(
      color: color ?? AppTheme.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticService.lightImpact();
                onTap!();
              },
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// THE filled block of a screen: gradient row with an icon disc, a title, an
/// optional one-line subtitle and an arrow. [muted] renders the same row on
/// a plain surface (a locked or waiting state) and drops the arrow.
class DsPrimaryRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool muted;
  final double height;
  final Widget? trailing;

  const DsPrimaryRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.muted = false,
    this.height = 72,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final fg = muted ? AppTheme.textPrimary : Colors.white;
    final fg2 = muted ? AppTheme.textSecondary : Colors.white.withValues(alpha: 0.85);
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: muted ? null : AppTheme.primaryGradient,
        color: muted ? AppTheme.surface : null,
        borderRadius: BorderRadius.circular(AppTheme.radiusRow),
        border: muted ? Border.all(color: AppTheme.border) : null,
        boxShadow: muted
            ? null
            : [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.22),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppTheme.radiusRow),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  HapticService.mediumImpact();
                  onTap!();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: muted
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.white.withValues(alpha: 0.18),
                  ),
                  child: Icon(icon, size: 20, color: muted ? AppTheme.textSecondary : Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.titleLarge.copyWith(color: fg, height: 1.1),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.caption.copyWith(color: fg2),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null)
                  trailing!
                else if (!muted)
                  const Icon(Icons.arrow_forward_rounded, size: 22, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quiet mode tile: icon over a one-word label, 68 px.
class DsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? badge;

  /// Premium-gated mode: the tile is dimmed and carries a small lock, so the
  /// gate reads before the tap. Still tappable — the screen behind it is what
  /// sells the upgrade.
  final bool locked;

  const DsTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.badge,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final corner = badge ??
        (locked
            ? const Icon(Icons.lock_outline_rounded, size: 13, color: AppTheme.textTertiary)
            : null);
    return SizedBox(
      height: 68,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: locked ? AppTheme.textTertiary : const Color(0xFFE2E8F0),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: locked ? AppTheme.textTertiary : AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (corner != null) Positioned(top: 8, right: 8, child: corner),
          ],
        ),
      ),
    );
  }
}

/// "Matchs récents ............ Voir tout".
class DsSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const DsSectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          Expanded(child: Text(title, style: AppTheme.sectionTitle)),
          if (actionLabel != null)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onAction == null
                  ? null
                  : () {
                      HapticService.lightImpact();
                      onAction!();
                    },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryLight,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Quiet status pill: tinted background, colored 11 / 700 label, optional dot.
class DsPill extends StatelessWidget {
  final String label;
  final Color color;
  final bool dot;

  const DsPill({super.key, required this.label, this.color = AppTheme.primaryLight, this.dot = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color, height: 1),
          ),
        ],
      ),
    );
  }
}

/// Surface list row: leading, 15 / 600 title, optional 12 / 500 subtitle,
/// trailing (chevron by default).
class DsListRow extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double height;

  const DsListRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.height = 60,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        onTap: onTap,
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.rowTitle),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.caption),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing ??
                const Icon(Icons.chevron_right_rounded, size: 20, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 3 px progress hairline.
class DsProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;

  const DsProgressBar({super.key, required this.value, this.color = AppTheme.primary, this.height = 3});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Container(color: Colors.white.withValues(alpha: 0.08)),
            FractionallySizedBox(
              widthFactor: value.isNaN ? 0 : value.clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// The result square of a match row: V / D on a tinted background.
class DsResultSquare extends StatelessWidget {
  final bool won;
  final String letter;
  final double size;

  const DsResultSquare({super.key, required this.won, required this.letter, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final color = won ? AppTheme.success : AppTheme.error;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        letter,
        style: TextStyle(fontSize: size * 0.44, fontWeight: FontWeight.w700, color: color, height: 1),
      ),
    );
  }
}

/// One tab of [DsBottomBar]: a line icon, an 11 / 600 label, an optional
/// badge on the icon's corner.
class DsBottomBarItem {
  final IconData icon;
  final String label;
  final Widget? badge;
  const DsBottomBarItem({required this.icon, required this.label, this.badge});
}

/// The app's bottom bar: surface, hairline on top, four quiet tabs and the
/// brand shield on a primary disc lifted at the centre (index 2).
class DsBottomBar extends StatelessWidget {
  /// Exactly four items: indices 0, 1 (left of the shield) and 3, 4 (right).
  final List<DsBottomBarItem> items;
  final String centerLabel;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const DsBottomBar({
    super.key,
    required this.items,
    required this.centerLabel,
    required this.currentIndex,
    required this.onSelect,
  }) : assert(items.length == 4);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
          child: Row(
            children: [
              Expanded(child: _tab(0, items[0])),
              Expanded(child: _tab(1, items[1])),
              Expanded(child: _center()),
              Expanded(child: _tab(3, items[2])),
              Expanded(child: _tab(4, items[3])),
            ],
          ),
        ),
      ),
    );
  }

  void _select(int index) {
    HapticService.lightImpact();
    onSelect(index);
  }

  Widget _center() {
    final isSelected = currentIndex == 2;
    return GestureDetector(
      onTap: () => _select(2),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            // The disc is lifted above the bar; Positioned keeps the column's
            // layout height at 48 like the other tabs.
            Positioned(
              top: -24,
              child: Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppTheme.primaryGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Image.asset(
                    'assets/logo/logo-without-letters.png',
                    width: 30,
                    height: 30,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              child: Text(
                centerLabel,
                maxLines: 1,
                style: TextStyle(
                  color: isSelected ? AppTheme.primaryLight : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(int index, DsBottomBarItem item) {
    final isSelected = currentIndex == index;
    final color = isSelected ? AppTheme.primaryLight : AppTheme.textSecondary;
    return GestureDetector(
      onTap: () => _select(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 48,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: 28,
                  height: 24,
                  child: Center(child: Icon(item.icon, size: 22, color: color)),
                ),
                if (item.badge != null)
                  Positioned(right: -8, top: -6, child: item.badge!),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// The urgent dot variant of a badge (a pending invite).
class DsDot extends StatelessWidget {
  const DsDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: AppTheme.error,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.surface, width: 2),
      ),
    );
  }
}

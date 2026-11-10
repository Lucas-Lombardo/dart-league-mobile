import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../providers/progression_provider.dart';
import '../../services/progression_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/rank_utils.dart';
import 'metal.dart';
import 'monogram_avatar.dart';

/// Shows an item's server asset (SVG or raster) from the disk cache, or
/// [fallback] while it loads / when there is none (CONTRACT.md §10).
class ProgressionAssetView extends StatefulWidget {
  final ItemDef item;
  final Widget fallback;
  final BoxFit fit;

  const ProgressionAssetView({super.key, required this.item, required this.fallback, this.fit = BoxFit.contain});

  @override
  State<ProgressionAssetView> createState() => _ProgressionAssetViewState();
}

class _ProgressionAssetViewState extends State<ProgressionAssetView> {
  Future<File?>? _file;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ProgressionAssetView old) {
    super.didUpdateWidget(old);
    if (old.item.asset?.hash != widget.item.asset?.hash || old.item.id != widget.item.id) _resolve();
  }

  void _resolve() {
    final asset = widget.item.asset;
    _file = asset == null ? null : ProgressionAssetCache.file(asset, widget.item.id);
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.item.asset;
    if (asset == null || _file == null) return widget.fallback;
    return FutureBuilder<File?>(
      future: _file,
      builder: (context, snap) {
        final file = snap.data;
        if (file == null) return widget.fallback;
        if (asset.isSvg) {
          return SvgPicture.file(file, fit: widget.fit, placeholderBuilder: (_) => widget.fallback);
        }
        return Image.file(file, fit: widget.fit, errorBuilder: (_, _, _) => widget.fallback);
      },
    );
  }
}

/// A player's avatar: parametric monogram, emblem (asset or drawn fallback),
/// or the rank badge by default (no avatar, unknown item) — or [fallback]
/// instead of the badge, for lists that do not know the player's rank.
class PlayerAvatar extends StatelessWidget {
  final String rank;
  final PublicCosmetics? cosmetics;
  final double size;
  final Widget? fallback;

  const PlayerAvatar({super.key, required this.rank, this.cosmetics, this.size = 64, this.fallback});

  @override
  Widget build(BuildContext context) {
    final content = watchProgressionContent(context);
    final item = content?.item(cosmetics?.avatar);
    if (item == null || item.type != ItemType.avatar) {
      return fallback ?? RankUtils.getRankBadge(rank, size: size);
    }
    return SizedBox.square(
      dimension: size,
      child: ProgressionItemVisual(item: item, monogramText: cosmetics?.monogram ?? '', size: size),
    );
  }
}

/// The generic thumbnail of any item (locker, level path, level up).
class ProgressionItemVisual extends StatelessWidget {
  final ItemDef item;
  final String monogramText;
  final double size;

  const ProgressionItemVisual({super.key, required this.item, this.monogramText = 'LL', this.size = 56});

  @override
  Widget build(BuildContext context) {
    final content = watchProgressionContent(context);
    final Widget fallback = switch (item.type) {
      ItemType.avatar => item.isMonogram
          ? MonogramAvatar.fromItem(item, text: monogramText.isEmpty ? 'LL' : monogramText, size: size, content: content)
          : EmblemFallback(item: item, size: size),
      ItemType.frame => _FrameThumb(item: item, size: size),
      ItemType.background => ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.18),
          child: SizedBox.square(dimension: size, child: CustomPaint(painter: TexturePainter.of(item))),
        ),
      ItemType.flight => Center(child: FlightMarker.forItem(item, size: size * 0.8)),
      ItemType.title => _TitleThumb(item: item, size: size),
      ItemType.badge => BadgeMedal(badge: PublicBadge(id: '', badgeId: item.id, tier: item.source.tier), size: size),
      ItemType.unknown => SizedBox.square(dimension: size),
    };
    if (item.isMonogram || item.type == ItemType.title || item.type == ItemType.badge) {
      return SizedBox.square(dimension: size, child: fallback);
    }
    return SizedBox.square(
      dimension: size,
      child: ProgressionAssetView(
        item: item,
        fallback: fallback,
        fit: item.type == ItemType.background ? BoxFit.cover : BoxFit.contain,
      ),
    );
  }
}

/// Drawn stand-in for an emblem avatar until its SVG is published.
class EmblemFallback extends StatelessWidget {
  final ItemDef item;
  final double size;
  const EmblemFallback({super.key, required this.item, required this.size});

  @override
  Widget build(BuildContext context) {
    final colors = MetalPalette.of(watchProgressionContent(context), item.metal);
    final emblem = item.render['emblem'];
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: MetalPalette.gradient(colors)),
        child: Padding(
          padding: EdgeInsets.all(size * 0.06),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: Alignment(-0.16, -0.28),
                radius: 0.7,
                colors: [Color(0xFF26324A), Color(0xFF0B1222)],
              ),
            ),
            child: Center(
              child: switch (emblem) {
                '170' || 't20' => Text(
                    emblem == 't20' ? 'T20' : '170',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: size * 0.26,
                      color: colors.first,
                      letterSpacing: -0.5,
                    ),
                  ),
                'trophee' => Icon(Icons.emoji_events_outlined, size: size * 0.5, color: colors.first),
                'cible' || 'bull' => Icon(Icons.track_changes, size: size * 0.52, color: colors.first),
                'flight' => FlightMarker(colors: [colors.first, colors[1]], size: size * 0.55),
                _ => Icon(Icons.north_east, size: size * 0.48, color: colors.first),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FrameThumb extends StatelessWidget {
  final ItemDef item;
  final double size;
  const _FrameThumb({required this.item, required this.size});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size * 0.62,
        child: CardFrame(
          frameId: item.id,
          radius: size * 0.14,
          width: math.max(2, size * 0.06),
          child: const ColoredBox(color: AppTheme.surface),
        ),
      ),
    );
  }
}

class _TitleThumb extends StatelessWidget {
  final ItemDef item;
  final double size;
  const _TitleThumb({required this.item, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(size * 0.22)),
      alignment: Alignment.center,
      child: Text(
        'Aa',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.3, color: AppTheme.textPrimary),
      ),
    );
  }
}

/// The player-card border, drawn in the frame's metal (or its SVG asset on
/// top). Renders [child] untouched when there is no (known) frame.
class CardFrame extends StatelessWidget {
  final String? frameId;
  final Widget child;
  final double radius;
  final double width;

  /// The wearer's level: past 50, the Légende frame carries one prestige
  /// star every 10 levels (null = no star, e.g. a locker thumbnail).
  final int? level;

  const CardFrame({
    super.key,
    this.frameId,
    required this.child,
    this.radius = AppTheme.radiusCard,
    this.width = 2,
    this.level,
  });

  @override
  Widget build(BuildContext context) {
    final content = watchProgressionContent(context);
    final item = content?.item(frameId);
    if (item == null || item.type != ItemType.frame) return child;
    final stars = level == null ? 0 : content!.prestigeStars(item.id, level!);
    final colors = MetalPalette.of(content, item.metal);
    final corners = item.render['corners'] == true;
    final painted = CustomPaint(
      painter: _FramePainter(colors: colors, radius: radius, width: width, corners: corners),
    );
    final asset = item.asset;
    return Stack(
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
        Positioned.fill(
          child: IgnorePointer(
            child: asset == null
                ? painted
                : asset.isSvg
                    // The frame SVGs keep their border thickness at any card
                    // size: painted in 9 cells, never stretched as a whole.
                    ? _NineSliceFrameAsset(item: item, fallback: painted)
                    : ProgressionAssetView(item: item, fallback: painted, fit: BoxFit.fill),
          ),
        ),
        // Prestige: the stars sit on a small plate set into the top edge.
        if (stars > 0)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: PrestigeStars(count: stars, metal: item.metal, size: 11, plate: true),
              ),
            ),
          ),
      ],
    );
  }
}

/// Prestige stars (tour 5): one per 10 levels past 50, on the Légende frame
/// only — the one place, with premium, where gold is allowed. Static, no
/// glow: a row of engraved stars in the frame's metal, or one star and the
/// count past [maxDrawn].
class PrestigeStars extends StatelessWidget {
  final int count;
  final String? metal;
  final double size;

  /// On a dark plate (set into a frame edge); bare otherwise.
  final bool plate;
  final int maxDrawn;

  const PrestigeStars({
    super.key,
    required this.count,
    this.metal = 'legende',
    this.size = 12,
    this.plate = false,
    this.maxDrawn = 5,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final colors = MetalPalette.of(watchProgressionContent(context), metal);
    final drawn = count > maxDrawn ? 1 : count;
    Widget star() => CustomPaint(size: Size.square(size), painter: _StarPainter(colors: colors));
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < drawn; i++) ...[
          if (i > 0) SizedBox(width: size * 0.18),
          star(),
        ],
        if (count > maxDrawn) ...[
          SizedBox(width: size * 0.25),
          Text(
            '$count',
            style: TextStyle(
              fontSize: size * 0.9,
              height: 1,
              fontWeight: FontWeight.w800,
              color: colors.first,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
    if (!plate) return Semantics(label: '★ $count', child: row);
    return Semantics(
      label: '★ $count',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: size * 0.45, vertical: size * 0.2),
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(size),
          border: Border.all(color: colors[1], width: 1),
        ),
        child: row,
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  final List<Color> colors;
  _StarPainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final inner = outer * 0.45;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    final rect = Offset.zero & size;
    // The two light stops of the metal, top to bottom: a small star filled
    // with the dark middle stop reads as brown. The dark one edges it.
    final fill = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [colors.first, colors.last],
    );
    canvas.drawPath(path, Paint()..shader = fill.createShader(rect));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, size.shortestSide * 0.05)
        ..color = colors[1],
    );
  }

  @override
  bool shouldRepaint(covariant _StarPainter old) => old.colors != colors;
}

/// A frame SVG loaded once per session (by item and asset hash), then
/// painted with [NineSliceFramePainter]; [fallback] until it is ready.
class _NineSliceFrameAsset extends StatefulWidget {
  final ItemDef item;
  final Widget fallback;
  const _NineSliceFrameAsset({required this.item, required this.fallback});

  static final Map<String, Future<PictureInfo?>> _pictures = {};

  static Future<PictureInfo?> _load(ItemDef item) {
    final asset = item.asset!;
    final key = '${item.id}#${asset.hash}';
    final cached = _pictures[key];
    if (cached != null) return cached;
    final future = () async {
      try {
        final file = await ProgressionAssetCache.file(asset, item.id);
        if (file == null) return null;
        return await vg.loadPicture(SvgFileLoader(file), null);
      } catch (e) {
        debugPrint('CardFrame ${item.id}: $e');
        return null;
      }
    }();
    _pictures[key] = future;
    // Offline or broken: try again next time rather than for the session.
    future.then((p) {
      if (p == null) _pictures.remove(key);
    });
    return future;
  }

  @override
  State<_NineSliceFrameAsset> createState() => _NineSliceFrameAssetState();
}

class _NineSliceFrameAssetState extends State<_NineSliceFrameAsset> {
  late Future<PictureInfo?> _picture;

  @override
  void initState() {
    super.initState();
    _picture = _NineSliceFrameAsset._load(widget.item);
  }

  @override
  void didUpdateWidget(covariant _NineSliceFrameAsset old) {
    super.didUpdateWidget(old);
    if (old.item.id != widget.item.id || old.item.asset?.hash != widget.item.asset?.hash) {
      _picture = _NineSliceFrameAsset._load(widget.item);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PictureInfo?>(
      future: _picture,
      builder: (context, snap) {
        final info = snap.data;
        if (info == null) return widget.fallback;
        return CustomPaint(painter: NineSliceFramePainter(picture: info.picture, sourceSize: info.size));
      },
    );
  }
}

/// Paints a card-frame picture (the SVG gabarit: viewBox 240 × 150, border
/// 8, radius 14, ornaments only in the corners, transparent centre) on a
/// card of any size without thickening its sides (CONTRACT.md §14.6).
///
/// 9 cells: the four [inset] × [inset] corners at 1 unit = 1 pt, the top and
/// bottom edges stretched horizontally only, the left and right edges
/// vertically only; the empty centre is skipped. On a card smaller than two
/// corners, everything scales down evenly. Cells are clipped without
/// anti-aliasing so neighbours share every pixel exactly (no seam).
class NineSliceFramePainter extends CustomPainter {
  final ui.Picture picture;
  final Size sourceSize;
  final double inset;

  const NineSliceFramePainter({required this.picture, required this.sourceSize, this.inset = 30});

  /// Source and destination rectangles of the 8 painted cells, row by row
  /// (the centre is left out). Pure: tested on its own.
  static List<(Rect, Rect)> cells(Size source, Size target, {double inset = 30}) {
    if (source.isEmpty || target.isEmpty) return const [];
    final cut = math.min(inset, math.min(source.width, source.height) / 2);
    final scale = math.min(1.0, math.min(target.width, target.height) / (2 * cut));
    final c = cut * scale;
    final xs = [0.0, cut, source.width - cut, source.width];
    final ys = [0.0, cut, source.height - cut, source.height];
    final dx = [0.0, c, target.width - c, target.width];
    final dy = [0.0, c, target.height - c, target.height];
    final out = <(Rect, Rect)>[];
    for (var j = 0; j < 3; j++) {
      for (var i = 0; i < 3; i++) {
        if (i == 1 && j == 1) continue;
        final src = Rect.fromLTRB(xs[i], ys[j], xs[i + 1], ys[j + 1]);
        final dst = Rect.fromLTRB(dx[i], dy[j], dx[i + 1], dy[j + 1]);
        if (src.isEmpty || dst.isEmpty) continue;
        out.add((src, dst));
      }
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final (src, dst) in cells(sourceSize, size, inset: inset)) {
      canvas.save();
      canvas.clipRect(dst, doAntiAlias: false);
      canvas.translate(dst.left, dst.top);
      canvas.scale(dst.width / src.width, dst.height / src.height);
      canvas.translate(-src.left, -src.top);
      canvas.drawPicture(picture);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant NineSliceFramePainter old) =>
      old.picture != picture || old.sourceSize != sourceSize || old.inset != inset;
}

class _FramePainter extends CustomPainter {
  final List<Color> colors;
  final double radius;
  final double width;
  final bool corners;
  _FramePainter({required this.colors, required this.radius, required this.width, required this.corners});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(width / 2), Radius.circular(math.max(0, radius - width / 2)));
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = MetalPalette.gradient(colors).createShader(rect),
    );
    if (corners) {
      final d = math.max(5.0, width * 2.4);
      final paint = Paint()..color = colors.first;
      for (final c in [
        Offset(d, d),
        Offset(size.width - d, d),
        Offset(d, size.height - d),
        Offset(size.width - d, size.height - d),
      ]) {
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(math.pi / 4);
        canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: d, height: d), paint);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) =>
      old.colors != colors || old.radius != radius || old.width != width || old.corners != corners;
}

/// The card background: the item's raster texture, else a drawn stand-in,
/// else the plain surface.
class CardBackground extends StatelessWidget {
  final String? backgroundId;
  final Widget child;
  final double radius;

  const CardBackground({super.key, this.backgroundId, required this.child, this.radius = AppTheme.radiusCard});

  @override
  Widget build(BuildContext context) {
    final item = watchProgressionContent(context)?.item(backgroundId);
    if (item == null || item.type != ItemType.background) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          Positioned.fill(
            child: ProgressionAssetView(
              item: item,
              fit: BoxFit.cover,
              fallback: CustomPaint(painter: TexturePainter.of(item)),
            ),
          ),
          // Keeps text legible on bright materials (laiton, marbre…).
          const Positioned.fill(child: ColoredBox(color: Color(0x330F172A))),
          child,
        ],
      ),
    );
  }
}

/// Drawn stand-in for a background texture (render.colors + render.pattern).
class TexturePainter extends CustomPainter {
  final Color base;
  final Color accent;
  final String pattern;
  TexturePainter({required this.base, required this.accent, required this.pattern});

  factory TexturePainter.of(ItemDef item) {
    final colors = item.renderColors;
    return TexturePainter(
      base: colors.isNotEmpty ? colors[0] : AppTheme.surface,
      accent: colors.length > 1 ? colors[1] : AppTheme.surfaceLight,
      pattern: item.render['pattern'] is String ? item.render['pattern'] as String : 'plain',
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final paint = Paint()..color = accent.withValues(alpha: 0.55);
    switch (pattern) {
      case 'dots':
        for (var x = 2.0; x < size.width; x += 6) {
          for (var y = 2.0; y < size.height; y += 6) {
            canvas.drawCircle(Offset(x + ((y ~/ 6).isOdd ? 3 : 0), y), 0.9, paint);
          }
        }
      case 'stripes':
        for (var x = 0.0; x < size.width; x += 7) {
          canvas.drawRect(Rect.fromLTWH(x, 0, 3, size.height), paint);
        }
      case 'diagonal':
        paint
          ..strokeWidth = 3
          ..color = accent.withValues(alpha: 0.6);
        for (var x = -size.height; x < size.width; x += 6) {
          canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), paint);
        }
      case 'marble':
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [base, accent, base, accent.withValues(alpha: 0.8), base],
              stops: const [0, 0.3, 0.31, 0.6, 1],
            ).createShader(Offset.zero & size),
        );
      default:
        break;
    }
  }

  @override
  bool shouldRepaint(covariant TexturePainter old) =>
      old.base != base || old.accent != accent || old.pattern != pattern;
}

/// The equipped title's localized name; nothing when null or unknown.
class TitleText extends StatelessWidget {
  final String? titleId;
  final TextStyle? style;
  const TitleText({super.key, this.titleId, this.style});

  static String? nameOf(BuildContext context, String? titleId) {
    final item = watchProgressionContent(context)?.item(titleId);
    if (item == null || item.type != ItemType.title) return null;
    return item.name.resolve(context);
  }

  @override
  Widget build(BuildContext context) {
    final name = nameOf(context, titleId);
    if (name == null) return const SizedBox.shrink();
    return Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
  }
}

/// The "Niv. 14" pill.
class LevelChip extends StatelessWidget {
  final int level;
  final bool compact;
  const LevelChip({super.key, required this.level, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 7, vertical: 2),
      decoration: BoxDecoration(color: AppTheme.surfaceLight, borderRadius: BorderRadius.circular(999)),
      child: Text(
        l10n.xpLevelShort(level),
        style: TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w800,
          color: const Color(0xFFE2E8F0),
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A badge medal: ring in the tier's metal, the badge asset inside (or a glyph).
class BadgeMedal extends StatelessWidget {
  final PublicBadge badge;
  final double size;

  /// Not earned yet: grey ring, dimmed face (achievements collection, Agent 3).
  final bool locked;
  const BadgeMedal({super.key, required this.badge, this.size = 40, this.locked = false});

  static const _monthsFr = ['JANV', 'FÉVR', 'MARS', 'AVR', 'MAI', 'JUIN', 'JUIL', 'AOÛT', 'SEPT', 'OCT', 'NOV', 'DÉC'];
  static const _monthsEn = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  /// "8 NOV" for a dated badge (YYYY-MM-DD), null otherwise.
  static String? dateLabel(String? date, Locale locale) {
    final d = date == null ? null : DateTime.tryParse(date);
    if (d == null) return null;
    final months = locale.languageCode == 'fr' ? _monthsFr : _monthsEn;
    return '${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final content = watchProgressionContent(context);
    final item = content?.item(badge.badgeId);
    // The SVG assets are the medal's FACE only (one file for the three
    // tiers): the ring in the tier's metal is always drawn here, under it.
    final metal = MetalPalette.of(content, MetalPalette.forTier(locked ? null : badge.tier));
    final ring = locked ? metal.map((c) => MetalPalette.shade(c, 0.55)).toList() : metal;
    final glyph = item?.render['glyph'];
    final ringDisc = DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: MetalPalette.gradient(ring)),
    );
    final inner = Container(
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: MetalPalette.gradient(ring)),
      padding: EdgeInsets.all(size * 0.08),
      child: Container(
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF0B1222)),
        alignment: Alignment.center,
        child: glyph is String && glyph.length <= 4
            ? Text(
                glyph,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.26, color: ring.first),
              )
            : Icon(Icons.military_tech_outlined, size: size * 0.5, color: ring.first),
      ),
    );
    // badge.daily-first (and any dated badge): the date goes in the band
    // y 76–92 of the 120 viewBox, left free by the asset ("8 NOV").
    final date = dateLabel(badge.date, Localizations.maybeLocaleOf(context) ?? const Locale('en'));
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item?.asset != null) ...[
            ringDisc,
            Opacity(opacity: locked ? 0.4 : 1, child: ProgressionAssetView(item: item!, fallback: inner)),
          ] else
            Opacity(opacity: locked ? 0.6 : 1, child: inner),
          if (date != null)
            Positioned(
              left: size * 0.22,
              right: size * 0.22,
              top: size * 76 / 120,
              height: size * 16 / 120,
              child: FittedBox(
                key: const ValueKey('badge-date'),
                fit: BoxFit.scaleDown,
                child: Text(
                  date,
                  maxLines: 1,
                  style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.2, color: ring.last),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A flight seen from the front (4 wings), which replaces the white dot of a
/// dart on the virtual board. Null flight → the classic white dot look.
class FlightMarker extends StatelessWidget {
  final List<Color> colors;
  final double size;
  final double rotation;
  final bool isLatest;

  const FlightMarker({
    super.key,
    this.colors = const [Color(0xFFF8FAFC), Color(0xFF111827)],
    this.size = 22,
    this.rotation = 0,
    this.isLatest = false,
  });

  factory FlightMarker.forItem(ItemDef? item, {Key? key, double size = 22, double rotation = 0, bool isLatest = false}) {
    final colors = item?.renderColors ?? const <Color>[];
    return FlightMarker(
      key: key,
      colors: colors.length >= 2 ? colors : const [Color(0xFFF8FAFC), Color(0xFF111827)],
      size: size,
      rotation: rotation,
      isLatest: isLatest,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _FlightPainter(colors: colors, rotation: rotation, isLatest: isLatest)),
    );
  }
}

class _FlightPainter extends CustomPainter {
  final List<Color> colors;
  final double rotation;
  final bool isLatest;
  _FlightPainter({required this.colors, required this.rotation, required this.isLatest});

  @override
  void paint(Canvas canvas, Size size) {
    // reference_svg.py board marker: wing `M0 0 L-4 -13 Q0 -14.8 4 -13 Z`, ×4.
    final s = size.width / 30;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(s);
    canvas.drawCircle(const Offset(2, 2.5), 12, Paint()..color = const Color(0x59000000));
    if (isLatest) {
      canvas.drawCircle(Offset.zero, 14.5, Paint()..color = AppTheme.primaryLight.withValues(alpha: 0.28));
    }
    final wing = Path()
      ..moveTo(0, 0)
      ..lineTo(-4, -13)
      ..quadraticBezierTo(0, -14.8, 4, -13)
      ..close();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF0B1222);
    for (var j = 0; j < 4; j++) {
      canvas.save();
      canvas.rotate((rotation + j * 90) * math.pi / 180);
      canvas.drawPath(wing, Paint()..color = colors[j.isEven ? 0 : 1]);
      canvas.drawPath(wing, edge);
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, 1.8, Paint()..color = const Color(0xFF334155));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FlightPainter old) =>
      old.colors != colors || old.rotation != rotation || old.isLatest != isLatest;
}

/// The XP bar (blue fill on surfaceLight).
class XpProgressBar extends StatelessWidget {
  final int xpIntoLevel;
  final int xpToNext;
  final double height;
  const XpProgressBar({super.key, required this.xpIntoLevel, required this.xpToNext, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final v = xpToNext <= 0 ? 0.0 : (xpIntoLevel / xpToNext).clamp(0.0, 1.0);
    // The track takes the whole width it is given, the fill its whole height
    // from the left (a child-less ColoredBox left loose in a Stack had no
    // height at all, and the track shrank to the fill's width).
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: ColoredBox(
          color: AppTheme.surfaceLight,
          child: FractionallySizedBox(
            key: const Key('xp-progress-fill'),
            alignment: Alignment.centerLeft,
            widthFactor: v,
            heightFactor: 1,
            child: const ColoredBox(color: AppTheme.primaryLight),
          ),
        ),
      ),
    );
  }
}

/// A compact avatar for list rows (leaderboard, friends): the player's
/// avatar inside a thin ring in the metal of their frame; the plain avatar
/// (rank badge by default) when they wear no frame.
class FramedAvatar extends StatelessWidget {
  final String rank;
  final PublicCosmetics? cosmetics;
  final double size;

  /// Shown in place of the rank badge when no avatar is equipped (see
  /// [PlayerAvatar.fallback]); sized by the caller to [size].
  final Widget? fallback;
  const FramedAvatar({super.key, required this.rank, this.cosmetics, this.size = 36, this.fallback});

  /// Whether [cosmetics] carries an avatar or a frame this content knows:
  /// the lists that never showed an avatar (bracket, history, chat) only
  /// draw one for a player who wears something.
  static bool wearsLook(ProgressionContent? content, PublicCosmetics? cosmetics) {
    if (content == null || cosmetics == null) return false;
    return content.item(cosmetics.avatar)?.type == ItemType.avatar ||
        content.item(cosmetics.frame)?.type == ItemType.frame;
  }

  @override
  Widget build(BuildContext context) {
    final content = watchProgressionContent(context);
    final frame = content?.item(cosmetics?.frame);
    final inner = frame == null ? size : size - 5;
    final avatar = PlayerAvatar(
      rank: rank,
      cosmetics: cosmetics,
      size: inner,
      fallback: fallback == null ? null : SizedBox.square(dimension: inner, child: FittedBox(child: fallback)),
    );
    if (frame == null || frame.type != ItemType.frame) return SizedBox.square(dimension: size, child: avatar);
    final ring = Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: MetalPalette.gradient(MetalPalette.of(content, frame.metal)),
      ),
      child: avatar,
    );
    final stars = content!.prestigeStars(frame.id, cosmetics?.level ?? 0);
    if (stars <= 0) return ring;
    // Prestige: a small plate on the bottom of the ring (one star alone
    // when the avatar is too small for more).
    final starSize = (size * 0.24).clamp(6.0, 11.0);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          ring,
          Positioned(
            bottom: -starSize * 0.35,
            child: PrestigeStars(
              count: size < 26 ? 1 : stars,
              metal: frame.metal,
              size: starSize,
              plate: true,
              maxDrawn: 3,
            ),
          ),
        ],
      ),
    );
  }
}

/// A plain disc with the first letter of [name]: the face a list that does
/// not know the player's rank (bracket, history, chat) puts inside the frame
/// ring of a player who wears a frame but no avatar.
class InitialAvatar extends StatelessWidget {
  final String name;
  final double size;
  const InitialAvatar({super.key, required this.name, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.surfaceLight),
      child: Text(
        trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase(),
        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: AppTheme.textPrimary, height: 1),
      ),
    );
  }
}

/// The small avatar + frame ring next to a player's name during a match
/// (mockup EnMatch). Static: nothing animates. Uses [rank] / [cosmetics] when
/// the caller knows them, else loads the player's look once
/// (GET /progression/cosmetics) and caches it for the session.
class MatchAvatar extends StatefulWidget {
  final String? userId;
  final String? rank;
  final PublicCosmetics? cosmetics;
  final double size;

  const MatchAvatar({super.key, this.userId, this.rank, this.cosmetics, this.size = 22});

  @override
  State<MatchAvatar> createState() => _MatchAvatarState();
}

class _MatchAvatarState extends State<MatchAvatar> {
  @override
  void initState() {
    super.initState();
    _ensure();
  }

  @override
  void didUpdateWidget(covariant MatchAvatar old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _ensure();
  }

  void _ensure() {
    final id = widget.userId;
    if (id == null || (widget.cosmetics != null && widget.rank != null)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        Provider.of<ProgressionProvider>(context, listen: false).ensurePlayers([id]);
      } on ProviderNotFoundException {
        // Built outside the app tree (tests): plain rank badge.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final look = maybeWatchProgression(context)?.player(widget.userId);
    return FramedAvatar(
      rank: widget.rank ?? look?.rank ?? 'unranked',
      cosmetics: widget.cosmetics ?? look?.cosmetics,
      size: widget.size,
    );
  }
}

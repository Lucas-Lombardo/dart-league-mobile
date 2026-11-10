import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/progression.dart';
import 'metal.dart';

/// The parametric monogram medal, drawn in Flutter (no asset): metal
/// gradient, round / ecusson / hexagone shape, guilloche / cible / carbone /
/// cadran engraving, couronne / laurier ornament, gradient text.
/// Geometry follows `mono_svg` in docs/progression/svg/reference_svg.py
/// (a 120 × 120 view box).
class MonogramAvatar extends StatelessWidget {
  final String text;
  final String metal;
  final String shape;
  final String? engraving;
  final bool plate;
  final String? ornament;
  final double size;
  final ProgressionContent? content;

  const MonogramAvatar({
    super.key,
    required this.text,
    required this.metal,
    this.shape = 'round',
    this.engraving,
    this.plate = false,
    this.ornament,
    this.size = 64,
    this.content,
  });

  /// From an avatar item's `render` params.
  factory MonogramAvatar.fromItem(
    ItemDef item, {
    Key? key,
    required String text,
    double size = 64,
    ProgressionContent? content,
  }) {
    final r = item.render;
    return MonogramAvatar(
      key: key,
      text: text,
      metal: r['metal'] is String ? r['metal'] as String : 'acier',
      shape: r['shape'] is String ? r['shape'] as String : 'round',
      engraving: r['engraving'] is String ? r['engraving'] as String : null,
      plate: r['plate'] == true,
      ornament: r['ornament'] is String ? r['ornament'] as String : null,
      size: size,
      content: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = MetalPalette.of(content ?? watchProgressionContent(context), metal);
    return Semantics(
      label: text,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: MonogramPainter(
            text: text.isEmpty ? '?' : text,
            colors: colors,
            shape: shape,
            engraving: engraving,
            plate: plate,
            ornament: ornament,
          ),
        ),
      ),
    );
  }
}

class MonogramPainter extends CustomPainter {
  final String text;
  final List<Color> colors;
  final String shape;
  final String? engraving;
  final bool plate;
  final String? ornament;

  MonogramPainter({
    required this.text,
    required this.colors,
    required this.shape,
    required this.engraving,
    required this.plate,
    required this.ornament,
  });

  static const _bgTop = Color(0xFF26324A);
  static const _bgBottom = Color(0xFF0B1222);
  static const _edge = Color(0xB30B1222);

  Path _outer() {
    switch (shape) {
      case 'ecusson':
        return Path()
          ..moveTo(60, 3)
          ..lineTo(111, 17)
          ..lineTo(111, 57)
          ..quadraticBezierTo(111, 97, 60, 117)
          ..quadraticBezierTo(9, 97, 9, 57)
          ..lineTo(9, 17)
          ..close();
      case 'hexagone':
        return _hex(59);
      default:
        return Path()..addOval(Rect.fromCircle(center: const Offset(60, 60), radius: 58));
    }
  }

  Path _inner() {
    switch (shape) {
      case 'ecusson':
        return Path()
          ..moveTo(60, 12)
          ..lineTo(103, 24)
          ..lineTo(103, 57)
          ..quadraticBezierTo(103, 90, 60, 108)
          ..quadraticBezierTo(17, 90, 17, 57)
          ..lineTo(17, 24)
          ..close();
      case 'hexagone':
        return _hex(51);
      default:
        return Path()..addOval(Rect.fromCircle(center: const Offset(60, 60), radius: 50.5));
    }
  }

  static Path _hex(double r) {
    final p = Path();
    for (var i = 0; i < 6; i++) {
      final a = (i * 60 - 90) * math.pi / 180;
      final pt = Offset(60 + r * math.cos(a), 60 + r * math.sin(a));
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    return p..close();
  }

  Paint _metal(Rect rect, {double factor = 1}) =>
      Paint()..shader = MetalPalette.gradient(colors, factor: factor).createShader(rect);

  @override
  void paint(Canvas canvas, Size size) {
    final crown = ornament == 'couronne';
    // View box: 0 0 120 120, or 0 -6 120 126 with a crown on top.
    final viewH = crown ? 126.0 : 120.0;
    final scale = math.min(size.width / 120, size.height / viewH);
    canvas.save();
    canvas.translate((size.width - 120 * scale) / 2, (size.height - viewH * scale) / 2);
    canvas.scale(scale);
    if (crown) canvas.translate(0, 6);

    canvas.save();
    if (crown) {
      _scaleAround(canvas, const Offset(60, 66), 0.88, const Offset(60, 60));
    } else if (ornament == 'laurier') {
      _scaleAround(canvas, const Offset(60, 60), 0.76, const Offset(60, 60));
    }
    _paintBody(canvas);
    canvas.restore();

    if (crown) _paintCrown(canvas);
    if (ornament == 'laurier') _paintLaurel(canvas);
    canvas.restore();
  }

  void _scaleAround(Canvas canvas, Offset to, double s, Offset from) {
    canvas.translate(to.dx, to.dy);
    canvas.scale(s);
    canvas.translate(-from.dx, -from.dy);
  }

  void _paintBody(Canvas canvas) {
    const box = Rect.fromLTWH(0, 0, 120, 120);
    canvas.drawPath(_outer(), _metal(box));
    final inner = _inner();
    canvas.drawPath(
      inner,
      plate
          ? _metal(box, factor: 0.72)
          : (Paint()
            ..shader = const RadialGradient(
              center: Alignment(-0.16, -0.28),
              radius: 0.7,
              colors: [_bgTop, _bgBottom],
            ).createShader(box)),
    );
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _edge,
    );

    canvas.save();
    canvas.clipPath(inner);
    _paintEngraving(canvas);
    canvas.restore();

    _paintText(canvas);

    if (shape == 'round') {
      // SVG `M20 40 A44 44 0 0 1 48 15`: centre (60.5, 57.2), −157° → −106.5°.
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(60.5, 57.2), radius: 44),
        -2.74,
        0.88,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = const Color(0x59FFFFFF),
      );
    }
  }

  void _paintEngraving(Canvas canvas) {
    final line = plate ? const Color(0x730B1222) : const Color(0x1AFFFFFF);
    switch (engraving) {
      case 'guilloche':
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = line;
        for (var a = 0; a < 360; a += 12) {
          final r = a * math.pi / 180;
          canvas.drawCircle(Offset(60 + 7 * math.cos(r), 60 + 7 * math.sin(r)), 36, paint);
        }
      case 'cible':
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = line;
        for (final r in const [47.0, 39.0, 31.0, 23.0]) {
          canvas.drawCircle(const Offset(60, 60), r, paint);
        }
        paint.strokeWidth = 1;
        for (var a = 9; a < 369; a += 18) {
          final r = a * math.pi / 180;
          canvas.drawLine(
            Offset(60 + 23 * math.cos(r), 60 + 23 * math.sin(r)),
            Offset(60 + 50 * math.cos(r), 60 + 50 * math.sin(r)),
            paint,
          );
        }
      case 'carbone':
        canvas.save();
        canvas.translate(60, 60);
        canvas.rotate(math.pi / 4);
        const dark = Color(0xFF0E1013);
        const light = Color(0xFF3B4048);
        for (var x = -96.0; x < 96; x += 4) {
          for (var y = -96.0; y < 96; y += 4) {
            final odd = ((x + y) / 4).round().isOdd;
            canvas.drawRect(Rect.fromLTWH(x, y, 4, 4), Paint()..color = odd ? light : dark);
          }
        }
        canvas.restore();
      case 'cadran':
        final paint = Paint()
          ..strokeCap = StrokeCap.round
          ..color = plate ? const Color(0x730B1222) : const Color(0x40FFFFFF);
        for (var i = 0; i < 60; i++) {
          final major = i % 5 == 0;
          final r = i * 6 * math.pi / 180;
          paint.strokeWidth = major ? 1.8 : 0.8;
          final r1 = major ? 41.0 : 45.0;
          canvas.drawLine(
            Offset(60 + r1 * math.cos(r), 60 + r1 * math.sin(r)),
            Offset(60 + 48 * math.cos(r), 60 + 48 * math.sin(r)),
            paint,
          );
        }
      default:
        break;
    }
  }

  void _paintText(Canvas canvas) {
    final fs = text.length <= 2 ? 44.0 : (text.length == 3 ? 34.0 : 27.0);
    final baseline = 60 + fs * 0.36;
    TextPainter layout(Paint? foreground, Color? color) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: fs,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
            height: 1,
            color: foreground == null ? color : null,
            foreground: foreground,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      return tp;
    }

    void draw(TextPainter tp, double dx, double dy) {
      final metrics = tp.computeLineMetrics();
      final ascent = metrics.isEmpty ? tp.height * 0.8 : metrics.first.ascent;
      tp.paint(canvas, Offset(60 + dx - tp.width / 2, baseline + dy - ascent));
    }

    if (plate) {
      draw(layout(null, const Color(0x59FFFFFF)), 0, 1.2);
      draw(layout(null, const Color(0xFF0B1222)), 0, 0);
    } else {
      draw(layout(null, const Color(0xCC05080F)), 0.8, 1.6);
      final shader = MetalPalette.gradient(
        colors,
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(const Rect.fromLTWH(0, 38, 120, 46));
      draw(layout(Paint()..shader = shader, null), 0, 0);
    }
  }

  void _paintCrown(Canvas canvas) {
    final crown = Path()
      ..moveTo(42, 22)
      ..lineTo(39, 3)
      ..lineTo(50, 12)
      ..lineTo(60, -1)
      ..lineTo(70, 12)
      ..lineTo(81, 3)
      ..lineTo(78, 22)
      ..close();
    canvas.drawPath(crown, _metal(const Rect.fromLTWH(38, -2, 44, 25)));
    canvas.drawPath(
      crown,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFF3D2E08),
    );
    final jewel = Paint()..color = const Color(0xFFFDE68A);
    canvas.drawCircle(const Offset(39, 3), 2.4, jewel);
    canvas.drawCircle(const Offset(60, -1), 2.6, jewel);
    canvas.drawCircle(const Offset(81, 3), 2.4, jewel);
  }

  void _paintLaurel(Canvas canvas) {
    final fill = _metal(const Rect.fromLTWH(0, 0, 120, 120));
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = const Color(0x800B1222);
    for (var th = 112; th < 240; th += 20) {
      for (final t in [th, 180 - th]) {
        final r = t * math.pi / 180;
        final c = Offset(60 + 52 * math.cos(r), 60 + 52 * math.sin(r));
        final tilt = t == th ? 22 : -22;
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate((t + tilt) * math.pi / 180);
        final leaf = Rect.fromCenter(center: Offset.zero, width: 6.6, height: 16);
        canvas.drawOval(leaf, fill);
        canvas.drawOval(leaf, edge);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant MonogramPainter old) =>
      old.text != text ||
      old.colors != colors ||
      old.shape != shape ||
      old.engraving != engraving ||
      old.plate != plate ||
      old.ornament != ornament;
}

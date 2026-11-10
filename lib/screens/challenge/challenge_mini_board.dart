import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/app_theme.dart';
import '../../widgets/virtual_dartboard.dart';
import 'challenge_models.dart';

/// The small board of a format (mockups DefB1, DefFormats): the zones that
/// count in their real colours, the others in slate. Geometry and colours of
/// `board()` in docs/progression/svg/gen_defi.py (a 240-unit square).
class ChallengeMiniBoard extends StatelessWidget {
  final ChallengeBoardSpec spec;
  final double size;
  final String? semanticLabel;

  const ChallengeMiniBoard({super.key, required this.spec, this.size = 78, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final board = CustomPaint(size: Size.square(size), painter: ChallengeMiniBoardPainter(spec));
    if (semanticLabel == null) return ExcludeSemantics(child: board);
    return Semantics(image: true, label: semanticLabel, child: board);
  }
}

class ChallengeMiniBoardPainter extends CustomPainter {
  final ChallengeBoardSpec spec;
  ChallengeMiniBoardPainter(this.spec);

  static const double _unit = 240;
  // Fractions of the radius (gen_defi.py `board()`).
  static const double _bull = 0.054;
  static const double _outerBull = 0.123;
  static const double _tripleIn = 0.44;
  static const double _tripleOut = 0.515;
  static const double _doubleIn = 0.69;
  static const double _doubleOut = 0.77;
  static const double _numbers = 0.885;

  static const _face = Color(0xFF0B1220);
  static const _bedOnDark = Color(0xFF22262B);
  static const _bedOnLight = Color(0xFFE8DCC6);
  static const _ringOnRed = Color(0xFFC8373F);
  static const _ringOnGreen = Color(0xFF2F9E57);
  static const _bedOffDark = Color(0xFF1A2436);
  static const _bedOffLight = Color(0xFF26324A);
  static const _ringOff = Color(0xFF2C3850);
  static const _bullOff = Color(0xFF3A4760);
  static const _numberOn = Color(0xFFF8FAFC);
  static const _numberOff = Color(0xFF475569);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _unit);
    const c = Offset(_unit / 2, _unit / 2);
    const r = _unit / 2;
    final paint = Paint()..isAntiAlias = true;
    canvas.drawCircle(c, r, paint..color = _face);

    Offset at(double f, double a) => c + Offset(math.cos(a) * f * r, math.sin(a) * f * r);

    const order = SpectatorDartboardPainter.numbers;
    for (var i = 0; i < order.length; i++) {
      final n = order[i];
      final a = (-90 + i * 18) * math.pi / 180;
      final a1 = a - 9 * math.pi / 180;
      final a2 = a + 9 * math.pi / 180;
      final even = i.isEven;
      final bedOn = even ? _bedOnDark : _bedOnLight;
      final ringOn = even ? _ringOnRed : _ringOnGreen;
      final bedOff = even ? _bedOffDark : _bedOffLight;
      for (final (r1, r2, ring, on, off) in [
        (_outerBull, _tripleIn, ChallengeRing.single, bedOn, bedOff),
        (_tripleIn, _tripleOut, ChallengeRing.treble, ringOn, _ringOff),
        (_tripleOut, _doubleIn, ChallengeRing.single, bedOn, bedOff),
        (_doubleIn, _doubleOut, ChallengeRing.double, ringOn, _ringOff),
      ]) {
        final path = Path()
          ..moveTo(at(r1, a1).dx, at(r1, a1).dy)
          ..lineTo(at(r2, a1).dx, at(r2, a1).dy)
          ..arcTo(Rect.fromCircle(center: c, radius: r2 * r), a1, a2 - a1, false)
          ..lineTo(at(r1, a2).dx, at(r1, a2).dy)
          ..arcTo(Rect.fromCircle(center: c, radius: r1 * r), a2, a1 - a2, false)
          ..close();
        canvas.drawPath(path, paint..color = spec.lit(n, ring) ? on : off);
      }
      final label = TextPainter(
        text: TextSpan(
          text: '$n',
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            height: 1,
            color: spec.numberLit(n) ? _numberOn : _numberOff,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, at(_numbers, a) - Offset(label.width / 2, label.height / 2));
    }
    canvas.drawCircle(c, _outerBull * r, paint..color = spec.bullLit ? _ringOnGreen : _ringOff);
    canvas.drawCircle(c, _bull * r, paint..color = spec.bullLit ? _ringOnRed : _bullOff);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ChallengeMiniBoardPainter oldDelegate) => oldDelegate.spec != spec;
}

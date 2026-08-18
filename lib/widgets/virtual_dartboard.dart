import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_theme.dart';

/// A rendered dartboard with impact markers for the current visit — the
/// spectator's "camera substitute". Realistic board look (deep black/cream
/// beds, dark red/green rings, dark spider, muted numbers) matching the
/// design mockup; deliberately NOT the bright interactive training board.
/// Markers are placed at the CENTER of the segment each backend notation
/// ('T20', 'S5', 'D25', …) designates: the per-dart protocol only carries
/// the segment, not the exact impact point.
class VirtualDartboard extends StatelessWidget {
  /// Backend notations of the darts currently on the board (0 to 3).
  final List<String> throws;

  /// Board diameter in logical pixels.
  final double size;

  const VirtualDartboard({super.key, required this.throws, required this.size});

  /// Offset from the board center for one notation, or null for a miss.
  /// Mirrors [SpectatorDartboardPainter]'s ring geometry.
  Offset? _offsetFor(String notation) {
    if (notation.length < 2) return null;
    final base = int.tryParse(notation.substring(1));
    if (base == null || base <= 0) return null;
    final radius = size / 2;
    final multiplier = notation[0];
    if (base == 25) {
      if (multiplier == 'D') return Offset.zero;
      const bullRing = (SpectatorDartboardPainter.bullseye +
              SpectatorDartboardPainter.bull) /
          2;
      return Offset(0, -radius * bullRing);
    }
    final index = SpectatorDartboardPainter.numbers.indexOf(base);
    if (index < 0) return null;
    final angle = -math.pi / 2 + index * math.pi / 10;
    final double ring;
    switch (multiplier) {
      case 'T':
        ring = (SpectatorDartboardPainter.tripleIn +
                SpectatorDartboardPainter.tripleOut) /
            2;
        break;
      case 'D':
        ring = (SpectatorDartboardPainter.doubleIn +
                SpectatorDartboardPainter.doubleOut) /
            2;
        break;
      default:
        // The protocol doesn't distinguish inner from outer single — place
        // in the (larger) outer single bed.
        ring = (SpectatorDartboardPainter.tripleOut +
                SpectatorDartboardPainter.doubleIn) /
            2;
    }
    return Offset(
      math.cos(angle) * radius * ring,
      math.sin(angle) * radius * ring,
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Widget>[];
    for (var i = 0; i < throws.length; i++) {
      final offset = _offsetFor(throws[i]);
      if (offset == null) continue;
      final isLatest = i == throws.length - 1;
      markers.add(
        Transform.translate(
          offset: offset,
          child: _ImpactMarker(isLatest: isLatest),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: SpectatorDartboardPainter(),
          ),
          ...markers,
        ],
      ),
    );
  }
}

/// Realistic, muted dartboard for the spectator view. Ring radii are
/// fractions of the board radius, true to a real board's proportions (and to
/// the mockup's SVG): numbers live on the outer black disc, doubles at the
/// playing-area edge, a visible gap between bull and triples.
class SpectatorDartboardPainter extends CustomPainter {
  static const List<int> numbers = [
    20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5
  ];

  static const double bullseye = 0.054;
  static const double bull = 0.123;
  static const double tripleIn = 0.44;
  static const double tripleOut = 0.515;
  static const double doubleIn = 0.69;
  static const double doubleOut = 0.77;
  static const double numbersRadius = 0.885;

  static const Color _boardDark = Color(0xFF14181D);
  static const Color _wire = Color(0xFF0A0C0F);
  static const Color _bedDark = Color(0xFF22262B);
  static const Color _bedCream = Color(0xFFE8DCC6);
  static const Color _red = Color(0xFFC8373F);
  static const Color _green = Color(0xFF2F9E57);
  static const Color _numberColor = Color(0xFFCBD5E1);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Outer disc: the black numbers ring.
    canvas.drawCircle(center, r, Paint()..color = _boardDark);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = _wire
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Beds and score rings. Real-board coloring: red doubles/triples on the
    // dark beds, green ones on the cream beds; segment 20 (index 0) is dark.
    for (var i = 0; i < 20; i++) {
      final isDark = i % 2 == 0;
      final bed = isDark ? _bedDark : _bedCream;
      final score = isDark ? _red : _green;
      final startAngle = -math.pi / 2 + i * math.pi / 10 - math.pi / 20;
      const sweep = math.pi / 10;
      _ringSegment(canvas, center, r * bull, r * tripleIn, startAngle, sweep, bed);
      _ringSegment(
          canvas, center, r * tripleIn, r * tripleOut, startAngle, sweep, score);
      _ringSegment(
          canvas, center, r * tripleOut, r * doubleIn, startAngle, sweep, bed);
      _ringSegment(
          canvas, center, r * doubleIn, r * doubleOut, startAngle, sweep, score);
    }

    // Spider: radial separators + ring wires.
    final radialPaint = Paint()
      ..color = _wire
      ..strokeWidth = 1;
    for (var i = 0; i < 20; i++) {
      final a = -math.pi / 2 + i * math.pi / 10 - math.pi / 20;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
          center + dir * r * bull, center + dir * r * doubleOut, radialPaint);
    }
    final wirePaint = Paint()
      ..color = _wire
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (final ring in const [tripleIn, tripleOut, doubleIn, doubleOut]) {
      canvas.drawCircle(center, r * ring, wirePaint);
    }

    // Bull (green ring) and bullseye (red).
    canvas.drawCircle(center, r * bull, Paint()..color = _green);
    canvas.drawCircle(center, r * bull, wirePaint);
    canvas.drawCircle(center, r * bullseye, Paint()..color = _red);
    canvas.drawCircle(center, r * bullseye, wirePaint);

    // Numbers: small and muted, on the outer disc.
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < 20; i++) {
      final a = -math.pi / 2 + i * math.pi / 10;
      final pos =
          center + Offset(math.cos(a), math.sin(a)) * r * numbersRadius;
      textPainter.text = TextSpan(
        text: '${numbers[i]}',
        style: TextStyle(
          color: _numberColor,
          fontSize: r * 0.085,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        pos - Offset(textPainter.width / 2, textPainter.height / 2),
      );
    }
  }

  void _ringSegment(Canvas canvas, Offset center, double rIn, double rOut,
      double startAngle, double sweepAngle, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..arcTo(Rect.fromCircle(center: center, radius: rIn), startAngle,
          sweepAngle, true)
      ..arcTo(Rect.fromCircle(center: center, radius: rOut),
          startAngle + sweepAngle, -sweepAngle, false)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ImpactMarker extends StatelessWidget {
  final bool isLatest;

  const _ImpactMarker({required this.isLatest});

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: isLatest ? 13 : 11,
      height: isLatest ? 13 : 11,
      decoration: BoxDecoration(
        color: AppTheme.accent,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.gameBackground, width: 2),
      ),
    );
    if (!isLatest) return Opacity(opacity: 0.85, child: dot);
    return Container(
      width: 25,
      height: 25,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: AppTheme.accent.withValues(alpha: 0.5), width: 2),
      ),
      child: dot,
    );
  }
}

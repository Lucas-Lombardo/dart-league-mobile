import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/app_theme.dart';
import 'interactive_dartboard.dart' show DartboardPainter;

/// A rendered dartboard with impact markers for the current visit — the
/// spectator's "camera substitute". The board itself is the existing
/// [DartboardPainter]; markers are placed at the CENTER of the segment each
/// backend notation ('T20', 'S5', 'D25', …) designates: the per-dart protocol
/// only carries the segment, not the exact impact point.
class VirtualDartboard extends StatelessWidget {
  /// Backend notations of the darts currently on the board (0 to 3).
  final List<String> throws;

  /// Board diameter in logical pixels (numbers paint slightly outside it).
  final double size;

  const VirtualDartboard({super.key, required this.throws, required this.size});

  /// Offset from the board center for one notation, or null for a miss.
  /// Mirrors [DartboardPainter]'s geometry: segment i is centered on angle
  /// -π/2 + i·π/10, triple band 0.28–0.48·r, outer single 0.48–0.78·r,
  /// double 0.78–0.95·r, bull ring 0.10–0.22·r.
  Offset? _offsetFor(String notation) {
    if (notation.length < 2) return null;
    final base = int.tryParse(notation.substring(1));
    if (base == null || base <= 0) return null;
    final radius = size / 2;
    final multiplier = notation[0];
    if (base == 25) {
      return multiplier == 'D'
          ? Offset.zero
          : Offset(0, -radius * 0.16);
    }
    final index = DartboardPainter.numbers.indexOf(base);
    if (index < 0) return null;
    final angle = -math.pi / 2 + index * math.pi / 10;
    final double ring;
    switch (multiplier) {
      case 'T':
        ring = 0.38;
        break;
      case 'D':
        ring = 0.865;
        break;
      default:
        ring = 0.63;
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
            painter: DartboardPainter(),
          ),
          ...markers,
        ],
      ),
    );
  }
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
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.5), width: 2),
      ),
      child: dot,
    );
  }
}

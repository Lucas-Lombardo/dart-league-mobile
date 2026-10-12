import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/stats_impacts.dart';
import '../utils/app_theme.dart';
import 'virtual_dartboard.dart';

/// Where the scorer puts each ring boundary (dart_scoring_service, radius
/// normalised on the outer edge of the double) paired with where
/// [SpectatorDartboardPainter] draws that same boundary.
///
/// The drawn board is not to scale: its treble and double rings are widened to
/// stay readable on a phone. Plotting a real radius linearly would land a dart
/// read as a treble twenty in the single bed next to it, so each band of the
/// real board is stretched onto the band that represents it.
const List<(double, double)> _ringMap = [
  (0, 0),
  (0.04059, SpectatorDartboardPainter.bullseye),
  (0.09912, SpectatorDartboardPainter.bull),
  (0.57, SpectatorDartboardPainter.tripleIn),
  (0.62882, SpectatorDartboardPainter.tripleOut),
  (0.94118, SpectatorDartboardPainter.doubleIn),
  (1, SpectatorDartboardPainter.doubleOut),
  // The rim of a real board: 225.5 mm against the 170 mm of the double ring.
  (1.3265, 1),
];

/// A real radius as a fraction of the DRAWN board's radius.
double drawnRadius(double radius) {
  if (radius <= 0) return 0;
  for (var i = 1; i < _ringMap.length; i++) {
    final (realFrom, drawnFrom) = _ringMap[i - 1];
    final (realTo, drawnTo) = _ringMap[i];
    if (radius <= realTo) {
      final t = (radius - realFrom) / (realTo - realFrom);
      return drawnFrom + (drawnTo - drawnFrom) * t;
    }
  }
  // Past the rim: a dart in the surround still shows, pinned to the edge.
  return 1;
}

/// A dart's position relative to the board centre. The stored angle is the
/// scorer's own — atan2(dy, dx) with y pointing down — which is also how a
/// canvas measures, so it needs no conversion.
Offset impactOffset(DartImpact impact, double boardRadius) {
  final r = drawnRadius(impact.radius) * boardRadius;
  return Offset(math.cos(impact.angle) * r, math.sin(impact.angle) * r);
}

/// A dartboard with a player's real darts landing on it one after the other,
/// in the order they were thrown. Tapping it replays the sequence.
class ImpactBoard extends StatefulWidget {
  /// Oldest first. [DartImpact.good] darts are drawn in the accent colour.
  final List<DartImpact> impacts;

  /// Board diameter in logical pixels.
  final double size;

  /// What the board shows, for screen readers ("Scoring, 17 trebles out of 96").
  final String semanticsLabel;

  /// Read out as the tap action.
  final String replayHint;

  const ImpactBoard({
    super.key,
    required this.impacts,
    required this.size,
    required this.semanticsLabel,
    required this.replayHint,
  });

  @override
  State<ImpactBoard> createState() => _ImpactBoardState();
}

class _ImpactBoardState extends State<ImpactBoard>
    with SingleTickerProviderStateMixin {
  /// A beat before the first dart, so the board is seen empty first.
  static const double _leadMs = 250;

  /// How long one dart takes to land.
  static const double _landMs = 360;

  /// The whole grouping lands inside this window however many darts it holds:
  /// ten darts are spaced out, a hundred follow each other closely.
  static const double _spreadMs = 2400;

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _duration)..forward();

  double get _stepMs {
    final count = widget.impacts.length;
    if (count <= 1) return 0;
    return (_spreadMs / count).clamp(12.0, 60.0);
  }

  double get _totalMs =>
      _leadMs + _stepMs * math.max(0, widget.impacts.length - 1) + _landMs;

  Duration get _duration => Duration(milliseconds: _totalMs.round());

  @override
  void didUpdateWidget(ImpactBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new window (the filter changed, a pull to refresh) is a new sequence.
    if (!identical(oldWidget.impacts, widget.impacts)) _replay();
  }

  void _replay() {
    _controller
      ..duration = _duration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final size = Size.square(widget.size);

    return Semantics(
      label: widget.semanticsLabel,
      button: true,
      onTapHint: widget.replayHint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _replay,
        child: RepaintBoundary(
          child: CustomPaint(
            size: size,
            painter: SpectatorDartboardPainter(
              // Under ~240 px the numbers are too small to read.
              showNumbers: widget.size >= 240,
            ),
            foregroundPainter: _ImpactsPainter(
              impacts: widget.impacts,
              progress: still ? const AlwaysStoppedAnimation(1) : _controller,
              totalMs: _totalMs,
              leadMs: _leadMs,
              stepMs: _stepMs,
              landMs: _landMs,
            ),
          ),
        ),
      ),
    );
  }
}

class _ImpactsPainter extends CustomPainter {
  final List<DartImpact> impacts;
  final Animation<double> progress;
  final double totalMs;
  final double leadMs;
  final double stepMs;
  final double landMs;

  _ImpactsPainter({
    required this.impacts,
    required this.progress,
    required this.totalMs,
    required this.leadMs,
    required this.stepMs,
    required this.landMs,
  }) : super(repaint: progress);

  /// Comes in large and settles with a slight overshoot — a dart arriving
  /// from the viewer's side of the board.
  static const Curve _land = Cubic(0.2, 0.8, 0.3, 1.25);

  @override
  void paint(Canvas canvas, Size size) {
    final boardRadius = size.width / 2;
    final center = Offset(boardRadius, boardRadius);
    final dot = math.max(3.0, size.width * 0.02);
    final elapsed = progress.value * totalMs;

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final fill = Paint();

    // Two passes, the accent darts last: in a tight grouping the trebles are
    // the point of the picture and would otherwise sit under whatever was
    // thrown after them. Each dart still LANDS at its own turn — only the
    // stacking changes.
    for (final accent in const [false, true]) {
      for (var i = 0; i < impacts.length; i++) {
        final impact = impacts[i];
        if (impact.good != accent) continue;
        final t = ((elapsed - leadMs - i * stepMs) / landMs).clamp(0.0, 1.0);
        if (t <= 0) continue;

        final at = center + impactOffset(impact, boardRadius);
        final scale = 3.2 + (1 - 3.2) * _land.transform(t);
        final color = accent ? AppTheme.primaryLight : AppTheme.textPrimary;

        fill.color = color.withValues(alpha: t);
        rim.color = AppTheme.background.withValues(alpha: t);
        canvas.drawCircle(at, dot * scale, fill);
        canvas.drawCircle(at, dot * scale, rim);
      }
    }
  }

  @override
  bool shouldRepaint(_ImpactsPainter old) =>
      !identical(old.impacts, impacts) ||
      old.progress != progress ||
      old.totalMs != totalMs;
}

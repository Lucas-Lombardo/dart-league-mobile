import 'package:flutter/material.dart';

import '../services/dart_detection_types.dart';
import '../utils/app_theme.dart';

// Spread values displayed by the gauges: below _lo the board is a distant
// speck, above _hi it overflows the frame. The green band inside is the
// reliable zone [kZoomSpreadMin, kZoomSpreadMax].
const double _lo = 0.15;
const double _hi = 1.0;

double _pos(double spread) => ((spread - _lo) / (_hi - _lo)).clamp(0.0, 1.0);

/// Vertical framing gauge for the camera-setup screen: green band = reliable
/// zone, cursor = live measured spread (hidden while the board isn't seen).
/// Bottom of the track = board too far, top = too close.
class SpreadGauge extends StatelessWidget {
  final double? spread;
  final double height;

  const SpreadGauge({super.key, required this.spread, this.height = 180});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: height,
      child: CustomPaint(painter: _SpreadGaugePainter(spread)),
    );
  }
}

class _SpreadGaugePainter extends CustomPainter {
  final double? spread;

  _SpreadGaugePainter(this.spread);

  @override
  void paint(Canvas canvas, Size size) {
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width / 2 - 5, 0, 10, size.height),
      const Radius.circular(5),
    );
    canvas.drawRRect(
      trackRect,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      trackRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.25),
    );

    // Reliable zone (y grows downward, spread grows upward).
    final zoneTop = size.height * (1 - _pos(kZoomSpreadMax));
    final zoneBottom = size.height * (1 - _pos(kZoomSpreadMin));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
            size.width / 2 - 5, zoneTop, size.width / 2 + 5, zoneBottom),
        const Radius.circular(4),
      ),
      Paint()..color = AppTheme.success.withValues(alpha: 0.45),
    );

    final s = spread;
    if (s == null) return;
    final y = size.height * (1 - _pos(s));
    final inZone = s >= kZoomSpreadMin && s <= kZoomSpreadMax;
    final color = inZone
        ? AppTheme.success
        : (s < kZoomSpreadMin ? AppTheme.error : AppTheme.accent);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(size.width / 2, y), width: size.width, height: 7),
        const Radius.circular(4),
      ),
      Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2),
    );
  }

  @override
  bool shouldRepaint(_SpreadGaugePainter old) => old.spread != spread;
}

/// Compact horizontal variant for the in-match AUTO chip.
class MiniSpreadGauge extends StatelessWidget {
  final double? spread;

  const MiniSpreadGauge({super.key, required this.spread});

  @override
  Widget build(BuildContext context) {
    final s = spread;
    return SizedBox(
      width: 40,
      height: 12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(colors: [
                AppTheme.error.withValues(alpha: 0.8),
                AppTheme.success.withValues(alpha: 0.8),
                AppTheme.accent.withValues(alpha: 0.8),
              ], stops: [
                _pos(kZoomSpreadMin) / 2,
                (_pos(kZoomSpreadMin) + _pos(kZoomSpreadMax)) / 2,
                (1 + _pos(kZoomSpreadMax)) / 2,
              ]),
            ),
          ),
          if (s != null)
            Align(
              alignment: Alignment(_pos(s) * 2 - 1, 0),
              child: Container(
                width: 4,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

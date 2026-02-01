import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../utils/app_theme.dart';
import '../utils/haptic_service.dart';
import '../providers/game_provider.dart';

class InteractiveDartboard extends StatefulWidget {
  final Function(int score, ScoreMultiplier multiplier) onDartThrow;
  
  const InteractiveDartboard({
    super.key,
    required this.onDartThrow,
  });

  @override
  State<InteractiveDartboard> createState() => _InteractiveDartboardState();
}

class _InteractiveDartboardState extends State<InteractiveDartboard> {
  // Dartboard number sequence (clockwise from top)
  static const List<int> numbers = [
    20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        
        return Center(
          child: SizedBox(
            width: size,
            height: size,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => _handleTap(details, size),
              child: CustomPaint(
                size: Size(size, size),
                painter: DartboardPainter(),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleTap(TapUpDetails details, double size) {
    final center = size / 2;
    final dx = details.localPosition.dx - center;
    final dy = details.localPosition.dy - center;
    final distance = math.sqrt(dx * dx + dy * dy);
    final radius = center;
    
    // Distance ratios for dartboard rings (with gap between bull and triples)
    final bullseyeRadius = radius * 0.10;       // Double bull (red center) - bigger
    final bullRadius = radius * 0.22;           // Single bull (green ring)
    // Gap between bull and triple (miss area)
    final tripleStart = radius * 0.28;          // Triple ring starts (smaller gap)
    final tripleEnd = radius * 0.48;            // Triple ring ends (much bigger)
    // Outer single: between triple and double
    final doubleStart = radius * 0.78;          // Double ring starts
    final doubleEnd = radius * 0.95;            // Double ring ends
    
    // Check bulls
    if (distance <= bullseyeRadius) {
      HapticService.mediumImpact();
      widget.onDartThrow(25, ScoreMultiplier.double); // Double bull = 50
      return;
    }
    
    if (distance <= bullRadius) {
      HapticService.mediumImpact();
      widget.onDartThrow(25, ScoreMultiplier.single); // Single bull = 25
      return;
    }
    
    // Outside dartboard
    if (distance > doubleEnd) {
      HapticService.mediumImpact();
      widget.onDartThrow(0, ScoreMultiplier.single); // Miss
      return;
    }
    
    // Calculate angle (0 at top, clockwise)
    var angle = math.atan2(dx, -dy);
    if (angle < 0) angle += 2 * math.pi;
    
    // Each segment is π/10 radians (18 degrees)
    // Add π/20 to align with segment boundaries
    final adjustedAngle = angle + math.pi / 20;
    final segmentIndex = ((adjustedAngle / (math.pi / 10)) % 20).floor();
    final number = numbers[segmentIndex];
    
    // Determine multiplier based on distance
    ScoreMultiplier multiplier;
    if (distance >= tripleStart && distance <= tripleEnd) {
      multiplier = ScoreMultiplier.triple;
    } else if (distance >= doubleStart && distance <= doubleEnd) {
      multiplier = ScoreMultiplier.double;
    } else {
      multiplier = ScoreMultiplier.single;
    }
    
    HapticService.mediumImpact();
    widget.onDartThrow(number, multiplier);
  }
}

class DartboardPainter extends CustomPainter {
  static const List<int> numbers = [
    20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Distance ratios (matching hitbox detection - with gap between bull and triples)
    final bullseyeRadius = radius * 0.10;       // Double bull (red center) - bigger
    final bullRadius = radius * 0.22;           // Single bull (green ring)
    // Gap between bull and triple: 0.22 to 0.28 (miss area - uses background)
    final tripleStart = radius * 0.28;          // Triple ring starts (smaller gap)
    final tripleEnd = radius * 0.48;            // Triple ring ends (much bigger)
    final outerSingleStart = radius * 0.48;     // Outer single starts
    final outerSingleEnd = radius * 0.78;       // Outer single ends
    final doubleStart = radius * 0.78;          // Double ring starts
    final doubleEnd = radius * 0.95;            // Double ring ends
    
    // Colors
    const black = Color(0xFF000000);
    const cream = Color(0xFFF4E4C1);
    final red = AppTheme.error;
    final green = AppTheme.success;
    
    // Draw outer circle with app surface color (board edge)
    final edgePaint = Paint()..color = AppTheme.surface;
    canvas.drawCircle(center, doubleEnd + 2, edgePaint);
    
    // Draw 20 segments
    for (int i = 0; i < 20; i++) {
      final isBlack = i % 2 == 0;
      final singleColor = isBlack ? black : cream;
      final scoreColor = isBlack ? red : green;
      
      // Start angle for this segment (0 at top, clockwise)
      // Offset by -π/20 so segment edges align properly
      final startAngle = -math.pi / 2 + (i * math.pi / 10) - (math.pi / 20);
      final sweepAngle = math.pi / 10;
      
      // Draw double ring (outermost)
      _drawSegment(canvas, center, doubleStart, doubleEnd, 
                   startAngle, sweepAngle, scoreColor);
      
      // Draw outer single (between double and triple)
      _drawSegment(canvas, center, outerSingleStart, outerSingleEnd, 
                   startAngle, sweepAngle, singleColor);
      
      // Draw triple ring (connects directly to bull)
      _drawSegment(canvas, center, tripleStart, tripleEnd, 
                   startAngle, sweepAngle, scoreColor);
    }
    
    // Draw single bull (outer bull - green)
    final bullPaint = Paint()..color = green;
    canvas.drawCircle(center, bullRadius, bullPaint);
    
    // Draw double bull (bullseye - red)
    final bullseyePaint = Paint()..color = red;
    canvas.drawCircle(center, bullseyeRadius, bullseyePaint);
    
    // Draw numbers
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    
    for (int i = 0; i < 20; i++) {
      // Position at center of segment
      final angle = -math.pi / 2 + (i * math.pi / 10);
      final numberRadius = doubleEnd + 15;
      final x = center.dx + numberRadius * math.cos(angle);
      final y = center.dy + numberRadius * math.sin(angle);
      
      textPainter.text = TextSpan(
        text: '${numbers[i]}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, y - textPainter.height / 2),
      );
    }
  }

  void _drawSegment(Canvas canvas, Offset center, double innerRadius, 
                   double outerRadius, double startAngle, double sweepAngle, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final path = Path();
    
    // Move to start point on inner radius
    path.moveTo(
      center.dx + innerRadius * math.cos(startAngle),
      center.dy + innerRadius * math.sin(startAngle),
    );
    
    // Line to start point on outer radius
    path.lineTo(
      center.dx + outerRadius * math.cos(startAngle),
      center.dy + outerRadius * math.sin(startAngle),
    );
    
    // Arc along outer radius
    path.arcTo(
      Rect.fromCircle(center: center, radius: outerRadius),
      startAngle,
      sweepAngle,
      false,
    );
    
    // Line back to inner radius
    path.lineTo(
      center.dx + innerRadius * math.cos(startAngle + sweepAngle),
      center.dy + innerRadius * math.sin(startAngle + sweepAngle),
    );
    
    // Arc along inner radius (backwards)
    path.arcTo(
      Rect.fromCircle(center: center, radius: innerRadius),
      startAngle + sweepAngle,
      -sweepAngle,
      false,
    );
    
    path.close();
    canvas.drawPath(path, paint);
    
    // Draw thin black border between segments
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(DartboardPainter oldDelegate) => false;
}

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
  int? _hoveredSegment;
  ScoreMultiplier? _hoveredMultiplier;

  static const List<int> dartboardNumbers = [
    20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        final center = Offset(size / 2, size / 2);
        
        return GestureDetector(
          onTapUp: (details) => _handleTap(details.localPosition, center, size),
          child: CustomPaint(
            size: Size(size, size),
            painter: DartboardPainter(
              hoveredSegment: _hoveredSegment,
              hoveredMultiplier: _hoveredMultiplier,
            ),
            child: MouseRegion(
              onHover: (event) => _handleHover(event.localPosition, center, size),
              onExit: (_) => setState(() {
                _hoveredSegment = null;
                _hoveredMultiplier = null;
              }),
              child: Container(),
            ),
          ),
        );
      },
    );
  }

  void _handleHover(Offset position, Offset center, double size) {
    final result = _getSegmentFromPosition(position, center, size);
    if (result != null) {
      setState(() {
        _hoveredSegment = result['segment'];
        _hoveredMultiplier = result['multiplier'];
      });
    }
  }

  void _handleTap(Offset position, Offset center, double size) {
    final result = _getSegmentFromPosition(position, center, size);
    if (result != null) {
      HapticService.mediumImpact();
      widget.onDartThrow(result['segment'], result['multiplier']);
    }
  }

  Map<String, dynamic>? _getSegmentFromPosition(Offset position, Offset center, double size) {
    final dx = position.dx - center.dx;
    final dy = position.dy - center.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    final radius = size / 2;
    
    // Define ring boundaries (as percentage of radius)
    final bullRadius = radius * 0.08;
    final innerBullRadius = radius * 0.15;
    final innerTripleRadius = radius * 0.52;
    final outerTripleRadius = radius * 0.60;
    final innerDoubleRadius = radius * 0.88;
    final outerDoubleRadius = radius * 0.98;
    
    // Check if in bullseye
    if (distance < bullRadius) {
      return {'segment': 50, 'multiplier': ScoreMultiplier.double}; // Double bull
    }
    if (distance < innerBullRadius) {
      return {'segment': 25, 'multiplier': ScoreMultiplier.single}; // Single bull
    }
    
    // Check if outside the board
    if (distance > outerDoubleRadius) {
      return {'segment': 0, 'multiplier': ScoreMultiplier.single}; // Miss
    }
    
    // Calculate angle
    var angle = math.atan2(dy, dx);
    angle = (angle + math.pi / 2) % (2 * math.pi); // Rotate so 20 is at top
    if (angle < 0) angle += 2 * math.pi;
    
    // Each segment is 18 degrees (360/20), offset by 9 degrees
    final segmentAngle = (angle + (math.pi / 20)) / (math.pi / 10);
    final segmentIndex = segmentAngle.floor() % 20;
    final segmentNumber = dartboardNumbers[segmentIndex];
    
    // Determine multiplier based on distance
    ScoreMultiplier multiplier;
    if (distance >= innerDoubleRadius && distance <= outerDoubleRadius) {
      multiplier = ScoreMultiplier.double;
    } else if (distance >= innerTripleRadius && distance <= outerTripleRadius) {
      multiplier = ScoreMultiplier.triple;
    } else {
      multiplier = ScoreMultiplier.single;
    }
    
    return {'segment': segmentNumber, 'multiplier': multiplier};
  }
}

class DartboardPainter extends CustomPainter {
  final int? hoveredSegment;
  final ScoreMultiplier? hoveredMultiplier;
  
  DartboardPainter({
    this.hoveredSegment,
    this.hoveredMultiplier,
  });

  static const List<int> dartboardNumbers = [
    20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // Define ring boundaries
    final bullRadius = radius * 0.08;
    final innerBullRadius = radius * 0.15;
    final innerTripleRadius = radius * 0.52;
    final outerTripleRadius = radius * 0.60;
    final innerDoubleRadius = radius * 0.88;
    final outerDoubleRadius = radius * 0.98;
    
    // Background
    final bgPaint = Paint()
      ..color = AppTheme.background
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, outerDoubleRadius, bgPaint);
    
    // Draw segments
    for (int i = 0; i < 20; i++) {
      final startAngle = (i * math.pi / 10) - (math.pi / 20);
      final sweepAngle = math.pi / 10;
      final number = dartboardNumbers[i];
      final isBlackSegment = i % 2 == 0;
      
      // Outer single (between triple and double)
      _drawSegment(
        canvas,
        center,
        outerTripleRadius,
        innerDoubleRadius,
        startAngle,
        sweepAngle,
        isBlackSegment ? const Color(0xFF1A1A1A) : const Color(0xFFE8E8E8),
        number,
        ScoreMultiplier.single,
      );
      
      // Inner single (between bull and triple)
      _drawSegment(
        canvas,
        center,
        innerBullRadius,
        innerTripleRadius,
        startAngle,
        sweepAngle,
        isBlackSegment ? const Color(0xFF1A1A1A) : const Color(0xFFE8E8E8),
        number,
        ScoreMultiplier.single,
      );
      
      // Triple ring
      _drawSegment(
        canvas,
        center,
        innerTripleRadius,
        outerTripleRadius,
        startAngle,
        sweepAngle,
        isBlackSegment ? const Color(0xFF1A1A1A) : const Color(0xFFFF3333),
        number,
        ScoreMultiplier.triple,
      );
      
      // Double ring
      _drawSegment(
        canvas,
        center,
        innerDoubleRadius,
        outerDoubleRadius,
        startAngle,
        sweepAngle,
        isBlackSegment ? const Color(0xFF1A1A1A) : const Color(0xFF00AA00),
        number,
        ScoreMultiplier.double,
      );
    }
    
    // Bullseye
    final bullPaint = Paint()
      ..color = (hoveredSegment == 25 && hoveredMultiplier == ScoreMultiplier.single)
          ? const Color(0xFF00AA00).withValues(alpha: 0.7)
          : const Color(0xFF00AA00)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerBullRadius, bullPaint);
    
    final doubleBullPaint = Paint()
      ..color = (hoveredSegment == 50 && hoveredMultiplier == ScoreMultiplier.double)
          ? const Color(0xFFFF3333).withValues(alpha: 0.7)
          : const Color(0xFFFF3333)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, bullRadius, doubleBullPaint);
    
    // Draw numbers around the board
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    
    for (int i = 0; i < 20; i++) {
      final angle = (i * math.pi / 10);
      final numberRadius = outerDoubleRadius + 20;
      final x = center.dx + numberRadius * math.cos(angle - math.pi / 2);
      final y = center.dy + numberRadius * math.sin(angle - math.pi / 2);
      
      textPainter.text = TextSpan(
        text: '${dartboardNumbers[i]}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
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

  void _drawSegment(
    Canvas canvas,
    Offset center,
    double innerRadius,
    double outerRadius,
    double startAngle,
    double sweepAngle,
    Color color,
    int number,
    ScoreMultiplier multiplier,
  ) {
    final paint = Paint()
      ..color = (hoveredSegment == number && hoveredMultiplier == multiplier)
          ? color.withValues(alpha: 0.7)
          : color
      ..style = PaintingStyle.fill;
    
    final path = Path();
    path.moveTo(
      center.dx + innerRadius * math.cos(startAngle),
      center.dy + innerRadius * math.sin(startAngle),
    );
    path.arcTo(
      Rect.fromCircle(center: center, radius: innerRadius),
      startAngle,
      sweepAngle,
      false,
    );
    path.lineTo(
      center.dx + outerRadius * math.cos(startAngle + sweepAngle),
      center.dy + outerRadius * math.sin(startAngle + sweepAngle),
    );
    path.arcTo(
      Rect.fromCircle(center: center, radius: outerRadius),
      startAngle + sweepAngle,
      -sweepAngle,
      false,
    );
    path.close();
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(DartboardPainter oldDelegate) {
    return oldDelegate.hoveredSegment != hoveredSegment ||
           oldDelegate.hoveredMultiplier != hoveredMultiplier;
  }
}

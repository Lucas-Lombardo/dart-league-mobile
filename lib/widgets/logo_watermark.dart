import 'package:flutter/material.dart';

/// Small Dart Rivals shield overlaid on the in-game camera/video panels, like
/// a broadcaster's corner bug — so every screenshot or clip a player shares
/// carries the brand. 30 px at 85 % opacity, nothing else: the system draws
/// no glows, and the shield reads fine on the dark feed at this size.
class LogoWatermark extends StatelessWidget {
  const LogoWatermark({super.key, this.height = 30});

  final double height;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.85,
        child: Image.asset(
          'assets/logo/logo-without-letters.png',
          height: height,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

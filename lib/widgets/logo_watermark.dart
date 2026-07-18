import 'dart:ui';

import 'package:flutter/material.dart';

/// Small semi-transparent Dart Rivals mark overlaid on the in-game
/// camera/video panels, like a broadcaster's corner bug — so every
/// screenshot or clip a player shares carries the brand.
///
/// The blurred white copy underneath acts as a glow that detaches the
/// logo's black outline from the dark video feed; without it the mark
/// is unreadable at this size on the dark theme.
class LogoWatermark extends StatelessWidget {
  const LogoWatermark({super.key, this.height = 38});

  final double height;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Opacity(
        opacity: 0.8,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Image.asset(
                'assets/logo/logo-without-letters.png',
                height: height,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            Image.asset(
              'assets/logo/logo-without-letters.png',
              height: height,
            ),
          ],
        ),
      ),
    );
  }
}

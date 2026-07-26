import 'package:flutter/material.dart';

/// Render of the physical trophy a tournament awards, served by the backend
/// (`/trophies/<model>.png`, transparent background). Fades in on first load
/// and falls back to [fallback] when the image can't be fetched, so an
/// offline app never shows a broken image.
class TrophyImage extends StatelessWidget {
  final String url;
  final double size;
  final Widget fallback;

  const TrophyImage({
    super.key,
    required this.url,
    required this.size,
    this.fallback = const SizedBox.shrink(),
  });

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
      frameBuilder: (context, child, frame, wasSyncLoaded) {
        if (wasSyncLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          child: child,
        );
      },
    );
  }
}

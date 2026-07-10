import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../l10n/app_localizations.dart';

/// Shared building blocks for the in-match maquette UI (July 2026 redesign).
/// Both turn layouts — AutoScoreGameView (your turn) and the opponent-turn
/// screen — compose these widgets so the two states stay visually consistent.

/// Height of the camera panel in portrait, IDENTICAL on your turn and the
/// opponent's turn so the video feed never resizes when the turn flips.
/// Derived from the screen height minus the vertical chrome each layout needs
/// below/above the camera, clamped so it neither collapses on small phones
/// nor starves the scoring panels on tall ones.
double gameCameraHeight(BuildContext context) {
  final mq = MediaQuery.of(context);
  final h = mq.size.height;
  final reserved = 340.0 + mq.padding.top + mq.padding.bottom;
  return (h - reserved).clamp(h * 0.32, h * 0.54);
}

/// Points value of a backend dart notation ('S20' → 20, 'T20' → 60, 'D25' →
/// 50, 'MISS' → 0). Mirrors GameProvider.currentRoundScore parsing.
int notationPoints(String notation) {
  if (notation.length < 2) return 0;
  final base = int.tryParse(notation.substring(1)) ?? 0;
  switch (notation[0]) {
    case 'S':
      return base;
    case 'D':
      return base * 2;
    case 'T':
      return base * 3;
    default:
      return 0;
  }
}

/// Small outlined pill chip ("VOUS", "TOUR 26").
class GameChip extends StatelessWidget {
  final String text;
  final Color color;

  const GameChip({super.key, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.8), width: 1.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// "EN DIRECT" pill shown on the opponent's live camera feed.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.opponentPink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          AppLocalizations.of(context).liveBadge,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ]),
    );
  }
}

/// Rounded-square outlined camera control (mic mute, camera flip).
class GameControlButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const GameControlButton({
    super.key,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.gameBackground.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.9), width: 1.4),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}

/// "− 1,9× +" zoom pill anchored to the bottom of the local camera feed.
class ZoomPill extends StatelessWidget {
  final double zoom;
  final double minZoom;
  final double maxZoom;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  const ZoomPill({
    super.key,
    required this.zoom,
    required this.minZoom,
    required this.maxZoom,
    this.onZoomIn,
    this.onZoomOut,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback? onTap) => GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Icon(icon, size: 18, color: onTap != null ? Colors.white : Colors.white30),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.gameBackground.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(Icons.remove, zoom > minZoom ? onZoomOut : null),
        Text(
          '${zoom.toStringAsFixed(1)}×',
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
        ),
        btn(Icons.add, zoom < maxZoom ? onZoomIn : null),
      ]),
    );
  }
}

/// Center block of the turn header that alternates between "VOTRE MOY." and
/// "MOY. ADV." every couple of seconds, tinting the value with the owner's
/// color. Shows just the available one when the other is still null.
class AlternatingAverage extends StatefulWidget {
  final double? myAverage;
  final double? opponentAverage;

  const AlternatingAverage({super.key, this.myAverage, this.opponentAverage});

  @override
  State<AlternatingAverage> createState() => _AlternatingAverageState();
}

class _AlternatingAverageState extends State<AlternatingAverage> {
  Timer? _timer;
  bool _showMine = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      if (widget.myAverage != null && widget.opponentAverage != null) {
        setState(() => _showMine = !_showMine);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Fall back to whichever side has data while the other is still null.
    final bool mine = widget.myAverage != null &&
        (_showMine || widget.opponentAverage == null);
    final double? value = mine ? widget.myAverage : widget.opponentAverage;
    if (value == null) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: Column(
        // Keying on the side makes AnimatedSwitcher cross-fade on each flip.
        key: ValueKey(mine),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            mine ? l10n.yourAvgLabel : l10n.opponentAvgLabel,
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.7),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          Text(
            value.toStringAsFixed(1),
            style: TextStyle(
              color: mine ? AppTheme.playerBlueBright : AppTheme.opponentPinkBright,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// Opponent-turn header: my identity (blue, left) vs opponent (pink, right)
/// with the round chip + alternating averages in the middle.
class TurnScoreHeader extends StatelessWidget {
  final String myName;
  final String opponentName;
  final int myScore;
  final int opponentScore;
  final int? roundNumber;
  final double? myAverage;
  final double? opponentAverage;
  final Widget? leading;

  const TurnScoreHeader({
    super.key,
    required this.myName,
    required this.opponentName,
    required this.myScore,
    required this.opponentScore,
    this.roundNumber,
    this.myAverage,
    this.opponentAverage,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const scoreStyle = TextStyle(
      fontSize: 40,
      fontWeight: FontWeight.w800,
      height: 1.05,
      letterSpacing: -1,
    );
    // Every column stacks: badge row (fixed height so the back button can't
    // push the left column down) → name → score. Fixed heights keep the two
    // names and the two scores on exactly the same lines.
    const badgeRowHeight = 40.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: badgeRowHeight,
                  child: Row(children: [
                    if (leading != null) ...[leading!, const SizedBox(width: 8)],
                    GameChip(text: l10n.you, color: AppTheme.playerBlue),
                  ]),
                ),
                const SizedBox(height: 4),
                Text(
                  myName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.playerBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                Text('$myScore', style: scoreStyle.copyWith(color: AppTheme.playerBlueBright)),
              ],
            ),
          ),
          Column(children: [
            SizedBox(
              height: badgeRowHeight,
              child: Center(
                child: roundNumber != null
                    ? GameChip(text: l10n.roundChip(roundNumber!), color: AppTheme.textSecondary)
                    : const SizedBox.shrink(),
              ),
            ),
            if (myAverage != null || opponentAverage != null) ...[
              const SizedBox(height: 4),
              AlternatingAverage(
                myAverage: myAverage,
                opponentAverage: opponentAverage,
              ),
            ],
          ]),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  height: badgeRowHeight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppTheme.opponentPink,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        AppLocalizations.of(context).playingBadge,
                        style: const TextStyle(
                          color: AppTheme.opponentPinkBright,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  opponentName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.opponentPinkBright,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                Text('$opponentScore', style: scoreStyle.copyWith(color: AppTheme.opponentPinkBright)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One dart of the current visit. Filled chips show the notation + points
/// (and an optional EDIT footer on the player's own chips); empty chips are
/// dashed with "à venir".
class DartVisitChip extends StatelessWidget {
  final String? notation;
  final Color accent;
  final bool highlighted;
  final bool showEditLabel;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final bool capturing;

  const DartVisitChip({
    super.key,
    this.notation,
    required this.accent,
    this.highlighted = false,
    this.showEditLabel = false,
    this.onTap,
    this.onRemove,
    this.capturing = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filled = notation != null && notation!.isNotEmpty;

    Widget chip;
    if (filled) {
      chip = Container(
        decoration: BoxDecoration(
          color: AppTheme.gamePanel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: highlighted ? AppTheme.opponentPink : accent.withValues(alpha: 0.75),
            width: highlighted ? 1.8 : 1.4,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              notation!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
            Text(
              l10n.ptsLabel(notationPoints(notation!)),
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (showEditLabel) ...[
              const SizedBox(height: 5),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                padding: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: accent.withValues(alpha: 0.3)),
                  ),
                ),
                child: Text(
                  l10n.editShort,
                  style: TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    } else {
      chip = CustomPaint(
        painter: _DashedRRectPainter(
          color: AppTheme.surfaceLight.withValues(alpha: 0.8),
          radius: 14,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.gamePanelEmpty,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              capturing
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.textSecondary.withValues(alpha: 0.4),
                      ),
                    )
                  : Container(
                      width: 22,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppTheme.textSecondary.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
              const SizedBox(height: 8),
              Text(
                l10n.upcomingDart,
                style: TextStyle(
                  color: AppTheme.textSecondary.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          chip,
          if (onRemove != null && filled)
            Positioned(
              top: -8,
              right: -8,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: AppTheme.opponentPink,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 15, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double radius;

  _DashedRRectPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect.deflate(0.75));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dash = 6.0, gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

/// "TOTAL 80" readout paired with the visit chips.
class VisitTotal extends StatelessWidget {
  final int total;
  final Color color;

  const VisitTotal({super.key, required this.total, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          AppLocalizations.of(context).totalLabel,
          style: TextStyle(
            color: AppTheme.textSecondary.withValues(alpha: 0.8),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$total',
          style: TextStyle(
            color: color,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ],
    );
  }
}

/// Big glowing "T20 / +60 pts / FLÉCHETTE 2 / 3" flash overlaid on the
/// opponent's camera whenever a new dart of theirs lands. Fades in, holds,
/// fades out on its own.
class DartHitFlash extends StatefulWidget {
  final List<String> throws;

  const DartHitFlash({super.key, required this.throws});

  @override
  State<DartHitFlash> createState() => _DartHitFlashState();
}

class _DartHitFlashState extends State<DartHitFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _holdTimer;
  String? _notation;
  int _dartIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 450),
    );
  }

  @override
  void didUpdateWidget(DartHitFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.throws.length > oldWidget.throws.length &&
        widget.throws.isNotEmpty) {
      _notation = widget.throws.last;
      _dartIndex = widget.throws.length;
      _holdTimer?.cancel();
      _controller.forward(from: 0);
      _holdTimer = Timer(const Duration(milliseconds: 2200), () {
        if (mounted) _controller.reverse();
      });
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IgnorePointer(
      child: FadeTransition(
        opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
        child: _notation == null
            ? const SizedBox.shrink()
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _notation!,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 84,
                        fontWeight: FontWeight.w900,
                        height: 1,
                        shadows: [
                          Shadow(
                            color: AppTheme.opponentPink.withValues(alpha: 0.9),
                            blurRadius: 36,
                          ),
                          Shadow(
                            color: AppTheme.opponentPink.withValues(alpha: 0.6),
                            blurRadius: 70,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.plusPts(notationPoints(_notation!)),
                      style: const TextStyle(
                        color: AppTheme.opponentPinkBright,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.dartOf(_dartIndex),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// "NE LANCEZ PAS VOS FLÉCHETTES" bottom banner for the opponent's turn.
/// Pulses ("breathes") like in the maquette video: icon, title and border
/// glow from dim to full pink and back on a ~2.2s cycle; the background
/// stays constant.
class OpponentWarningBanner extends StatefulWidget {
  const OpponentWarningBanner({super.key});

  @override
  State<OpponentWarningBanner> createState() => _OpponentWarningBannerState();
}

class _OpponentWarningBannerState extends State<OpponentWarningBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _pulse.value;
        final titleColor = AppTheme.opponentPinkBright
            .withValues(alpha: 0.45 + 0.55 * t);
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.warnBannerBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppTheme.opponentPink.withValues(alpha: 0.25 + 0.5 * t),
              width: 1.4,
            ),
          ),
          child: Row(children: [
            Icon(
              Icons.warning_amber_rounded,
              color: AppTheme.opponentPink.withValues(alpha: 0.45 + 0.55 * t),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.doNotThrowTitle,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    l10n.opponentTurnWait,
                    style: TextStyle(
                      color: AppTheme.opponentPinkBright
                          .withValues(alpha: 0.35 + 0.3 * t),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// Your-turn bottom score bar: "VOUS (name) 490  VS  (opponent) 501".
class UserScoreBar extends StatelessWidget {
  final String myName;
  final String opponentName;
  final int myScore;
  final int opponentScore;

  const UserScoreBar({
    super.key,
    required this.myName,
    required this.opponentName,
    required this.myScore,
    required this.opponentScore,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The remaining score is the one thing the player reads from throwing
    // distance (~2m) — keep it big.
    const scoreStyle = TextStyle(
      fontSize: 46,
      fontWeight: FontWeight.w800,
      height: 1.05,
      letterSpacing: -1,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.gamePanelEmpty,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                GameChip(text: l10n.you, color: AppTheme.playerBlue),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    myName.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppTheme.playerBlue,
                    shape: BoxShape.circle,
                  ),
                ),
              ]),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('$myScore', style: scoreStyle.copyWith(color: AppTheme.playerBlueBright)),
              ),
            ],
          ),
        ),
        Text(
          l10n.vsLabel,
          style: TextStyle(
            color: AppTheme.textSecondary.withValues(alpha: 0.6),
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                opponentName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.opponentPinkBright,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  '$opponentScore',
                  style: scoreStyle.copyWith(
                    color: AppTheme.opponentPinkBright.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

/// Pill button styles matching the maquette ("CONFIRMER" & dialog actions).
ButtonStyle gameOutlineButtonStyle(Color accent) => OutlinedButton.styleFrom(
      foregroundColor: accent,
      side: BorderSide(color: accent.withValues(alpha: 0.9), width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      ),
    );

ButtonStyle gameFilledButtonStyle(Color accent) => ElevatedButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      textStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.5,
      ),
    );

/// Maquette-styled dialog shell shared by every in-match popup (win, bust,
/// leave, forfeit, report): deep navy panel, accent border, uppercase
/// letterspaced title. [actionsBuilder] receives the dialog's own context so
/// actions can Navigator.pop the dialog route.
Future<T?> showGameDialog<T>(
  BuildContext context, {
  required Color accent,
  required IconData icon,
  required String title,
  Widget? content,
  required List<Widget> Function(BuildContext ctx) actionsBuilder,
  bool barrierDismissible = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => gameDialogFrame(
      accent: accent,
      icon: icon,
      title: title,
      content: content,
      actions: actionsBuilder(ctx),
    ),
  );
}

/// The dialog widget itself, exposed for callers that need a StatefulBuilder
/// or custom showDialog options around it.
Widget gameDialogFrame({
  required Color accent,
  required IconData icon,
  required String title,
  Widget? content,
  required List<Widget> actions,
}) {
  return AlertDialog(
    backgroundColor: AppTheme.gamePanelEmpty,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(color: accent.withValues(alpha: 0.7), width: 1.5),
    ),
    title: Row(children: [
      Icon(icon, color: accent, size: 26),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            color: accent,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
      ),
    ]),
    content: content,
    actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
    actions: actions,
  );
}

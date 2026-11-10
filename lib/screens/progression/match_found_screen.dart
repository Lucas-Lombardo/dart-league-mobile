import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/head_to_head.dart';
import '../../models/progression.dart';
import '../../services/stats_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/rank_translation.dart';
import '../../utils/rank_utils.dart';
import '../../widgets/progression/player_showcase_card.dart';
import '../progression/progression_format.dart';

/// One side of the "Match found" screen.
class MatchFoundPlayer {
  final String username;
  final String rank;
  final int? elo;
  final PublicCosmetics? cosmetics;

  /// The crown on the card (mine from my profile, the opponent's from
  /// match_found's `opponentPremium`).
  final bool isPremium;
  const MatchFoundPlayer({required this.username, required this.rank, this.elo, this.cosmetics, this.isPremium = false});
}

/// "Match found", piste B « Duel » validated by Lucas (mockups
/// ecrans/MtB.dc.html and MtDeroule.dc.html, generator `b()` / `countdown()`
/// / `vs_disc()` in docs/progression/svg/gen_match.py; CONTRACT §14.13).
///
/// The screen is cut on a diagonal, my side blue at the top left, the
/// opponent's pink at the bottom right. Me: « TOI », my S1 card, my ELO in
/// large and my rank. The VS disc on the seam. The opponent the same way,
/// right-aligned (« FANTÔME » for a ghost). Bottom left, what the series is
/// worth (`eloIfWin` / `eloIfLoss`, hidden when unknown) and the record;
/// bottom right, the 3-2-1 ring.
///
/// The [seconds] (6) play one scene, the same on both phones: my card slides
/// in at 0.3 s, theirs at 0.6 s, the VS drops at 0.9 s, the rest fades in at
/// 1.3 s, and the ring counts the last 3 seconds down. The navigation
/// (MatchmakingNavigationGate) leaves after [seconds]; nothing here can skip
/// it. With the system's "reduce motion", everything is there at once and
/// only the countdown moves. Both card blocks shrink together on a short
/// screen (FittedBox).
///
/// The record line is [recordLine] when given (the ghost's match), otherwise
/// with an [opponentId] it is fetched (GET /stats/head-to-head) and shown if
/// it arrives while the screen is up, never waited for.
class MatchFoundScreen extends StatefulWidget {
  final String subtitle;
  final MatchFoundPlayer me;
  final MatchFoundPlayer opponent;
  final String? recordLine;
  final String? opponentId;
  final int seconds;
  final bool isGhost;

  /// What the series is worth to me, from the server (match_found or the
  /// ghost match). « En jeu » is shown only when both are known.
  final int? eloIfWin;
  final int? eloIfLoss;

  /// Test seam: how the record is fetched (defaults to StatsService).
  final Future<HeadToHeadRecord?> Function(String opponentId)? loadRecord;

  /// The length of the scene (the déroulé of MtDeroule: 6 s instead of 2).
  static const int defaultSeconds = 6;

  /// When each element arrives (MtDeroule, `STEPS` of gen_match.py).
  static const Duration meAt = Duration(milliseconds: 300);
  static const Duration opponentAt = Duration(milliseconds: 600);
  static const Duration vsAt = Duration(milliseconds: 900);
  static const Duration detailsAt = Duration(milliseconds: 1300);

  /// The ring counts these last seconds down (3, 2, 1).
  static const int countdownSeconds = 3;

  /// The animated blocks, for tests.
  static const Key meKey = ValueKey('matchFound.me');
  static const Key opponentKey = ValueKey('matchFound.opponent');
  static const Key vsKey = ValueKey('matchFound.vs');
  static const Key myDetailsKey = ValueKey('matchFound.myDetails');
  static const Key opponentDetailsKey = ValueKey('matchFound.opponentDetails');
  static const Key stakesKey = ValueKey('matchFound.stakes');
  static const Key countdownKey = ValueKey('matchFound.countdown');

  /// Test seam for the screens built by the navigation gate.
  @visibleForTesting
  static Future<HeadToHeadRecord?> Function(String opponentId)? debugLoadRecord;

  const MatchFoundScreen({
    super.key,
    required this.subtitle,
    required this.me,
    required this.opponent,
    this.recordLine,
    this.opponentId,
    this.seconds = defaultSeconds,
    this.isGhost = false,
    this.eloIfWin,
    this.eloIfLoss,
    this.loadRecord,
  });

  static Route<void> route(MatchFoundScreen screen) => PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 150),
        pageBuilder: (_, _, _) => screen,
        transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
      );

  @override
  State<MatchFoundScreen> createState() => _MatchFoundScreenState();
}

class _MatchFoundScreenState extends State<MatchFoundScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _clock;
  HeadToHeadRecord? _record;
  bool? _reduceMotion;
  bool _vsBuzzed = false;

  // The scene, built once per "reduce motion" setting.
  final List<CurvedAnimation> _curves = [];
  late Animation<double> _meIn, _opponentIn, _vsIn, _seamIn, _detailsIn, _countdownIn, _vsScale;
  late Animation<Offset> _meSlide, _opponentSlide;

  // The VS falls for the first 45 % of its 400 ms, then bounces.
  static const Duration _vsLength = Duration(milliseconds: 400);
  static const double _vsFall = 0.45;

  int get _totalMs => math.max(1, widget.seconds) * 1000;
  double get _elapsedMs => _clock.value * _totalMs;
  int get _countdownStartMs => math.max(0, widget.seconds - MatchFoundScreen.countdownSeconds) * 1000;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: Duration(milliseconds: _totalMs))
      ..addListener(_buzzOnImpact)
      ..forward();
    // 0 s: the background and the title, a light tap.
    HapticService.lightImpact();
    final id = widget.opponentId;
    if (widget.recordLine == null && id != null && !widget.isGhost) _loadRecord(id);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      _buildScene();
    }
  }

  @override
  void dispose() {
    _disposeCurves();
    _clock.dispose();
    super.dispose();
  }

  void _disposeCurves() {
    for (final c in _curves) {
      c.dispose();
    }
    _curves.clear();
  }

  void _buildScene() {
    _disposeCurves();
    const fade = Duration(milliseconds: 200);
    _meIn = _window(MatchFoundScreen.meAt, fade, Curves.easeOut);
    _meSlide = _slide(MatchFoundScreen.meAt, -1.15);
    _opponentIn = _window(MatchFoundScreen.opponentAt, fade, Curves.easeOut);
    _opponentSlide = _slide(MatchFoundScreen.opponentAt, 1.15);
    _vsIn = _window(MatchFoundScreen.vsAt, const Duration(milliseconds: 120), Curves.easeOut);
    _seamIn = _window(MatchFoundScreen.vsAt, const Duration(milliseconds: 300), Curves.easeOut);
    _vsScale = _buildVsScale();
    _detailsIn = _window(MatchFoundScreen.detailsAt, const Duration(milliseconds: 300), Curves.easeOut);
    _countdownIn = _window(Duration(milliseconds: _countdownStartMs), fade, Curves.easeOut);
  }

  /// The VS lands: a second tap (not with "reduce motion": nothing drops).
  void _buzzOnImpact() {
    if (_vsBuzzed || _reduceMotion != false) return;
    final impact = MatchFoundScreen.vsAt.inMilliseconds + _vsLength.inMilliseconds * _vsFall;
    if (_elapsedMs < impact) return;
    _vsBuzzed = true;
    HapticService.mediumImpact();
  }

  Future<void> _loadRecord(String opponentId) async {
    try {
      final loader = widget.loadRecord ??
          MatchFoundScreen.debugLoadRecord ??
          (String id) async => (await StatsService.getHeadToHead(id)).record;
      final record = await loader(opponentId);
      if (mounted && record != null) setState(() => _record = record);
    } catch (_) {
      // No line rather than an error: the screen is only up for a moment.
    }
  }

  String? _recordText(AppLocalizations l10n) {
    if (widget.recordLine != null) return widget.recordLine;
    final r = _record;
    if (r == null) return null;
    return r.encounters == 0 ? l10n.matchFoundFirstMeeting : l10n.matchFoundDuelRecord(r.wins, r.losses);
  }

  /// [from] → [from + length] of the scene, as a 0 → 1 animation.
  Animation<double> _window(Duration from, Duration length, Curve curve) {
    if (_reduceMotion == true) return kAlwaysCompleteAnimation;
    final begin = (from.inMilliseconds / _totalMs).clamp(0.0, 1.0);
    final end = ((from + length).inMilliseconds / _totalMs).clamp(begin, 1.0);
    final curved = CurvedAnimation(parent: _clock, curve: Interval(begin, end, curve: curve));
    _curves.add(curved);
    return curved;
  }

  Animation<Offset> _slide(Duration from, double fromX) {
    if (_reduceMotion == true) return const AlwaysStoppedAnimation(Offset.zero);
    return Tween<Offset>(begin: Offset(fromX, 0), end: Offset.zero)
        .animate(_window(from, const Duration(milliseconds: 450), Curves.easeOutCubic));
  }

  Animation<double> _buildVsScale() {
    if (_reduceMotion == true) return const AlwaysStoppedAnimation(1.0);
    return TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.8, end: 1.0).chain(CurveTween(curve: Curves.easeInCubic)), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.9).chain(CurveTween(curve: Curves.easeOut)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0).chain(CurveTween(curve: Curves.easeInOut)), weight: 35),
    ]).animate(_window(MatchFoundScreen.vsAt, _vsLength, Curves.linear));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final details = _detailsIn;
    final recordLine = _recordText(l10n);

    final duel = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FadeTransition(
          key: MatchFoundScreen.meKey,
          opacity: _meIn,
          child: SlideTransition(
            position: _meSlide,
            child: _SideCard(label: l10n.matchFoundYou, player: widget.me, opponent: false),
          ),
        ),
        const SizedBox(height: 8),
        FadeTransition(
          key: MatchFoundScreen.myDetailsKey,
          opacity: details,
          child: Align(alignment: Alignment.centerLeft, child: _EloLine(player: widget.me, alignEnd: false)),
        ),
        SizedBox(
          height: 110,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -40,
                right: -40,
                top: 54,
                height: 2,
                child: FadeTransition(
                  opacity: _seamIn,
                  child: const _Seam(),
                ),
              ),
              FadeTransition(
                key: MatchFoundScreen.vsKey,
                opacity: _vsIn,
                child: ScaleTransition(scale: _vsScale, child: _VsDisc(text: l10n.matchFoundVsShort)),
              ),
            ],
          ),
        ),
        FadeTransition(
          key: MatchFoundScreen.opponentKey,
          opacity: _opponentIn,
          child: SlideTransition(
            position: _opponentSlide,
            child: _SideCard(
              label: widget.isGhost ? l10n.matchFoundGhost : l10n.matchFoundOpponent,
              player: widget.opponent,
              opponent: true,
            ),
          ),
        ),
        const SizedBox(height: 8),
        FadeTransition(
          key: MatchFoundScreen.opponentDetailsKey,
          opacity: details,
          child: Align(alignment: Alignment.centerRight, child: _EloLine(player: widget.opponent, alignEnd: true)),
        ),
      ],
    );

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: CustomPaint(
          painter: const MatchFoundBackdropPainter(),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Column(
                    children: [
                      Text(
                        l10n.matchFoundTitle,
                        textAlign: TextAlign.center,
                        style: _style(28, FontWeight.w800, AppTheme.textPrimary, letterSpacing: -0.56, height: 1.2),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        textAlign: TextAlign.center,
                        style: _style(14, FontWeight.w600, AppTheme.textSecondary, height: 1.35),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, box) => Align(
                              alignment: Alignment.topCenter,
                              // Both sides and the VS, scaled down together,
                              // proportionally, when the height runs short.
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.topCenter,
                                child: SizedBox(width: box.maxWidth, child: duel),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: FadeTransition(
                                key: MatchFoundScreen.stakesKey,
                                opacity: details,
                                child: _Stakes(
                                  eloIfWin: widget.eloIfWin,
                                  eloIfLoss: widget.eloIfLoss,
                                  recordLine: recordLine,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FadeTransition(
                              key: MatchFoundScreen.countdownKey,
                              opacity: _countdownIn,
                              child: _Countdown(
                                clock: _clock,
                                seconds: math.max(1, widget.seconds),
                                stepped: _reduceMotion == true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _style(
  double size,
  FontWeight weight,
  Color color, {
  double letterSpacing = 0,
  double? height,
  bool tabular = false,
}) =>
    TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );

/// « TOI » / « ADVERSAIRE » and the player's S1 card (no « Modifier », no XP
/// bar). A player without any equipped item still gets a real card: steel
/// rim, plain ground, the rank badge as avatar (PlayerShowcaseCard).
class _SideCard extends StatelessWidget {
  final String label;
  final MatchFoundPlayer player;
  final bool opponent;
  const _SideCard({required this.label, required this.player, required this.opponent});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          textAlign: opponent ? TextAlign.right : TextAlign.left,
          style: _style(
            12,
            FontWeight.w800,
            opponent ? const Color(0xFFFB7185) : AppTheme.playerBlueBright,
            letterSpacing: 1.4,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 8),
        PlayerShowcaseCard(
          username: player.username,
          rank: player.rank,
          cosmetics: player.cosmetics,
          isPremium: player.isPremium,
        ),
      ],
    );
  }
}

/// The ELO in large (40 / 800) next to the rank badge and name; mirrored on
/// the opponent's side. Only the rank when the ELO is unknown.
class _EloLine extends StatelessWidget {
  final MatchFoundPlayer player;
  final bool alignEnd;
  const _EloLine({required this.player, required this.alignEnd});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rank = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RankUtils.getRankBadge(player.rank, size: 22),
        const SizedBox(width: 6),
        Text(
          RankTranslation.translate(l10n, player.rank),
          style: _style(14, FontWeight.w700, const Color(0xFFCBD5E1), height: 1.3),
        ),
      ],
    );
    final elo = player.elo;
    if (elo == null) return SizedBox(height: 40, child: Center(widthFactor: 1, child: rank));
    final number = Text(
      formatXp(elo),
      style: _style(40, FontWeight.w800, AppTheme.textPrimary, letterSpacing: -1.2, height: 1, tabular: true),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: alignEnd ? [rank, const SizedBox(width: 10), number] : [number, const SizedBox(width: 10), rank],
    );
  }
}

/// The thin seam behind the VS disc, tilted like the background's cut
/// (-18°): blue fading in on the left, pink fading out on the right.
class _Seam extends StatelessWidget {
  const _Seam();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -18 * math.pi / 180,
      child: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0x0038BDF8), Color(0x7394A3B8), Color(0x00F43F5E)],
          ),
        ),
      ),
    );
  }
}

/// `vs_disc(72)`: a 72 pt disc of the background with a 2 pt slate border
/// and a 6 pt solid ring of the background around it (no glow).
class _VsDisc extends StatelessWidget {
  final String text;
  const _VsDisc({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.background,
        border: Border.all(color: AppTheme.surfaceLight, width: 2),
        boxShadow: const [BoxShadow(color: AppTheme.background, spreadRadius: 6)],
      ),
      child: Text(text, style: _style(26, FontWeight.w800, AppTheme.textPrimary, letterSpacing: -0.52, height: 1)),
    );
  }
}

/// Bottom left: « En jeu », « +18 / −6 ELO », then the record. Without
/// stakes (placement, an older server) the first two lines go.
class _Stakes extends StatelessWidget {
  final int? eloIfWin;
  final int? eloIfLoss;
  final String? recordLine;
  const _Stakes({required this.eloIfWin, required this.eloIfLoss, required this.recordLine});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final win = eloIfWin;
    final loss = eloIfLoss;
    final caption = _style(13, FontWeight.w700, AppTheme.textSecondary, height: 1.3);
    final lines = <Widget>[
      if (win != null && loss != null) ...[
        Text(l10n.matchFoundStakes, style: caption),
        Text.rich(
          TextSpan(
            style: _style(16, FontWeight.w800, AppTheme.textPrimary, height: 1.3, tabular: true),
            children: [
              TextSpan(text: _signed(win), style: const TextStyle(color: Color(0xFF4ADE80))),
              const TextSpan(text: ' / ', style: TextStyle(color: AppTheme.textTertiary)),
              TextSpan(text: _signed(loss), style: const TextStyle(color: AppTheme.opponentPinkBright)),
              TextSpan(text: ' ${l10n.eloLabel}'),
            ],
          ),
        ),
      ],
      if (recordLine != null) Text(recordLine!, maxLines: 2, overflow: TextOverflow.ellipsis, style: caption),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          lines[i],
        ],
      ],
    );
  }

  /// +18, −6 (a real minus sign), 0.
  static String _signed(int v) => v > 0 ? '+$v' : (v < 0 ? '−${-v}' : '0');
}

/// `countdown()`: a 64 pt ring (track #1E293B, arc #38BDF8, 5 pt) around the
/// digit, « Le match commence » under it. 3, 2, 1 over the last 3 seconds;
/// the ring empties with them (in steps with "reduce motion").
class _Countdown extends StatelessWidget {
  final Animation<double> clock;
  final int seconds;
  final bool stepped;
  const _Countdown({required this.clock, required this.seconds, required this.stepped});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final span = math.min(seconds, MatchFoundScreen.countdownSeconds).toDouble();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 64,
          child: AnimatedBuilder(
            animation: clock,
            builder: (context, _) {
              final remaining = seconds * (1 - clock.value);
              final digit = remaining.ceil().clamp(1, span.toInt());
              final fraction = stepped ? digit / span : (remaining / span).clamp(0.0, 1.0);
              return CustomPaint(
                painter: _RingPainter(fraction),
                child: Center(
                  child: Text(
                    '$digit',
                    style: _style(28, FontWeight.w800, AppTheme.textPrimary, height: 1, tabular: true),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(l10n.matchFoundStarting, style: _style(13, FontWeight.w700, AppTheme.textSecondary, height: 1.3)),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  const _RingPainter(this.fraction);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 64;
    final center = size.center(Offset.zero);
    final radius = 28 * scale;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * scale;
    canvas.drawCircle(center, radius, stroke..color = AppTheme.surface);
    if (fraction <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      stroke
        ..color = AppTheme.primaryLight
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction;
}

/// The background of `b()`: `linear-gradient(162deg, #0B2540 0%, #0F172A
/// 49.6%, #2A0E1D 50.4%, #170A14 100%)`, i.e. a cut through the middle of the
/// screen rising 18° to the right, bluish above, pinkish below. Computed like
/// CSS (the gradient line through the centre, as long as the box needs).
class MatchFoundBackdropPainter extends CustomPainter {
  const MatchFoundBackdropPainter();

  static const double angleDeg = 162;

  @override
  void paint(Canvas canvas, Size size) {
    final a = angleDeg * math.pi / 180;
    final dir = Offset(math.sin(a), -math.cos(a));
    final half = (size.width * math.sin(a).abs() + size.height * math.cos(a).abs()) / 2;
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        c - dir * half,
        c + dir * half,
        const [Color(0xFF0B2540), Color(0xFF0F172A), Color(0xFF2A0E1D), Color(0xFF170A14)],
        const [0, 0.496, 0.504, 1],
      );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(MatchFoundBackdropPainter old) => false;
}

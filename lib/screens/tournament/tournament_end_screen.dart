import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/tournament.dart';
import '../../providers/auth_provider.dart';
import '../../providers/tournament_game_provider.dart';
import '../../services/tournament_service.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../l10n/app_localizations.dart';

class TournamentEndScreen extends StatefulWidget {
  final String tournamentId;
  final String tournamentName;
  final String roundName;
  final bool didWin;
  final String opponentUsername;
  final int myLegsWon;
  final int opponentLegsWon;

  const TournamentEndScreen({
    super.key,
    required this.tournamentId,
    required this.tournamentName,
    required this.roundName,
    required this.didWin,
    required this.opponentUsername,
    required this.myLegsWon,
    required this.opponentLegsWon,
  });

  @override
  State<TournamentEndScreen> createState() => _TournamentEndScreenState();
}

class _TournamentEndScreenState extends State<TournamentEndScreen>
    with TickerProviderStateMixin {
  late final AnimationController _mainCtrl;
  late final AnimationController _glowCtrl;
  late final AnimationController _confettiCtrl;

  late final Animation<double> _medalScale;
  late final Animation<double> _medalFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _titleFade;
  late final Animation<double> _subtitleFade;
  late final Animation<double> _buttonFade;

  List<TournamentMatch> _myMatches = [];
  bool _loading = true;
  late final int _placement;

  @override
  void initState() {
    super.initState();
    _placement = _calcPlacement(widget.roundName, widget.didWin);

    _mainCtrl = AnimationController(duration: const Duration(milliseconds: 2500), vsync: this);
    _glowCtrl = AnimationController(duration: const Duration(milliseconds: 1800), vsync: this)
      ..repeat(reverse: true);
    _confettiCtrl = AnimationController(duration: const Duration(milliseconds: 4000), vsync: this);

    _medalScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainCtrl, curve: const Interval(0.0, 0.45, curve: Curves.elasticOut)),
    );
    _medalFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainCtrl, curve: const Interval(0.0, 0.25, curve: Curves.easeIn)),
    );
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
      CurvedAnimation(parent: _mainCtrl, curve: const Interval(0.35, 0.65, curve: Curves.easeOut)),
    );
    _titleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainCtrl, curve: const Interval(0.35, 0.6, curve: Curves.easeIn)),
    );
    _subtitleFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainCtrl, curve: const Interval(0.55, 0.75, curve: Curves.easeIn)),
    );
    _buttonFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainCtrl, curve: const Interval(0.88, 1.0, curve: Curves.easeIn)),
    );

    _mainCtrl.forward().then((_) {
      if (_placement == 1) {
        HapticService.heavyImpact();
      } else if (_placement <= 3) {
        HapticService.mediumImpact();
      }
    });

    if (_placement == 1) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _confettiCtrl.repeat();
      });
    }

    _loadBracket();
  }

  Future<void> _loadBracket() async {
    try {
      final matches = await TournamentService.getBracket(widget.tournamentId);
      final auth = context.read<AuthProvider>();
      final myId = auth.currentUser?.id;
      if (myId != null) {
        final myMatches = matches
            .where((m) => m.isCompleted && (m.player1Id == myId || m.player2Id == myId))
            .toList()
          ..sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
        if (mounted) setState(() { _myMatches = myMatches; _loading = false; });
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _calcPlacement(String roundName, bool didWin) {
    if (roundName == 'final') return didWin ? 1 : 2;
    if (roundName == 'semi_final') return 3;
    if (roundName == 'quarter_final') return 5;
    if (roundName == 'round_of_16') return 9;
    if (roundName == 'round_of_32') return 17;
    return 0;
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _glowCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  Color get _medalColor {
    if (_placement == 1) return const Color(0xFFFFD700);
    if (_placement == 2) return const Color(0xFFC0C0C0);
    if (_placement <= 4) return const Color(0xFFCD7F32);
    return AppTheme.error;
  }

  IconData get _medalIcon {
    if (_placement <= 3) return Icons.emoji_events;
    if (_placement <= 5) return Icons.military_tech;
    return Icons.sentiment_dissatisfied;
  }

  String _placementOrdinal(AppLocalizations l10n) {
    if (_placement == 1) return l10n.tournamentFirstPlace;
    if (_placement == 2) return l10n.tournamentSecondPlace;
    if (_placement <= 4) return l10n.tournamentThirdFourthPlace;
    if (_placement <= 8) return l10n.tournamentTopEight;
    if (_placement <= 16) return l10n.tournamentTopSixteen;
    return l10n.tournamentParticipant;
  }

  String _placementTitle(AppLocalizations l10n) {
    if (_placement == 1) return l10n.tournamentChampion;
    if (_placement == 2) return l10n.tournamentRunnerUp;
    if (_placement <= 4) return l10n.tournamentSemiFinalist;
    if (_placement <= 8) return l10n.tournamentQuarterFinalist;
    return l10n.tournamentParticipant;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = context.read<AuthProvider>();
    final myId = auth.currentUser?.id;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
          child: Stack(
            children: [
              if (_placement == 1)
                AnimatedBuilder(
                  animation: _confettiCtrl,
                  builder: (_, __) => CustomPaint(
                    painter: _ConfettiPainter(_confettiCtrl.value),
                    size: Size.infinite,
                  ),
                ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 32),

                      // Medal / trophy
                      FadeTransition(
                        opacity: _medalFade,
                        child: ScaleTransition(
                          scale: _medalScale,
                          child: AnimatedBuilder(
                            animation: _glowCtrl,
                            builder: (_, __) => Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: _medalColor.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                                border: Border.all(color: _medalColor, width: 3),
                                boxShadow: [
                                  BoxShadow(
                                    color: _medalColor.withValues(alpha: 0.25 + 0.25 * _glowCtrl.value),
                                    blurRadius: 24 + 20 * _glowCtrl.value,
                                    spreadRadius: 4 + 8 * _glowCtrl.value,
                                  ),
                                ],
                              ),
                              child: Icon(_medalIcon, color: _medalColor, size: 60),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Ordinal + title
                      SlideTransition(
                        position: _titleSlide,
                        child: FadeTransition(
                          opacity: _titleFade,
                          child: Column(
                            children: [
                              Text(
                                _placementOrdinal(l10n).toUpperCase(),
                                style: TextStyle(
                                  color: _medalColor,
                                  fontSize: 38,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _placementTitle(l10n),
                                style: TextStyle(
                                  color: _medalColor.withValues(alpha: 0.8),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Tournament name badge
                      FadeTransition(
                        opacity: _subtitleFade,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            widget.tournamentName,
                            style: const TextStyle(
                              color: AppTheme.primary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Journey label
                      FadeTransition(
                        opacity: _subtitleFade,
                        child: Text(
                          l10n.yourTournamentJourney.toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Match history (scrollable, flexible)
                      Flexible(
                        child: _loading
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2),
                                ),
                              )
                            : SingleChildScrollView(
                                child: Column(
                                  children: _buildMatchCards(myId, l10n),
                                ),
                              ),
                      ),

                      const SizedBox(height: 16),

                      // Return home button
                      FadeTransition(
                        opacity: _buttonFade,
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: () {
                              HapticService.mediumImpact();
                              final provider = context.read<TournamentGameProvider>();
                              AppNavigator.toHomeClearing(context);
                              try { provider.reset(); } catch (_) {}
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _placement == 1 ? _medalColor : AppTheme.primary,
                              foregroundColor: _placement == 1 ? Colors.black : Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: Text(
                              l10n.returnHome.toUpperCase(),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMatchCards(String? myId, AppLocalizations l10n) {
    final matches = _myMatches.isNotEmpty
        ? _myMatches
        : [
            _FallbackMatch(
              roundName: widget.roundName,
              opponentUsername: widget.opponentUsername,
              myLegsWon: widget.myLegsWon,
              opponentLegsWon: widget.opponentLegsWon,
              didWin: widget.didWin,
            )
          ];

    return matches.asMap().entries.map((entry) {
      final i = entry.key;
      final m = entry.value;

      String roundDisplay;
      String rName;
      String oppName;
      int myScore;
      int oppScore;
      bool didWin;

      if (m is TournamentMatch) {
        rName = m.roundName;
        final isP1 = m.player1Id == myId;
        myScore = isP1 ? m.player1Score : m.player2Score;
        oppScore = isP1 ? m.player2Score : m.player1Score;
        oppName = (isP1 ? m.player2Username : m.player1Username) ?? '?';
        didWin = m.winnerId == myId;
      } else {
        final fb = m as _FallbackMatch;
        rName = fb.roundName;
        myScore = fb.myLegsWon;
        oppScore = fb.opponentLegsWon;
        oppName = fb.opponentUsername;
        didWin = fb.didWin;
      }

      roundDisplay = _roundDisplay(rName, l10n);

      final startFrac = math.min(0.65 + i * 0.06, 0.92);
      final endFrac = math.min(startFrac + 0.20, 1.0);

      final fadeFrac = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _mainCtrl, curve: Interval(startFrac, endFrac, curve: Curves.easeOut)),
      );
      final slideFrac = Tween<Offset>(begin: const Offset(0.3, 0), end: Offset.zero).animate(
        CurvedAnimation(parent: _mainCtrl, curve: Interval(startFrac, endFrac, curve: Curves.easeOut)),
      );

      final winColor = didWin ? AppTheme.success : AppTheme.error;

      return FadeTransition(
        opacity: fadeFrac,
        child: SlideTransition(
          position: slideFrac,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: winColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    roundDisplay,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${l10n.vs} $oppName',
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$myScore - $oppScore',
                  style: TextStyle(color: winColor, fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: winColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    didWin ? 'W' : 'L',
                    style: TextStyle(color: winColor, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  String _roundDisplay(String roundName, AppLocalizations l10n) {
    switch (roundName) {
      case 'final': return l10n.roundFinal;
      case 'semi_final': return l10n.roundSemiFinal;
      case 'quarter_final': return l10n.roundQuarterFinal;
      case 'round_of_16': return l10n.roundOf16;
      case 'round_of_32': return l10n.roundOf32;
      case 'round_of_64': return l10n.roundOf64;
      default: return roundName.replaceAll('_', ' ');
    }
  }
}

/// Used as a fallback when bracket data is unavailable
class _FallbackMatch {
  final String roundName;
  final String opponentUsername;
  final int myLegsWon;
  final int opponentLegsWon;
  final bool didWin;
  const _FallbackMatch({
    required this.roundName,
    required this.opponentUsername,
    required this.myLegsWon,
    required this.opponentLegsWon,
    required this.didWin,
  });
}

// ─── Confetti (1st place only) ────────────────────────────────────────────────

class _ConfettiPainter extends CustomPainter {
  final double progress;
  static final _rng = math.Random(42);
  static final _particles = List.generate(70, (_) => _ConfettiParticle(_rng));

  const _ConfettiPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      p.draw(canvas, size, progress);
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

class _ConfettiParticle {
  final double _x;
  final double _yStart;
  final double _speed;
  final double _size;
  final double _rotation;
  final double _rotSpeed;
  final double _swayAmp;
  final double _swayFreq;
  final Color _color;

  _ConfettiParticle(math.Random rng)
      : _x = rng.nextDouble(),
        _yStart = -0.05 - rng.nextDouble() * 0.4,
        _speed = 0.35 + rng.nextDouble() * 0.55,
        _size = 5.0 + rng.nextDouble() * 8.0,
        _rotation = rng.nextDouble() * math.pi * 2,
        _rotSpeed = (rng.nextDouble() - 0.5) * 10,
        _swayAmp = 0.015 + rng.nextDouble() * 0.035,
        _swayFreq = 1.5 + rng.nextDouble() * 2.5,
        _color = const [
          Color(0xFFFFD700),
          Color(0xFF22C55E),
          Color(0xFF0EA5E9),
          Color(0xFFF43F5E),
          Colors.white,
          Color(0xFFEAB308),
          Color(0xFFA855F7),
        ][rng.nextInt(7)];

  void draw(Canvas canvas, Size size, double progress) {
    final y = _yStart + progress * _speed;
    if (y > 1.1 || y < -0.15) return;
    final px = (_x + math.sin(progress * _swayFreq * math.pi * 2) * _swayAmp) * size.width;
    final py = y * size.height;
    final alpha = math.max(0.0, 1.0 - math.max(0.0, (y - 0.75) / 0.3));
    canvas.save();
    canvas.translate(px, py);
    canvas.rotate(_rotation + progress * _rotSpeed);
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: _size, height: _size * 0.45),
      Paint()..color = _color.withValues(alpha: alpha),
    );
    canvas.restore();
  }
}

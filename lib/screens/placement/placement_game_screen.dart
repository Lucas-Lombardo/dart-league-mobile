import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../providers/placement_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/game_provider.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/interactive_dartboard.dart';

class PlacementGameScreen extends StatefulWidget {
  const PlacementGameScreen({super.key});

  @override
  State<PlacementGameScreen> createState() => _PlacementGameScreenState();
}

class _PlacementGameScreenState extends State<PlacementGameScreen> {
  bool _botTurnInProgress = false;
  bool _gameEnded = false;
  String? _winnerId;
  int? _editingDartIndex;

  // Local scoring state (no sockets)
  int _myScore = 501;
  int _dartsThrown = 0;
  List<_DartThrow> _currentRoundThrows = [];
  int _scoreBeforeRound = 501;
  bool _isBust = false;
  bool _isWin = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  int _dartScore(int baseScore, ScoreMultiplier multiplier) {
    switch (multiplier) {
      case ScoreMultiplier.single:
        return baseScore;
      case ScoreMultiplier.double:
        return baseScore * 2;
      case ScoreMultiplier.triple:
        return baseScore * 3;
    }
  }

  void _throwDart(int baseScore, ScoreMultiplier multiplier) {
    if (_dartsThrown >= 3 || _botTurnInProgress || _gameEnded || _isBust || _isWin) return;

    // If editing an existing dart, replace it
    if (_editingDartIndex != null && _editingDartIndex! < _currentRoundThrows.length) {
      setState(() {
        _currentRoundThrows[_editingDartIndex!] = _DartThrow(baseScore, multiplier);
        _editingDartIndex = null;
      });
      _recalculateScore();
      return;
    }

    final score = _dartScore(baseScore, multiplier);
    final newScore = _myScore - score;

    // Bust: score goes below 0, equals 1, or hits 0 without a double
    if (newScore < 0 || newScore == 1 || (newScore == 0 && multiplier != ScoreMultiplier.double)) {
      setState(() {
        _isBust = true;
        _currentRoundThrows.add(_DartThrow(baseScore, multiplier));
        _dartsThrown++;
      });
      return;
    }

    setState(() {
      _myScore = newScore;
      _currentRoundThrows.add(_DartThrow(baseScore, multiplier));
      _dartsThrown++;
    });

    // Check win (checkout on double) — don't auto-end, show confirm button
    if (newScore == 0 && multiplier == ScoreMultiplier.double) {
      setState(() => _isWin = true);
      return;
    }
  }

  void _recalculateScore() {
    int score = _scoreBeforeRound;
    bool bust = false;
    bool win = false;

    for (final dart in _currentRoundThrows) {
      final s = _dartScore(dart.baseScore, dart.multiplier);
      final newScore = score - s;
      if (newScore < 0 || newScore == 1 || (newScore == 0 && dart.multiplier != ScoreMultiplier.double)) {
        bust = true;
        break;
      }
      score = newScore;
      if (score == 0 && dart.multiplier == ScoreMultiplier.double) {
        win = true;
        break;
      }
    }

    setState(() {
      _myScore = bust ? _scoreBeforeRound : score;
      _dartsThrown = _currentRoundThrows.length;
      _isBust = bust;
      _isWin = win;
    });
  }

  void _confirmRound() {
    if (_isWin) {
      final auth = context.read<AuthProvider>();
      _handleGameEnd(auth.currentUser?.id);
      return;
    }

    if (_isBust) {
      // Bust: revert score
      setState(() {
        _myScore = _scoreBeforeRound;
        _dartsThrown = 0;
        _currentRoundThrows = [];
        _isBust = false;
        _scoreBeforeRound = _myScore;
      });
    } else {
      setState(() {
        _dartsThrown = 0;
        _currentRoundThrows = [];
        _scoreBeforeRound = _myScore;
      });
    }

    // Trigger bot turn
    _executeBotTurn();
  }

  Future<void> _executeBotTurn() async {
    if (_botTurnInProgress || _gameEnded) return;

    setState(() => _botTurnInProgress = true);

    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    final placement = context.read<PlacementProvider>();
    final success = await placement.triggerBotTurn();

    if (success && mounted) {
      // Short delay to show bot throws
      await Future.delayed(const Duration(milliseconds: 1200));

      // Check if bot checked out
      if (placement.botIsCheckout && placement.player2Score == 0) {
        _handleGameEnd(null);
        return;
      }
    }

    if (mounted) {
      setState(() => _botTurnInProgress = false);
    }
  }

  void _handleGameEnd(String? winnerId) async {
    setState(() {
      _gameEnded = true;
      _winnerId = winnerId;
    });

    final placement = context.read<PlacementProvider>();
    final result = await placement.completeMatch(winnerId, player1Score: _myScore);

    if (mounted && result != null) {
      await context.read<AuthProvider>().checkAuthStatus();
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final placement = context.watch<PlacementProvider>();
    final auth = context.watch<AuthProvider>();

    if (_gameEnded) {
      final didWin = _winnerId == auth.currentUser?.id;
      return _buildGameEndScreen(didWin);
    }

    if (placement.currentMatchId == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _showLeaveDialog();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Container(
        color: AppTheme.surface,
        child: SafeArea(
          top: false,
          child: Scaffold(
            backgroundColor: AppTheme.background,
            appBar: AppBar(
              backgroundColor: AppTheme.surface,
              title: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _botTurnInProgress ? AppTheme.accent : AppTheme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _botTurnInProgress ? AppLocalizations.of(context).botTurn : AppLocalizations.of(context).placementMatch,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              centerTitle: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                onPressed: () async {
                  final shouldLeave = await _showLeaveDialog();
                  if (shouldLeave && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              actions: [
                if (!_botTurnInProgress)
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.sports_esports_outlined,
                            size: 16, color: AppTheme.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          'Dart ${_dartsThrown + 1}/3',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            body: Container(
              color: AppTheme.background,
              child: Stack(
                children: [
                  Column(
                    children: [
                      // Bot turn display area
                      if (_botTurnInProgress)
                        _buildBotTurnDisplay(placement),

                      // Controls Area (dartboard)
                      Expanded(
                        flex: 6,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(24),
                              topRight: Radius.circular(24),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 10,
                                offset: Offset(0, -4),
                              ),
                            ],
                          ),
                          child: _botTurnInProgress
                              ? _buildWaitingForBot()
                              : _buildDartboard(),
                        ),
                      ),
                    ],
                  ),

                  // Top bar with scores (only during user's turn)
                  if (!_botTurnInProgress)
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left: Player score + dart indicators + MISS + CONFIRM
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceLight.withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppTheme.surfaceLight, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        AppLocalizations.of(context).yourScore,
                                        style: const TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      Text(
                                        '$_myScore',
                                        style: TextStyle(
                                          color: _myScore <= 170 ? AppTheme.success : AppTheme.primary,
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      ...List.generate(3, (index) {
                                        final hasThrow = index < _currentRoundThrows.length;
                                        final isNext = index == _currentRoundThrows.length;
                                        final isEditing = _editingDartIndex == index;
                                        return GestureDetector(
                                          onTap: hasThrow ? () {
                                            HapticService.lightImpact();
                                            setState(() {
                                              _editingDartIndex = isEditing ? null : index;
                                            });
                                          } : null,
                                          child: Container(
                                            width: 40,
                                            height: 40,
                                            margin: const EdgeInsets.only(right: 8),
                                            decoration: BoxDecoration(
                                              color: isEditing
                                                  ? AppTheme.error.withValues(alpha: 0.3)
                                                  : hasThrow
                                                      ? AppTheme.primary.withValues(alpha: 0.2)
                                                      : AppTheme.background,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(
                                                color: isEditing
                                                    ? AppTheme.error
                                                    : hasThrow
                                                        ? AppTheme.primary
                                                        : isNext
                                                            ? Colors.white24
                                                            : Colors.transparent,
                                                width: isEditing ? 3 : (hasThrow || isNext ? 2 : 1),
                                              ),
                                            ),
                                            child: Center(
                                              child: hasThrow
                                                  ? Text(
                                                      _currentRoundThrows[index].notation,
                                                      style: TextStyle(
                                                        color: isEditing ? AppTheme.error : AppTheme.primary,
                                                        fontSize: 14,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    )
                                                  : Icon(
                                                      Icons.adjust,
                                                      color: isNext ? Colors.white54 : Colors.white10,
                                                      size: 16,
                                                    ),
                                            ),
                                          ),
                                        );
                                      }),
                                      // MISS button
                                      Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            HapticService.mediumImpact();
                                            _throwDart(0, ScoreMultiplier.single);
                                          },
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            width: 50,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: AppTheme.background,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: AppTheme.surfaceLight, width: 2),
                                            ),
                                            child: const Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.close, color: Colors.white70, size: 16),
                                                Text('MISS', style: TextStyle(color: Colors.white70, fontSize: 7, fontWeight: FontWeight.bold)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Right: Bot score card
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.surfaceLight.withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.surfaceLight, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.smart_toy, color: AppTheme.accent, size: 14),
                                    const SizedBox(width: 4),
                                    Text(
                                      'BOT #${placement.currentBotDifficulty ?? 1}',
                                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('SCORE: ', style: TextStyle(color: AppTheme.textSecondary, fontSize: 8, fontWeight: FontWeight.bold)),
                                    Text('${placement.player2Score}', style: const TextStyle(color: AppTheme.primary, fontSize: 20, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBotTurnDisplay(PlacementProvider placement) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      color: AppTheme.surface,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.smart_toy, color: AppTheme.accent, size: 32),
              const SizedBox(width: 12),
              Text(
                'Bot #${placement.currentBotDifficulty ?? 1} is throwing...',
                style: const TextStyle(color: AppTheme.accent, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              placement.lastBotThrows.length,
              (index) {
                final t = placement.lastBotThrows[index];
                return Container(
                  width: 60,
                  height: 50,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.primary, width: 2),
                  ),
                  child: Center(
                    child: Text(t.notation, style: const TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          if (placement.botIsBust)
            Text(AppLocalizations.of(context).bust, style: const TextStyle(color: AppTheme.error, fontSize: 16, fontWeight: FontWeight.bold))
          else if (placement.botIsCheckout)
            Text(AppLocalizations.of(context).checkout, style: const TextStyle(color: AppTheme.success, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _scoreColumn(AppLocalizations.of(context).you, _myScore),
              _scoreColumn(AppLocalizations.of(context).bot, placement.player2Score),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scoreColumn(String label, int score) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
        Text('$score', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 28, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildWaitingForBot() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.accent),
          const SizedBox(height: 16),
          Text(AppLocalizations.of(context).botIsThrowing, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildDartboard() {
    return Column(
      children: [
        const Spacer(flex: 1),
        Expanded(
          flex: 3,
          child: Container(
            color: AppTheme.surface,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: InteractiveDartboard(
              onDartThrow: (baseScore, multiplier) {
                HapticService.mediumImpact();
                _throwDart(baseScore, multiplier);
              },
            ),
          ),
        ),
        // Bottom confirm button — always visible
        Container(
          padding: const EdgeInsets.all(16),
          color: AppTheme.surface,
          child: SizedBox(
            width: double.infinity,
            height: 64,
            child: ElevatedButton(
              onPressed: _dartsThrown > 0
                  ? () {
                      HapticService.heavyImpact();
                      _confirmRound();
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isBust
                    ? AppTheme.error
                    : _isWin
                        ? AppTheme.success
                        : AppTheme.primary,
                disabledBackgroundColor: AppTheme.primary.withValues(alpha: 0.3),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isBust
                        ? AppLocalizations.of(context).bustConfirm
                        : _isWin
                            ? AppLocalizations.of(context).confirmWin
                            : _dartsThrown >= 3
                                ? AppLocalizations.of(context).confirmAndEndTurn
                                : AppLocalizations.of(context).endTurnEarly,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(_isBust ? Icons.replay : Icons.check_circle_outline),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGameEndScreen(bool didWin) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: didWin
                        ? AppTheme.success.withValues(alpha: 0.1)
                        : AppTheme.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: didWin ? AppTheme.success : AppTheme.error,
                      width: 4,
                    ),
                  ),
                  child: Icon(
                    didWin ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                    color: didWin ? AppTheme.success : AppTheme.error,
                    size: 80,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  didWin ? '${AppLocalizations.of(context).victory.toUpperCase()}!' : AppLocalizations.of(context).defeat.toUpperCase(),
                  style: AppTheme.displayLarge.copyWith(
                    color: didWin ? AppTheme.success : AppTheme.error,
                    fontSize: 48,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  didWin
                      ? '${AppLocalizations.of(context).youWon.replaceAll('!', '')} — bot'
                      : '${AppLocalizations.of(context).youLost} — bot',
                  style: AppTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),
                const CircularProgressIndicator(color: AppTheme.primary),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context).savingResult,
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _showLeaveDialog() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppTheme.error, width: 2),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning, color: AppTheme.error, size: 32),
            const SizedBox(width: 12),
            Text(
              AppLocalizations.of(context).leaveMatch,
              style: AppTheme.titleLarge.copyWith(
                color: AppTheme.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          AppLocalizations.of(context).leaveMatchWarning,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppLocalizations.of(context).stay),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            child: Text(AppLocalizations.of(context).leave),
          ),
        ],
      ),
    );
    return shouldLeave ?? false;
  }
}

class _DartThrow {
  final int baseScore;
  final ScoreMultiplier multiplier;

  _DartThrow(this.baseScore, this.multiplier);

  String get notation {
    switch (multiplier) {
      case ScoreMultiplier.single:
        return 'S$baseScore';
      case ScoreMultiplier.double:
        return 'D$baseScore';
      case ScoreMultiplier.triple:
        return 'T$baseScore';
    }
  }
}

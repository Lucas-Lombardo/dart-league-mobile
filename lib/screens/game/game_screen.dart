import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/socket_service.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_theme.dart';

class GameScreen extends StatefulWidget {
  final String matchId;
  final String opponentId;

  const GameScreen({
    super.key,
    required this.matchId,
    required this.opponentId,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  int? _selectedNumber;
  ScoreMultiplier _selectedMultiplier = ScoreMultiplier.single;
  late AnimationController _scoreAnimationController;

  @override
  void initState() {
    super.initState();
    
    debugPrint('🎮 GameScreen initState - matchId: ${widget.matchId}, opponentId: ${widget.opponentId}');
    
    _scoreAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final game = context.read<GameProvider>();
        final auth = context.read<AuthProvider>();
        
        if (auth.currentUser != null) {
          game.initGame(widget.matchId, auth.currentUser!.id, widget.opponentId);
        }
      } catch (e, stackTrace) {
        debugPrint('❌ GameScreen initState error: $e');
        debugPrint('Stack trace: $stackTrace');
      }
    });
  }

  @override
  void dispose() {
    _scoreAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    try {
      final game = context.watch<GameProvider>();
      final auth = context.watch<AuthProvider>();
      
      final matchId = game.matchId;
      final gameStarted = game.gameStarted;

      // Show loading if game not initialized or started
      if (matchId == null || !gameStarted) {
        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: AppTheme.primary),
                SizedBox(height: 16),
                Text(
                  'INITIALIZING MATCH...',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      final gameEnded = game.gameEnded;
      
      if (gameEnded) {
        final winnerId = game.winnerId;
        final currentUserId = auth.currentUser?.id;
        final didWin = winnerId == currentUserId;
        
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: AppTheme.surfaceGradient,
            ),
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
                        boxShadow: [
                          BoxShadow(
                            color: (didWin ? AppTheme.success : AppTheme.error).withValues(alpha: 0.4),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(
                        didWin ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                        color: didWin ? AppTheme.success : AppTheme.error,
                        size: 80,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      didWin ? 'VICTORY!' : 'DEFEAT',
                      style: AppTheme.displayLarge.copyWith(
                        color: didWin ? AppTheme.success : AppTheme.error,
                        fontSize: 48,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      didWin 
                          ? 'You have proven yourself a legend.' 
                          : 'Training is the path to greatness.',
                      style: AppTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 64),
                    ElevatedButton(
                      onPressed: () {
                        HapticService.mediumImpact();
                        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text(
                        'RETURN TO LOBBY',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final dartsThrown = game.dartsThrown;

      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.surface,
          title: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'LIVE MATCH',
                style: TextStyle(
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
            onPressed: () {
              // Confirm exit dialog could be added here
              Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
            },
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  const Icon(Icons.sports_esports_outlined, size: 16, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Dart ${dartsThrown + 1}/3',
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
        body: Column(
          children: [
            // Scoreboard Area
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Player (You)
                    Expanded(
                      child: _buildPlayerScoreCard(
                        'YOU',
                        game.myScore,
                        game.isMyTurn,
                        true,
                      ),
                    ),
                    // Vs Divider / Info
                    SizedBox(
                      width: 40,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 1,
                            height: 40,
                            color: AppTheme.surfaceLight,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'VS',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            width: 1,
                            height: 40,
                            color: AppTheme.surfaceLight,
                          ),
                        ],
                      ),
                    ),
                    // Opponent
                    Expanded(
                      child: _buildPlayerScoreCard(
                        'OPPONENT',
                        game.opponentScore,
                        !game.isMyTurn,
                        false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Current Round Darts Display
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              color: AppTheme.surface.withValues(alpha: 0.5),
              child: _buildCurrentRoundDisplay(game),
            ),

            // Controls Area
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
                child: _buildScoreInput(game),
              ),
            ),
          ],
        ),
      );
    } catch (e, stackTrace) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Text('Error: $e\n$stackTrace'),
        ),
      );
    }
  }

  Widget _buildPlayerScoreCard(String label, int score, bool isActive, bool isMe) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: isActive 
            ? (isMe ? AppTheme.primary.withValues(alpha: 0.1) : AppTheme.error.withValues(alpha: 0.1))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive 
              ? (isMe ? AppTheme.primary : AppTheme.error)
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: isActive 
                  ? (isMe ? AppTheme.primary : AppTheme.error)
                  : AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$score',
            style: TextStyle(
              color: Colors.white,
              fontSize: 64,
              fontWeight: FontWeight.bold,
              shadows: isActive ? [
                BoxShadow(
                  color: (isMe ? AppTheme.primary : AppTheme.error).withValues(alpha: 0.5),
                  blurRadius: 20,
                )
              ] : [],
            ),
          ),
          if (isActive) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: (isMe ? AppTheme.primary : AppTheme.error),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'THROWING',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrentRoundDisplay(GameProvider game) {
    final throws = game.currentRoundThrows;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final hasThrow = index < throws.length;
        final isNext = index == throws.length;
        
        return Container(
          width: 60,
          height: 60,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: hasThrow 
                ? AppTheme.primary.withValues(alpha: 0.2)
                : AppTheme.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasThrow 
                  ? AppTheme.primary 
                  : isNext && game.isMyTurn 
                      ? Colors.white24 
                      : Colors.transparent,
              width: hasThrow || (isNext && game.isMyTurn) ? 2 : 1,
            ),
            boxShadow: hasThrow ? [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.2),
                blurRadius: 8,
              )
            ] : null,
          ),
          child: Center(
            child: hasThrow 
              ? Text(
                  throws[index],
                  style: const TextStyle(
                    color: AppTheme.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : Icon(
                  Icons.adjust,
                  color: isNext && game.isMyTurn ? Colors.white54 : Colors.white10,
                  size: 20,
                ),
          ),
        );
      }),
    );
  }

  Widget _buildScoreInput(GameProvider game) {
    // Round Completion State
    if (game.currentRoundThrows.length >= 3) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'ROUND COMPLETE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Score: ${game.currentRoundScore}',
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 64,
                child: ElevatedButton(
                  onPressed: () {
                    HapticService.heavyImpact();
                    final auth = context.read<AuthProvider>();
                    SocketService.emit('confirm_round', {
                      'matchId': game.matchId,
                      'playerId': auth.currentUser?.id,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'CONFIRM & END TURN',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.check_circle_outline),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Waiting for Turn State
    if (!game.isMyTurn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: AppTheme.error,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "OPPONENT'S TURN",
              style: TextStyle(
                color: AppTheme.error.withValues(alpha: 0.8),
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Please wait...",
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Active Input State
    return Column(
      children: [
        // Multiplier Toggles
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(child: _buildMultiplierButton('SINGLE', ScoreMultiplier.single, const Color(0xFF00E5FF))),
                Expanded(child: _buildMultiplierButton('DOUBLE', ScoreMultiplier.double, const Color(0xFF4CAF50))),
                Expanded(child: _buildMultiplierButton('TRIPLE', ScoreMultiplier.triple, const Color(0xFFFF9800))),
              ],
            ),
          ),
        ),
        
        // Number Grid
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildNumberGrid(),
          ),
        ),

        // Action Button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _selectedNumber != null
                  ? () {
                      HapticService.mediumImpact();
                      game.throwDart(
                        baseScore: _selectedNumber!,
                        multiplier: _selectedMultiplier,
                      );
                      setState(() {
                        _selectedNumber = null;
                        _selectedMultiplier = ScoreMultiplier.single; // Reset multiplier
                      });
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.surfaceLight,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: _selectedNumber != null ? 4 : 0,
              ),
              child: Text(
                _selectedNumber != null 
                    ? 'THROW ${_getMultiplierPrefix()}$_selectedNumber'
                    : 'SELECT SCORE',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _getMultiplierPrefix() {
    switch (_selectedMultiplier) {
      case ScoreMultiplier.single: return '';
      case ScoreMultiplier.double: return 'D';
      case ScoreMultiplier.triple: return 'T';
    }
  }

  Widget _buildMultiplierButton(String label, ScoreMultiplier multiplier, Color color) {
    final isSelected = _selectedMultiplier == multiplier;
    
    return GestureDetector(
      onTap: () {
        HapticService.lightImpact();
        setState(() {
          _selectedMultiplier = multiplier;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.black : AppTheme.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildNumberGrid() {
    // Standard dartboard order + Bull
    final numbers = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5, 25, 0];
    
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6, // Wider grid for easy access
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.1,
      ),
      itemCount: numbers.length,
      itemBuilder: (context, index) {
        final number = numbers[index];
        final isSelected = _selectedNumber == number;
        final isBull = number == 25;
        final isMiss = number == 0;
        
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticService.lightImpact();
              setState(() {
                _selectedNumber = number;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 100),
              decoration: BoxDecoration(
                color: isSelected 
                    ? AppTheme.primary 
                    : isBull 
                        ? AppTheme.error.withValues(alpha: 0.2)
                        : AppTheme.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected 
                      ? AppTheme.primary 
                      : isBull 
                          ? AppTheme.error.withValues(alpha: 0.5)
                          : AppTheme.surfaceLight.withValues(alpha: 0.3),
                ),
              ),
              child: Center(
                child: isBull 
                  ? const Icon(Icons.radio_button_checked, size: 20, color: AppTheme.error)
                  : isMiss
                      ? const Text('MISS', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary))
                      : Text(
                          '$number',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 18,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
              ),
            ),
          ),
        );
      },
    );
  }
}

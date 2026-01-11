import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/socket_service.dart';
import '../../utils/haptic_service.dart';

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
        
        debugPrint('🎮 GameScreen postFrameCallback - auth.currentUser: ${auth.currentUser?.id}');
        
        if (auth.currentUser != null) {
          game.initGame(widget.matchId, auth.currentUser!.id, widget.opponentId);
        } else {
          debugPrint('❌ GameScreen - currentUser is null!');
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
    debugPrint('🎮 GameScreen build called');
    
    try {
      debugPrint('🎮 Step 1: Getting GameProvider...');
      final game = context.watch<GameProvider>();
      debugPrint('🎮 Step 2: GameProvider obtained');
      
      debugPrint('🎮 Step 3: Getting AuthProvider...');
      final auth = context.watch<AuthProvider>();
      debugPrint('🎮 Step 4: AuthProvider obtained');
      
      debugPrint('🎮 Step 5: Accessing game.matchId...');
      final matchId = game.matchId;
      debugPrint('🎮 Step 6: matchId = $matchId');
      
      debugPrint('🎮 Step 7: Accessing game.gameStarted...');
      final gameStarted = game.gameStarted;
      debugPrint('🎮 Step 8: gameStarted = $gameStarted');

      // Show loading if game not initialized or started
      if (matchId == null || !gameStarted) {
        debugPrint('🎮 Step 9: Showing loading screen (matchId=$matchId, gameStarted=$gameStarted)');
        return Scaffold(
          appBar: AppBar(
            title: const Text('Game'),
          ),
          body: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Color(0xFF00E5FF)),
                SizedBox(height: 16),
                Text('Waiting for game to start...'),
              ],
            ),
          ),
        );
      }

      debugPrint('🎮 Step 10: Checking if game ended...');
      final gameEnded = game.gameEnded;
      debugPrint('🎮 Step 11: gameEnded = $gameEnded');
      
      if (gameEnded) {
        debugPrint('🎮 Step 12: Game has ended, showing game over screen');
        final winnerId = game.winnerId;
        final currentUserId = auth.currentUser?.id;
        final didWin = winnerId == currentUserId;
        debugPrint('🏁 Game ended - winnerId: $winnerId, currentUserId: $currentUserId');
        return Scaffold(
        appBar: AppBar(
          title: const Text('Game Over'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                didWin ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                color: didWin ? const Color(0xFFFFD700) : const Color(0xFFFF5252),
                size: 100,
              ),
              const SizedBox(height: 24),
              Text(
                didWin ? 'YOU WIN!' : 'YOU LOSE',
                style: TextStyle(
                  color: didWin ? const Color(0xFFFFD700) : const Color(0xFFFF5252),
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: () {
                  HapticService.mediumImpact();
                  debugPrint('🏠 Back to home pressed from game over screen');
                  Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                ),
                child: const Text(
                  'BACK TO HOME',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      );
    }

    debugPrint('🎮 Step 13: Rendering main game UI');
    debugPrint('🎮 Step 14: Getting dartsThrown...');
    final dartsThrown = game.dartsThrown;
    debugPrint('🎮 Step 15: dartsThrown = $dartsThrown');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Game'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            debugPrint('⬅️ Back button pressed - navigating home');
            Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
          },
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                'Dart ${dartsThrown + 1}/3',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00E5FF),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildOpponentSection(game),
          _buildTurnIndicator(game),
          _buildPlayerSection(game),
          const SizedBox(height: 16),
          _buildCurrentRoundDisplay(game),
          const SizedBox(height: 16),
          Expanded(
            child: _buildScoreInput(game),
          ),
        ],
      ),
    );
    } catch (e, stackTrace) {
      debugPrint('❌ GameScreen build error: $e');
      debugPrint('Stack trace: $stackTrace');
      
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              Text('Error: $e', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildOpponentSection(GameProvider game) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A1A1A), Color(0xFF0A0A0A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          const Text(
            'OPPONENT',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${game.opponentScore}',
            style: TextStyle(
              color: !game.isMyTurn ? const Color(0xFF00E5FF) : Colors.white,
              fontSize: 64,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnIndicator(GameProvider game) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: game.isMyTurn 
          ? const Color(0xFF00E5FF).withValues(alpha: 0.2)
          : const Color(0xFFFF5252).withValues(alpha: 0.2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            game.isMyTurn ? Icons.arrow_downward : Icons.arrow_upward,
            color: game.isMyTurn ? const Color(0xFF00E5FF) : const Color(0xFFFF5252),
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            game.isMyTurn ? 'YOUR TURN' : 'OPPONENT\'S TURN',
            style: TextStyle(
              color: game.isMyTurn ? const Color(0xFF00E5FF) : const Color(0xFFFF5252),
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerSection(GameProvider game) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0A0A0A), Color(0xFF1A1A1A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          Text(
            '${game.myScore}',
            style: TextStyle(
              color: game.isMyTurn ? const Color(0xFF00E5FF) : Colors.white,
              fontSize: 64,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'YOU',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              letterSpacing: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentRoundDisplay(GameProvider game) {
    final throws = game.currentRoundThrows;
    
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00E5FF)),
      ),
      child: Column(
        children: [
          const Text(
            'Current Round',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(3, (index) {
              final hasThrow = index < throws.length;
              return Container(
                width: 80,
                height: 60,
                decoration: BoxDecoration(
                  color: hasThrow 
                      ? const Color(0xFF00E5FF).withValues(alpha: 0.2)
                      : const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: hasThrow ? const Color(0xFF00E5FF) : Colors.white24,
                  ),
                ),
                child: Center(
                  child: Text(
                    hasThrow ? throws[index] : 'Dart ${index + 1}',
                    style: TextStyle(
                      color: hasThrow ? const Color(0xFF00E5FF) : Colors.white38,
                      fontSize: hasThrow ? 20 : 14,
                      fontWeight: hasThrow ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }),
          ),
          if (throws.length == 3) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () => _confirmRound(game),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'CONFIRM ROUND - NEXT TURN',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _confirmRound(GameProvider game) {
    HapticService.heavyImpact();
    // Emit event to backend to complete the round and switch turns
    debugPrint('🔄 Confirming round completion');
    final auth = context.read<AuthProvider>();
    SocketService.emit('confirm_round', {
      'matchId': game.matchId,
      'playerId': auth.currentUser?.id,
    });
  }

  Widget _buildScoreInput(GameProvider game) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildMultiplierSelector(),
          const SizedBox(height: 24),
          _buildNumberGrid(),
          const SizedBox(height: 24),
          _buildThrowButton(game),
        ],
      ),
    );
  }

  Widget _buildMultiplierSelector() {
    return Row(
      children: [
        Expanded(
          child: _buildMultiplierButton(
            'Single',
            ScoreMultiplier.single,
            const Color(0xFF00E5FF),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMultiplierButton(
            'Double',
            ScoreMultiplier.double,
            const Color(0xFF4CAF50),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMultiplierButton(
            'Triple',
            ScoreMultiplier.triple,
            const Color(0xFFFF9800),
          ),
        ),
      ],
    );
  }

  Widget _buildMultiplierButton(String label, ScoreMultiplier multiplier, Color color) {
    final isSelected = _selectedMultiplier == multiplier;
    
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: isSelected ? color.withValues(alpha: 0.3) : const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isSelected ? color : Colors.white24,
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedMultiplier = multiplier;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white70,
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberGrid() {
    final numbers = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5, 25];
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1,
      ),
      itemCount: numbers.length,
      itemBuilder: (context, index) {
        final number = numbers[index];
        final isSelected = _selectedNumber == number;
        final isBullseye = number == 25;
        
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected 
                ? const Color(0xFF00E5FF).withValues(alpha: 0.3)
                : const Color(0xFF1A1A1A),
            border: Border.all(
              color: isSelected 
                  ? const Color(0xFF00E5FF)
                  : isBullseye 
                      ? const Color(0xFFFF1744)
                      : Colors.white24,
              width: 2,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedNumber = number;
                });
              },
              customBorder: const CircleBorder(),
              child: Center(
                child: Text(
                  isBullseye ? 'Bull' : '$number',
                  style: TextStyle(
                    color: isSelected 
                        ? const Color(0xFF00E5FF)
                        : isBullseye 
                            ? const Color(0xFFFF1744)
                            : Colors.white,
                    fontSize: isBullseye ? 12 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildThrowButton(GameProvider game) {
    final canThrow = game.isMyTurn && _selectedNumber != null;
    
    String getMultiplierPrefix() {
      switch (_selectedMultiplier) {
        case ScoreMultiplier.single:
          return 'S';
        case ScoreMultiplier.double:
          return 'D';
        case ScoreMultiplier.triple:
          return 'T';
      }
    }

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: canThrow
            ? () {
                HapticService.mediumImpact();
                game.throwDart(
                  baseScore: _selectedNumber!,
                  multiplier: _selectedMultiplier,
                );
                setState(() {
                  _selectedNumber = null;
                });
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00E5FF),
          foregroundColor: Colors.black,
          disabledBackgroundColor: const Color(0xFF1A1A1A),
          disabledForegroundColor: Colors.white24,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          canThrow 
              ? 'THROW ${getMultiplierPrefix()}$_selectedNumber'
              : !game.isMyTurn
                  ? 'WAIT FOR YOUR TURN'
                  : game.dartsThrown >= 3 || game.currentRoundThrows.length >= 3
                      ? 'ROUND COMPLETE'
                      : 'SELECT A NUMBER',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

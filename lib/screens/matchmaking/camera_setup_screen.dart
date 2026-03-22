import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import '../../providers/matchmaking_provider.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/socket_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_navigator.dart';
import '../../l10n/app_localizations.dart';
import '../shared/camera_setup_mixin.dart';
import 'matchmaking_screen.dart';
import '../game/game_screen.dart';

class CameraSetupScreen extends StatefulWidget {
  final String? rejoinMatchId;
  final String? rejoinOpponentId;
  final String? rejoinOpponentUsername;

  const CameraSetupScreen({
    super.key,
    this.rejoinMatchId,
    this.rejoinOpponentId,
    this.rejoinOpponentUsername,
  });

  bool get isRejoin => rejoinMatchId != null;

  @override
  State<CameraSetupScreen> createState() => _CameraSetupScreenState();
}

class _CameraSetupScreenState extends State<CameraSetupScreen>
    with WidgetsBindingObserver, CameraSetupMixin {
  @override
  CameraSetupConfig get cameraSetupConfig => const CameraSetupConfig(
        requireMicrophone: true,
        enableAiDetection: true,
        restoreSavedZoom: false,
        enableGestureZoom: true,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) initializeCamera();
    });
    initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    handleAppLifecycleState(state);
  }

  Future<void> _joinQueue() async {
    if (!cameraReady || !permissionsGranted) return;

    HapticService.mediumImpact();
    await prepareForNavigation();
    if (!mounted) return;

    final matchmaking = context.read<MatchmakingProvider>();
    final game = context.read<GameProvider>();
    final user = context.read<AuthProvider>().currentUser;

    if (user?.id != null) {
      matchmaking.setGameProvider(game);
      await matchmaking.joinQueue(user!.id);

      if (mounted) {
        AppNavigator.replaceWith(context, const MatchmakingScreen());
      }
    }
  }

  Future<void> _rejoinMatch() async {
    if (!cameraReady || !permissionsGranted) return;

    HapticService.mediumImpact();
    await prepareForNavigation();
    if (!mounted) return;

    final game = context.read<GameProvider>();
    final user = context.read<AuthProvider>().currentUser;
    if (user?.id == null) return;

    final matchId = widget.rejoinMatchId!;
    final opponentId = widget.rejoinOpponentId!;
    final opponentUsername = widget.rejoinOpponentUsername ?? 'Unknown';

    await SocketService.ensureConnected();
    game.ensureListenersSetup();
    game.initGame(matchId, user!.id, opponentId);
    game.reconnectToMatch();

    if (mounted) {
      AppNavigator.replaceWith(
        context,
        GameScreen(
          matchId: matchId,
          opponentId: opponentId,
          opponentUsername: opponentUsername,
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    disposeCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: buildCameraAppBar(l10n.cameraSetup),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: isLoading
                  ? buildLoadingView()
                  : errorMessage != null
                      ? buildErrorView()
                      : _buildCameraPreview(),
            ),
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final l10n = AppLocalizations.of(context);
    if (cameraController == null || !cameraController!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary, width: 2),
      ),
      child: GestureDetector(
        onScaleStart: onScaleStart,
        onScaleUpdate: onScaleUpdate,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              Center(child: CameraPreview(cameraController!)),
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.cameraReady,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      if (aiModelLoaded) ...[
                        const SizedBox(height: 10),
                        buildAiStatusOverlay(l10n),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: buildZoomControls(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSection() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(
              color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                buildInfoRow(Icons.videocam, l10n.cameraOnDuringMatch),
                const SizedBox(height: 8),
                buildInfoRow(Icons.mic_off, l10n.micOffByDefault),
                const SizedBox(height: 8),
                buildInfoRow(
                    Icons.my_location, l10n.makeSureDartboardVisible),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canPlay
                  ? (widget.isRejoin ? _rejoinMatch : _joinQueue)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    canPlay ? AppTheme.primary : AppTheme.surfaceLight,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: canPlay ? 4 : 0,
              ),
              child: Text(
                getPlayButtonLabel(l10n),
                style: TextStyle(
                  color: canPlay ? Colors.white : AppTheme.textSecondary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

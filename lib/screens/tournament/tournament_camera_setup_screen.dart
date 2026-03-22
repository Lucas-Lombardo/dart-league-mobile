import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_navigator.dart';
import '../shared/camera_setup_mixin.dart';
import 'tournament_ready_screen.dart';

class TournamentCameraSetupScreen extends StatefulWidget {
  final String matchId;
  final String tournamentId;
  final String tournamentName;
  final String roundName;
  final String opponentUsername;
  final String opponentId;
  final String player1Id;
  final String player2Id;
  final int bestOf;
  final DateTime? inviteSentAt;

  const TournamentCameraSetupScreen({
    super.key,
    required this.matchId,
    required this.tournamentId,
    required this.tournamentName,
    required this.roundName,
    required this.opponentUsername,
    required this.opponentId,
    required this.player1Id,
    required this.player2Id,
    required this.bestOf,
    this.inviteSentAt,
  });

  @override
  State<TournamentCameraSetupScreen> createState() =>
      _TournamentCameraSetupScreenState();
}

class _TournamentCameraSetupScreenState
    extends State<TournamentCameraSetupScreen> with CameraSetupMixin {
  bool _readyingSent = false;

  @override
  CameraSetupConfig get cameraSetupConfig => const CameraSetupConfig(
        requireMicrophone: true,
        enableAiDetection: false,
        restoreSavedZoom: false,
        enableGestureZoom: false,
      );

  @override
  void initState() {
    super.initState();
    initializeCamera();
    initCamera();
  }

  Future<void> _onReadyPressed() async {
    if (!cameraReady || !permissionsGranted || _readyingSent) return;

    setState(() => _readyingSent = true);
    HapticService.mediumImpact();
    await prepareForNavigation();
    if (!mounted) return;

    AppNavigator.replaceWith(
      context,
      TournamentReadyScreen(
        matchId: widget.matchId,
        tournamentId: widget.tournamentId,
        tournamentName: widget.tournamentName,
        roundName: widget.roundName,
        opponentUsername: widget.opponentUsername,
        opponentId: widget.opponentId,
        player1Id: widget.player1Id,
        player2Id: widget.player2Id,
        bestOf: widget.bestOf,
      ),
    );
  }

  @override
  void dispose() {
    disposeCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: buildCameraAppBar(l10n.cameraSetupTitle),
      body: SafeArea(
        child: Column(
          children: [
            _buildMatchInfoBar(),
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

  Widget _buildMatchInfoBar() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        border: Border(
          bottom:
              BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.roundName.replaceAll('_', ' ').toUpperCase(),
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.tournamentName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'vs ${widget.opponentUsername} • ${l10n.bestOf} ${widget.bestOf}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
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
                padding: const EdgeInsets.all(16),
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
                          width: 12,
                          height: 12,
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
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            color: AppTheme.primary, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.positionDeviceInstruction,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
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
    );
  }

  Widget _buildBottomSection() {
    final l10n = AppLocalizations.of(context);
    final isReady = permissionsGranted && cameraReady;
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
                buildInfoRow(Icons.videocam, l10n.cameraOnDuringMatchInfo),
                const SizedBox(height: 8),
                buildInfoRow(Icons.mic_off, l10n.micOffByDefault),
                const SizedBox(height: 8),
                buildInfoRow(
                    Icons.my_location, l10n.makeSureDartboardVisibleInfo),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  isReady && !_readyingSent ? _onReadyPressed : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isReady ? AppTheme.success : AppTheme.surfaceLight,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: isReady ? 4 : 0,
              ),
              child: Text(
                isReady ? l10n.ready : l10n.cameraRequiredButton,
                style: TextStyle(
                  color: isReady ? Colors.white : AppTheme.textSecondary,
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

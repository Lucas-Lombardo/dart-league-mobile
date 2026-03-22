import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_navigator.dart';
import '../shared/camera_setup_mixin.dart';
import 'placement_game_screen.dart';

class PlacementCameraSetupScreen extends StatefulWidget {
  const PlacementCameraSetupScreen({super.key});

  @override
  State<PlacementCameraSetupScreen> createState() =>
      _PlacementCameraSetupScreenState();
}

class _PlacementCameraSetupScreenState
    extends State<PlacementCameraSetupScreen>
    with WidgetsBindingObserver, CameraSetupMixin {
  @override
  CameraSetupConfig get cameraSetupConfig => const CameraSetupConfig(
        requireMicrophone: false,
        enableAiDetection: true,
        restoreSavedZoom: true,
        enableGestureZoom: false,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    initializeCamera();
    initCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    handleAppLifecycleState(state);
  }

  Future<void> _onPlayPressed() async {
    if (!canPlay) return;
    HapticService.mediumImpact();
    await prepareForNavigation();
    if (!mounted) return;
    final result = await AppNavigator.toScreen<Map<String, dynamic>>(
      context,
      const PlacementGameScreen(),
    );
    if (mounted) {
      AppNavigator.back(context, result);
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
      appBar: buildCameraAppBar(l10n.cameraSetupTitle),
      body: SafeArea(
        child: Column(
          children: [
            _buildMatchInfoBar(l10n),
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

  Widget _buildMatchInfoBar(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.1),
        border: Border(
            bottom:
                BorderSide(color: AppTheme.accent.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy, color: AppTheme.accent, size: 13),
                const SizedBox(width: 4),
                Text(l10n.placementBadge,
                    style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.positionPhoneInstruction,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 13),
              overflow: TextOverflow.ellipsis,
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
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: cameraController!.value.previewSize!.height,
                  height: cameraController!.value.previewSize!.width,
                  child: CameraPreview(cameraController!),
                ),
              ),
            ),
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
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(l10n.cameraReady,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline,
                            color: AppTheme.primary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.positionDeviceInstruction,
                            style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 13),
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
                color: AppTheme.surfaceLight.withValues(alpha: 0.5))),
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
                buildInfoRow(Icons.smart_toy, l10n.aiWillScoreDartsInfo),
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
              onPressed: canPlay ? _onPlayPressed : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    canPlay ? AppTheme.primary : AppTheme.surfaceLight,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
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

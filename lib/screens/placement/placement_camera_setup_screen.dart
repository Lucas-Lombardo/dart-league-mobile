import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_navigator.dart';
import '../shared/camera_setup_mixin.dart';
import 'placement_game_screen.dart';

class PlacementCameraSetupScreen extends StatefulWidget {
  /// Screen pushed once the camera is validated. Defaults to the X01
  /// [PlacementGameScreen]; the cricket bot flow injects its own screen.
  final Widget Function()? gameScreenBuilder;

  const PlacementCameraSetupScreen({super.key, this.gameScreenBuilder});

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) initializeCamera();
    });
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
      widget.gameScreenBuilder?.call() ?? const PlacementGameScreen(),
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
        child: OrientationBuilder(
          builder: (context, orientation) {
            final body = isLoading
                ? buildLoadingView()
                : errorMessage != null
                    ? buildErrorView()
                    : _buildCameraPreview();
            if (orientation == Orientation.landscape) {
              return Column(
                children: [
                  _buildMatchInfoBar(l10n),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: body),
                        Expanded(
                          flex: 2,
                          child: SingleChildScrollView(
                            child: _buildBottomSection(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Column(
              children: [
                _buildMatchInfoBar(l10n),
                Expanded(child: body),
                _buildBottomSection(),
              ],
            );
          },
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

  Widget _buildCameraPreview() => buildCameraPreview();

  Widget _buildBottomSection() {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
            top: BorderSide(
                color: AppTheme.surfaceLight.withValues(alpha: 0.5))),
      ),
      child: Column(
        children: [
          // One compact line — the camera panel above is the point of this
          // screen, the chrome stays out of its way.
          buildInfoRow(Icons.videocam, l10n.cameraNeededForAiInfo),
          const SizedBox(height: 12),
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

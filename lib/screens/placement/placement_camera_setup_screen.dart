import 'dart:async';

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/progression_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/app_navigator.dart';
import '../../widgets/design_system.dart';
import '../shared/camera_setup_mixin.dart';
import 'placement_game_screen.dart';

class PlacementCameraSetupScreen extends StatefulWidget {
  /// Screen pushed once the camera is validated. Defaults to the X01
  /// [PlacementGameScreen]; the cricket bot flow injects its own screen.
  final Widget Function()? gameScreenBuilder;

  /// Runs when the player presses "Play", before the game screen: the
  /// placement flow creates (or resumes) the server match here, once the
  /// camera is ready — never at the hub, where the 7-minute idle sweep used to
  /// kill it during the tripod setup. False keeps the player on this screen
  /// with an error, the camera still live.
  final Future<bool> Function()? beforeStart;

  const PlacementCameraSetupScreen({
    super.key,
    this.gameScreenBuilder,
    this.beforeStart,
  });

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

  /// True while [PlacementCameraSetupScreen.beforeStart] is running.
  bool _starting = false;

  Future<void> _onPlayPressed() async {
    if (!canPlay || _starting) return;
    HapticService.mediumImpact();
    // Discovery quest "Set up your camera" and the first step of the first
    // 7 days (progression). Fire-and-forget.
    unawaited(ProgressionService.reportClientAction('camera_setup'));
    final before = widget.beforeStart;
    if (before != null) {
      setState(() => _starting = true);
      final ok = await before();
      if (!mounted) return;
      setState(() => _starting = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context).onboardingPlacementStartFailed),
        ));
        return;
      }
    }
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

  /// Context strip: the "Placement" pill next to the one-line instruction —
  /// flat, like every other camera screen; the preview below is the point.
  Widget _buildMatchInfoBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          DsPill(label: dsSentence(l10n.placementBadge)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.positionPhoneInstruction,
              style: AppTheme.caption,
              maxLines: 2,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          // One compact line — the camera panel above is the point of this
          // screen, the chrome stays out of its way.
          buildInfoRow(Icons.videocam_outlined, l10n.cameraNeededForAiInfo),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: canPlay && !_starting ? _onPlayPressed : null,
              child: _starting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : Text(dsSentence(getPlayButtonLabel(l10n))),
            ),
          ),
        ],
      ),
    );
  }
}

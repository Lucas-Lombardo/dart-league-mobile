import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/local_match_config.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';
import '../shared/camera_setup_mixin.dart';
import 'local_cricket_match_screen.dart';
import 'local_match_screen.dart';

/// Camera/permission gate before a local 1v1 match. Same gate the bot-training
/// flow uses (AI auto-scoring, no microphone) — just routes into
/// [LocalMatchScreen] (X01) or [LocalCricketMatchScreen].
class LocalMatchCameraSetupScreen extends StatefulWidget {
  final LocalMatchConfig config;

  const LocalMatchCameraSetupScreen({super.key, required this.config});

  @override
  State<LocalMatchCameraSetupScreen> createState() =>
      _LocalMatchCameraSetupScreenState();
}

class _LocalMatchCameraSetupScreenState
    extends State<LocalMatchCameraSetupScreen>
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
    final config = widget.config;
    await AppNavigator.toScreen<void>(
      context,
      config.isCricket
          ? LocalCricketMatchScreen(config: config)
          : LocalMatchScreen(config: config),
    );
    if (mounted) AppNavigator.back(context);
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

  /// Context strip: the "Match local" pill next to the one-line instruction —
  /// flat, like every other camera screen; the preview below is the point.
  Widget _buildMatchInfoBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          DsPill(label: dsSentence(l10n.localMatchBadge)),
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
              onPressed: canPlay ? _onPlayPressed : null,
              child: Text(dsSentence(getPlayButtonLabel(l10n))),
            ),
          ),
        ],
      ),
    );
  }
}

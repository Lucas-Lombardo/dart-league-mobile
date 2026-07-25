import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

/// Optional context banner shown under the app bar (e.g. tournament round,
/// name and opponent). Purely presentational — the screen behaves identically
/// with or without it.
class CameraSetupMatchInfo {
  final String pill;
  final String title;
  final String subtitle;

  const CameraSetupMatchInfo({
    required this.pill,
    required this.title,
    required this.subtitle,
  });
}

/// The single camera-setup screen for every online mode — ranked, friendly
/// (invite/accept), tournament — so the camera gate, AI board detection and
/// button behavior can never diverge between flows again.
class CameraSetupScreen extends StatefulWidget {
  final String? rejoinMatchId;
  final String? rejoinOpponentId;
  final String? rejoinOpponentUsername;

  /// When true, the primary button just confirms the camera/permissions are
  /// ready and pops with `true` (instead of joining the ranked queue). Used by
  /// the friendly-match flow so the inviter/invitee pass the same camera gate as
  /// ranked; the caller then sends/accepts the invite.
  final bool confirmAndPop;

  /// Optional override for the primary button label (e.g. "Invite", "Join").
  final String? actionLabel;

  /// Context banner under the app bar (tournament round / opponent).
  final CameraSetupMatchInfo? matchInfo;

  /// Pre-navigation gate, run on tap BEFORE the camera is torn down, with the
  /// button showing a spinner. Return false to stay on the screen (the camera
  /// keeps running and the button re-enables) — e.g. after surfacing a
  /// connection error. Return true to proceed.
  final Future<bool> Function(BuildContext context)? onValidate;

  /// Custom navigation, run after [onValidate] passed and the camera was
  /// released. Takes precedence over [confirmAndPop]/rejoin/queue. Return
  /// true after navigating away; false to stay (the button re-enables).
  final Future<bool> Function(BuildContext context)? onConfirm;

  const CameraSetupScreen({
    super.key,
    this.rejoinMatchId,
    this.rejoinOpponentId,
    this.rejoinOpponentUsername,
    this.confirmAndPop = false,
    this.actionLabel,
    this.matchInfo,
    this.onValidate,
    this.onConfirm,
  });

  bool get isRejoin => rejoinMatchId != null;

  @override
  State<CameraSetupScreen> createState() => _CameraSetupScreenState();
}

class _CameraSetupScreenState extends State<CameraSetupScreen>
    with WidgetsBindingObserver, CameraSetupMixin {
  bool _busy = false;

  @override
  CameraSetupConfig get cameraSetupConfig => const CameraSetupConfig(
        requireMicrophone: true,
        enableAiDetection: true,
        restoreSavedZoom: true,
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

  /// Single entry point for the primary button: guard, validate while the
  /// camera is still alive, then tear the camera down and hand off.
  Future<void> _onActionPressed() async {
    if (!canPlay || _busy) return;
    setState(() => _busy = true);
    HapticService.mediumImpact();

    if (widget.onValidate != null) {
      final ok = await widget.onValidate!(context);
      if (!mounted) return;
      if (!ok) {
        setState(() => _busy = false);
        return;
      }
    }

    // Tracked explicitly rather than via `mounted`: during a push/pop
    // transition this State is still mounted, and re-enabling the button
    // there would reopen the double-tap window the busy flag closes.
    var navigated = false;
    try {
      await prepareForNavigation();
      if (!mounted) return;

      if (widget.onConfirm != null) {
        navigated = await widget.onConfirm!(context);
      } else if (widget.confirmAndPop) {
        // Pop with `true` so the caller knows the camera gate was cleared and
        // can send/accept the friendly-match invite.
        Navigator.of(context).pop(true);
        navigated = true;
      } else if (widget.isRejoin) {
        navigated = await _rejoinMatch();
      } else {
        navigated = await _joinQueue();
      }
    } finally {
      // Only fires when the hand-off bailed out (offline rejoin, missing
      // user, …) or threw, and the user is still here: give the button back
      // instead of leaving a dead spinner.
      if (!navigated && mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _joinQueue() async {
    final matchmaking = context.read<MatchmakingProvider>();
    final game = context.read<GameProvider>();
    final user = context.read<AuthProvider>().currentUser;
    if (user?.id == null) return false;

    matchmaking.setGameProvider(game);
    await matchmaking.joinQueue(user!.id);

    if (!mounted) return true;
    AppNavigator.replaceWith(context, const MatchmakingScreen());
    return true;
  }

  Future<bool> _rejoinMatch() async {
    final game = context.read<GameProvider>();
    final user = context.read<AuthProvider>().currentUser;
    if (user?.id == null) return false;

    final matchId = widget.rejoinMatchId!;
    final opponentId = widget.rejoinOpponentId!;
    final opponentUsername = widget.rejoinOpponentUsername ?? 'Unknown';

    await SocketService.ensureConnected();
    game.ensureListenersSetup();
    game.initGame(matchId, user!.id, opponentId);
    game.reconnectToMatch();

    if (!mounted) return true;
    AppNavigator.replaceWith(
      context,
      GameScreen(
        matchId: matchId,
        opponentId: opponentId,
        opponentUsername: opponentUsername,
      ),
    );
    return true;
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
                  if (widget.matchInfo != null) _buildMatchInfoBar(),
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
                if (widget.matchInfo != null) _buildMatchInfoBar(),
                Expanded(child: body),
                _buildBottomSection(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMatchInfoBar() {
    final info = widget.matchInfo!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)),
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
              info.pill,
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
                  info.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  info.subtitle,
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

  Widget _buildCameraPreview() => buildCameraPreview();

  Widget _buildBottomSection() {
    final l10n = AppLocalizations.of(context);
    // The caller's action label only once the gate is fully open — until then
    // the progressive status ("loading AI", "scanning…") tells the user what
    // the screen is waiting for, identically in every mode.
    final label =
        canPlay ? (widget.actionLabel ?? getPlayButtonLabel(l10n)) : getPlayButtonLabel(l10n);
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
              onPressed: canPlay && !_busy ? _onActionPressed : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    canPlay ? AppTheme.primary : AppTheme.surfaceLight,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: canPlay ? 4 : 0,
              ),
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      label,
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

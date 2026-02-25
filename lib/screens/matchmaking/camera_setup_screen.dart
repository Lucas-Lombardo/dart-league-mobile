import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../providers/matchmaking_provider.dart';
import '../../providers/game_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/socket_service.dart';
import '../../services/detection_isolate_stub.dart'
    if (dart.library.io) '../../services/detection_isolate.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/storage_service.dart';
import '../../l10n/app_localizations.dart';
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

class _CameraSetupScreenState extends State<CameraSetupScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isLoading = true;
  bool _permissionsGranted = false;
  bool _cameraReady = false;
  String? _errorMessage;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  // AI dartboard detection
  DetectionIsolate? _detectionIsolate;
  bool _aiModelLoaded = false;
  String? _aiHint;
  bool _boardDetected = false;
  Timer? _aiCaptureTimer;
  bool _aiCapturing = false;
  bool _aiAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    if (!kIsWeb) _initAiDetection();
  }

  Future<void> _initAiDetection() async {
    try {
      _detectionIsolate = DetectionIsolate();
      await _detectionIsolate!.start();
      if (mounted) {
        setState(() => _aiModelLoaded = true);
        _startAiCapture();
      }
    } catch (_) {
      // AI not available — queue is still unlocked
    }
  }

  void _startAiCapture() {
    if (_aiCapturing || !_aiModelLoaded) return;
    _aiCapturing = true;
    _aiCaptureTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (mounted && _cameraReady && _cameraController != null) {
        _runAiCapture();
      }
    });
  }

  Future<void> _runAiCapture() async {
    if (_aiAnalyzing) return;
    if (_detectionIsolate == null || !_aiModelLoaded) return;
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    _aiAnalyzing = true;
    try {
      final xFile = await _cameraController!.takePicture();
      if (!mounted) { try { await File(xFile.path).delete(); } catch (_) {} return; }
      final result = await _detectionIsolate!.analyze(xFile.path);
      try { await File(xFile.path).delete(); } catch (_) {}
      if (!mounted) return;
      final calibs = result.calibrationPoints;
      String? hint;
      bool detected = false;
      if (calibs.length < 4) {
        hint = calibs.isEmpty ? 'Dartboard not detected' : 'Board not fully visible';
        detected = false;
      } else {
        double minX = 1, maxX = 0, minY = 1, maxY = 0;
        for (final c in calibs) {
          if (c.x < minX) minX = c.x;
          if (c.x > maxX) maxX = c.x;
          if (c.y < minY) minY = c.y;
          if (c.y > maxY) maxY = c.y;
        }
        final spread = (maxX - minX) > (maxY - minY) ? (maxX - minX) : (maxY - minY);
        if (spread < 0.50) {
          hint = 'Zoom in — board too far';
          detected = false;
        } else if (spread > 0.85) {
          hint = 'Zoom out — board too close';
          detected = false;
        } else {
          hint = null;
          detected = true;
        }
      }
      setState(() {
        _aiHint = hint;
        _boardDetected = detected;
      });
    } catch (_) {
      // ignore capture errors
    } finally {
      _aiAnalyzing = false;
    }
  }

  bool get _canPlay {
    if (!_permissionsGranted || !_cameraReady) return false;
    if (_aiModelLoaded && !_boardDetected) return false;
    return true;
  }

  String get _playButtonLabel {
    if (!_permissionsGranted || !_cameraReady) return 'CAMERA REQUIRED';
    if (_aiModelLoaded && !_boardDetected) {
      return _aiHint != null ? _aiHint!.toUpperCase() : 'SCANNING...';
    }
    return 'PLAY';
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Request permissions
      final statuses = await [
        Permission.camera,
        Permission.microphone,
      ].request();

      final cameraGranted = statuses[Permission.camera]?.isGranted ?? false;
      final micGranted = statuses[Permission.microphone]?.isGranted ?? false;

      if (!cameraGranted || !micGranted) {
        setState(() {
          _isLoading = false;
          _permissionsGranted = false;
          if (!cameraGranted && !micGranted) {
            _errorMessage = 'Camera and microphone permissions are required to join a match';
          } else if (!cameraGranted) {
            _errorMessage = 'Camera permission is required to join a match';
          } else {
            _errorMessage = 'Microphone permission is required to join a match';
          }
        });
        return;
      }

      _permissionsGranted = true;

      // Get available cameras
      _cameras = await availableCameras();
      
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No cameras found on this device';
        });
        return;
      }

      // Find back camera
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      // Initialize camera controller
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      try {
        _minZoom = await _cameraController!.getMinZoomLevel();
        _maxZoom = await _cameraController!.getMaxZoomLevel();
        _currentZoom = _minZoom;
      } catch (_) {
        _minZoom = 1.0;
        _maxZoom = 1.0;
        _currentZoom = 1.0;
      }

      if (mounted) {
        setState(() {
          _cameraReady = true;
          _isLoading = false;
        });
        if (_aiModelLoaded) _startAiCapture();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _cameraReady = false;
        _errorMessage = 'Failed to initialize camera: ${e.toString()}';
      });
    }
  }

  Future<void> _joinQueue() async {
    if (!_cameraReady || !_permissionsGranted) {
      return;
    }

    HapticService.mediumImpact();
    await StorageService.saveCameraZoom(_currentZoom);
    
    // Dispose camera controller
    await _cameraController?.dispose();

    if (!mounted) return;

    final matchmaking = context.read<MatchmakingProvider>();
    final game = context.read<GameProvider>();
    final user = context.read<AuthProvider>().currentUser;

    if (user?.id != null) {
      matchmaking.setGameProvider(game);
      await matchmaking.joinQueue(user!.id);

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => const MatchmakingScreen(),
          ),
        );
      }
    }
  }

  Future<void> _rejoinMatch() async {
    if (!_cameraReady || !_permissionsGranted) return;

    HapticService.mediumImpact();
    await StorageService.saveCameraZoom(_currentZoom);

    await _cameraController?.dispose();
    if (!mounted) return;

    final game = context.read<GameProvider>();
    final user = context.read<AuthProvider>().currentUser;
    if (user?.id == null) return;

    final matchId = widget.rejoinMatchId!;
    final opponentId = widget.rejoinOpponentId!;
    final opponentUsername = widget.rejoinOpponentUsername ?? 'Unknown';

    // Connect socket and set up game listeners
    await SocketService.ensureConnected();
    game.ensureListenersSetup();
    game.initGame(matchId, user!.id, opponentId);

    // Explicitly tell server we're reconnecting to this match
    game.reconnectToMatch();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => GameScreen(
            matchId: matchId,
            opponentId: opponentId,
            opponentUsername: opponentUsername,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _aiCaptureTimer?.cancel();
    _aiCaptureTimer = null;
    _aiCapturing = false;
    _detectionIsolate?.dispose();
    _detectionIsolate = null;
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            HapticService.lightImpact();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          AppLocalizations.of(context).cameraSetup,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _isLoading
                  ? _buildLoadingView()
                  : _errorMessage != null
                      ? _buildErrorView()
                      : _buildCameraPreview(),
            ),
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            color: AppTheme.primary,
            strokeWidth: 3,
          ),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context).initializingCamera,
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.error, width: 2),
              ),
              child: const Icon(
                Icons.videocam_off,
                color: AppTheme.error,
                size: 80,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              AppLocalizations.of(context).cameraRequired,
              style: AppTheme.displayMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'Unknown error',
              style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.surfaceLight),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.info_outline, color: AppTheme.primary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLocalizations.of(context).cannotJoinWithoutCamera,
                          style: AppTheme.bodyLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context).enablePermissionsInSettings,
                    style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _initializeCamera,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context).tryAgain,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
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
            // Camera preview
            Center(
              child: CameraPreview(_cameraController!),
            ),
            
            // Overlay instructions
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppTheme.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context).connected,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: AppTheme.primary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context).positionDartboard,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    // AI detection status
                    if (_aiModelLoaded) ...[
                      const SizedBox(height: 10),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: (_aiHint == null && _boardDetected)
                              ? AppTheme.success.withValues(alpha: 0.2)
                              : (_aiHint != null)
                                  ? AppTheme.error.withValues(alpha: 0.2)
                                  : AppTheme.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (_aiHint == null && _boardDetected)
                                ? AppTheme.success
                                : (_aiHint != null)
                                    ? AppTheme.error
                                    : AppTheme.accent,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              (_aiHint == null && _boardDetected)
                                  ? Icons.check_circle
                                  : (_aiHint != null)
                                      ? Icons.warning_rounded
                                      : Icons.smart_toy_outlined,
                              color: (_aiHint == null && _boardDetected)
                                  ? AppTheme.success
                                  : (_aiHint != null)
                                      ? AppTheme.error
                                      : AppTheme.accent,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                (_aiHint == null && _boardDetected)
                                    ? 'Dartboard detected — good position'
                                    : _aiHint ?? 'Scanning for dartboard...',
                                style: TextStyle(
                                  color: (_aiHint == null && _boardDetected)
                                      ? AppTheme.success
                                      : (_aiHint != null)
                                          ? AppTheme.error
                                          : AppTheme.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            
            // Zoom controls
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildZoomButton(Icons.add, _zoomIn),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${_currentZoom.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(color: Colors.black, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                  _buildZoomButton(Icons.remove, _zoomOut),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                _buildInfoRow(Icons.videocam, AppLocalizations.of(context).cameraOnDuringMatch),
                const SizedBox(height: 8),
                _buildInfoRow(Icons.mic_off, AppLocalizations.of(context).micOffByDefault),
                const SizedBox(height: 8),
                _buildInfoRow(Icons.my_location, AppLocalizations.of(context).makeSureDartboardVisible),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canPlay ? (widget.isRejoin ? _rejoinMatch : _joinQueue) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _canPlay ? AppTheme.primary : AppTheme.surfaceLight,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: _canPlay ? 4 : 0,
              ),
              child: Text(
                _playButtonLabel,
                style: TextStyle(
                  color: _canPlay ? Colors.white : AppTheme.textSecondary,
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

  Future<void> _zoomIn() async {
    final newZoom = (_currentZoom + 0.1).clamp(_minZoom, _maxZoom);
    await _cameraController?.setZoomLevel(newZoom);
    setState(() => _currentZoom = newZoom);
  }

  Future<void> _zoomOut() async {
    final newZoom = (_currentZoom - 0.1).clamp(_minZoom, _maxZoom);
    await _cameraController?.setZoomLevel(newZoom);
    setState(() => _currentZoom = newZoom);
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onPressed) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.textSecondary, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

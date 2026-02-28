import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../l10n/app_localizations.dart';
import '../../services/detection_isolate_stub.dart'
    if (dart.library.io) '../../services/detection_isolate.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/storage_service.dart';
import 'placement_game_screen.dart';

class PlacementCameraSetupScreen extends StatefulWidget {
  const PlacementCameraSetupScreen({super.key});

  @override
  State<PlacementCameraSetupScreen> createState() => _PlacementCameraSetupScreenState();
}

class _PlacementCameraSetupScreenState extends State<PlacementCameraSetupScreen> {
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
    } catch (_) {}
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
    final l10n = AppLocalizations.of(context);
    if (_aiAnalyzing || _detectionIsolate == null || !_aiModelLoaded) return;
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
        hint = calibs.isEmpty ? l10n.dartboardNotDetected : l10n.boardNotFullyVisible;
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
          hint = l10n.zoomInBoardTooFar;
        } else if (spread > 0.85) {
          hint = l10n.zoomOutBoardTooClose;
        } else {
          hint = null;
          detected = true;
        }
      }
      setState(() { _aiHint = hint; _boardDetected = detected; });
    } catch (_) {
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
    final l10n = AppLocalizations.of(context);
    if (!_permissionsGranted || !_cameraReady) return l10n.cameraRequiredButton;
    if (_aiModelLoaded && !_boardDetected) {
      return _aiHint != null ? _aiHint!.toUpperCase() : l10n.scanningButton;
    }
    return l10n.play.toUpperCase();
  }

  Future<void> _initializeCamera() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    
    if (kIsWeb) {
      setState(() {
        _isLoading = false;
        _permissionsGranted = true;
        _cameraReady = true;
      });
      return;
    }
    
    final l10n = AppLocalizations.of(context);
    
    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() {
          _isLoading = false;
          _permissionsGranted = false;
          _errorMessage = l10n.cameraPermissionRequired;
        });
        return;
      }
      _permissionsGranted = true;

      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() { _isLoading = false; _errorMessage = l10n.noCamerasFound; });
        return;
      }

      final backCamera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(backCamera, ResolutionPreset.high, enableAudio: false);
      await _cameraController!.initialize();
      
      try {
        await _cameraController!.setFlashMode(FlashMode.off);
      } catch (e) {
        print('[Camera] Flash mode not supported: $e');
      }

      try {
        _minZoom = await _cameraController!.getMinZoomLevel();
        _maxZoom = await _cameraController!.getMaxZoomLevel();
        final savedZoom = await StorageService.getCameraZoom();
        _currentZoom = savedZoom.clamp(_minZoom, _maxZoom);
        await _cameraController!.setZoomLevel(_currentZoom);
      } catch (_) {
        _minZoom = 1.0; _maxZoom = 1.0; _currentZoom = 1.0;
      }

      if (mounted) {
        setState(() { _cameraReady = true; _isLoading = false; });
        if (_aiModelLoaded) _startAiCapture();
      }
    } catch (e) {
      setState(() { _isLoading = false; _cameraReady = false; _errorMessage = '${l10n.failedToInitializeCamera}: $e'; });
    }
  }

  Future<void> _onPlayPressed() async {
    if (!_canPlay) return;
    HapticService.mediumImpact();
    await StorageService.saveCameraZoom(_currentZoom);
    await _cameraController?.dispose();
    _cameraController = null;
    if (!mounted) return;
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (context) => const PlacementGameScreen()),
    );
    if (mounted) {
      Navigator.of(context).pop(result);
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
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () { HapticService.lightImpact(); Navigator.of(context).pop(); },
        ),
        title: Text(
          l10n.cameraSetupTitle,
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Match info bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.1),
                border: Border(bottom: BorderSide(color: AppTheme.accent.withValues(alpha: 0.3))),
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
                        Text(l10n.placementBadge, style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.positionPhoneInstruction,
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
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
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3),
          const SizedBox(height: 24),
          Text(l10n.initializingCamera, style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    final l10n = AppLocalizations.of(context);
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
              child: const Icon(Icons.videocam_off, color: AppTheme.error, size: 80),
            ),
            const SizedBox(height: 32),
            Text(
              l10n.cameraRequiredError,
              style: AppTheme.displayMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? l10n.unknownError,
              style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _initializeCamera,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(l10n.tryAgainButton, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final l10n = AppLocalizations.of(context);
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
            // Camera preview fills container with cover fit
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize!.height,
                  height: _cameraController!.value.previewSize!.width,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),

            // Overlay: instructions + AI status
            Positioned(
              top: 16, left: 16, right: 16,
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
                          width: 12, height: 12,
                          decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(l10n.cameraReady, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: AppTheme.primary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.positionDeviceInstruction,
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
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
                                : (_aiHint != null) ? AppTheme.error : AppTheme.accent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              (_aiHint == null && _boardDetected) ? Icons.check_circle : (_aiHint != null) ? Icons.warning_rounded : Icons.smart_toy_outlined,
                              color: (_aiHint == null && _boardDetected) ? AppTheme.success : (_aiHint != null) ? AppTheme.error : AppTheme.accent,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                (_aiHint == null && _boardDetected)
                                    ? l10n.dartboardDetectedGoodPosition
                                    : _aiHint ?? l10n.scanningForDartboard,
                                style: TextStyle(
                                  color: (_aiHint == null && _boardDetected) ? AppTheme.success : (_aiHint != null) ? AppTheme.error : AppTheme.accent,
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
              right: 12, top: 0, bottom: 0,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildZoomButton(Icons.add, _zoomIn),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '${_currentZoom.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
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
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.surfaceLight.withValues(alpha: 0.5))),
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
                _buildInfoRow(Icons.videocam, l10n.cameraOnDuringMatchInfo),
                const SizedBox(height: 8),
                _buildInfoRow(Icons.smart_toy, l10n.aiWillScoreDartsInfo),
                const SizedBox(height: 8),
                _buildInfoRow(Icons.my_location, l10n.makeSureDartboardVisibleInfo),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canPlay ? _onPlayPressed : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _canPlay ? AppTheme.primary : AppTheme.surfaceLight,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: _canPlay ? 4 : 0,
              ),
              child: Text(
                _playButtonLabel,
                style: TextStyle(
                  color: _canPlay ? Colors.white : AppTheme.textSecondary,
                  fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5,
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
        width: 40, height: 40,
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
        Expanded(child: Text(text, style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary, fontSize: 14))),
      ],
    );
  }
}

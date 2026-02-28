import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/storage_service.dart';
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
  State<TournamentCameraSetupScreen> createState() => _TournamentCameraSetupScreenState();
}

class _TournamentCameraSetupScreenState extends State<TournamentCameraSetupScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isLoading = true;
  bool _permissionsGranted = false;
  bool _cameraReady = false;
  String? _errorMessage;
  double _currentZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  bool _readyingSent = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

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
            _errorMessage = l10n.cameraAndMicPermissionRequired;
          } else if (!cameraGranted) {
            _errorMessage = l10n.cameraPermissionRequired;
          } else {
            _errorMessage = l10n.micPermissionRequired;
          }
        });
        return;
      }

      _permissionsGranted = true;
      _cameras = await availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = l10n.noCamerasFound;
        });
        return;
      }

      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();
      
      try {
        await _cameraController!.setFlashMode(FlashMode.off);
      } catch (e) {
        print('[Camera] Flash mode not supported: $e');
      }

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
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _cameraReady = false;
        _errorMessage = '${l10n.failedToInitializeCamera}: ${e.toString()}';
      });
    }
  }

  Future<void> _onReadyPressed() async {
    if (!_cameraReady || !_permissionsGranted || _readyingSent) return;

    setState(() => _readyingSent = true);
    HapticService.mediumImpact();
    await StorageService.saveCameraZoom(_currentZoom);

    await _cameraController?.dispose();
    _cameraController = null;

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => TournamentReadyScreen(
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
      ),
    );
  }

  @override
  void dispose() {
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
          onPressed: () {
            HapticService.lightImpact();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          l10n.cameraSetupTitle,
          style: const TextStyle(
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
            // Tournament match info bar
            _buildMatchInfoBar(),
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

  Widget _buildMatchInfoBar() {
    final l10n = AppLocalizations.of(context);
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

  Widget _buildLoadingView() {
    final l10n = AppLocalizations.of(context);
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
            l10n.initializingCamera,
            style: AppTheme.bodyLarge.copyWith(color: AppTheme.textSecondary),
          ),
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
              child: const Icon(
                Icons.videocam_off,
                color: AppTheme.error,
                size: 80,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              l10n.cameraRequiredError,
              style: AppTheme.displayMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  l10n.tryAgainButton,
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
            Center(
              child: CameraPreview(_cameraController!),
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(16),
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
                        Icon(Icons.info_outline, color: AppTheme.primary, size: 20),
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
    final l10n = AppLocalizations.of(context);
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
                _buildInfoRow(Icons.videocam, l10n.cameraOnDuringMatchInfo),
                const SizedBox(height: 8),
                _buildInfoRow(Icons.mic_off, l10n.micOffByDefault),
                const SizedBox(height: 8),
                _buildInfoRow(Icons.my_location, l10n.makeSureDartboardVisibleInfo),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _permissionsGranted && _cameraReady && !_readyingSent
                  ? _onReadyPressed
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _permissionsGranted && _cameraReady
                    ? AppTheme.success
                    : AppTheme.surfaceLight,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: _permissionsGranted && _cameraReady ? 4 : 0,
              ),
              child: Text(
                _readyingSent
                    ? l10n.ready
                    : _permissionsGranted && _cameraReady
                        ? l10n.ready
                        : l10n.cameraRequiredButton,
                style: TextStyle(
                  color: _permissionsGranted && _cameraReady
                      ? Colors.white
                      : AppTheme.textSecondary,
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

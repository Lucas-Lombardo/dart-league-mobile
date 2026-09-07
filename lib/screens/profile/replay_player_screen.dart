import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/notification_service.dart';

/// Full-screen player for one replay clip — local file (fresh capture) or
/// presigned R2 url (library). Two actions: save to the phone gallery (from
/// there Instagram / TikTok stories pick it up like any camera roll video)
/// and share to another app. Both always work on a FILE (remote clips are
/// downloaded to a temp path first, once), so TikTok/WhatsApp get a real
/// video, not a link.
class ReplayPlayerScreen extends StatefulWidget {
  const ReplayPlayerScreen({
    super.key,
    required this.source,
    required this.isLocal,
  });

  /// Local file path, or presigned https url.
  final String source;
  final bool isLocal;

  @override
  State<ReplayPlayerScreen> createState() => _ReplayPlayerScreenState();
}

class _ReplayPlayerScreenState extends State<ReplayPlayerScreen> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _sharing = false;
  bool _saving = false;

  /// Downloaded copy of a remote clip, kept so save + share don't fetch twice.
  String? _cachedLocalPath;

  bool get _actionsDisabled => _failed || _saving || _sharing;

  @override
  void initState() {
    super.initState();
    final controller = widget.isLocal
        ? VideoPlayerController.file(File(widget.source))
        : VideoPlayerController.networkUrl(Uri.parse(widget.source));
    _controller = controller;
    controller.initialize().then((_) {
      if (!mounted) return;
      controller.setLooping(true);
      controller.play();
      setState(() {});
    }).catchError((Object e) {
      debugPrint('[ReplayPlayer] init failed: $e');
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Path to a real file on disk for this clip, downloading it once if the
  /// clip lives in R2.
  Future<String> _ensureLocalFile() async {
    if (widget.isLocal) return widget.source;
    final cached = _cachedLocalPath;
    if (cached != null && File(cached).existsSync()) return cached;

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/replay_${DateTime.now().millisecondsSinceEpoch}.mp4');
    final resp = await http
        .get(Uri.parse(widget.source))
        .timeout(const Duration(minutes: 2));
    if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
    await file.writeAsBytes(resp.bodyBytes, flush: true);
    _cachedLocalPath = file.path;
    return file.path;
  }

  Future<void> _saveToGallery() async {
    if (_saving || _sharing) return;
    setState(() => _saving = true);
    final l10n = AppLocalizations.of(context);
    try {
      final path = await _ensureLocalFile();
      // Add-only access (no `album:`): iOS then just needs
      // NSPhotoLibraryAddUsageDescription. Asking for an album would escalate
      // to readWrite, which requires NSPhotoLibraryUsageDescription and full
      // read access to the user's whole photo library — not worth it, the clip
      // lands in Recents either way, where Instagram/TikTok pick it up.
      if (!await Gal.hasAccess()) {
        final granted = await Gal.requestAccess();
        if (!granted) {
          if (mounted) {
            NotificationService.showError(
                context, l10n.replayGalleryPermissionDenied);
          }
          return;
        }
      }
      await Gal.putVideo(path);
      if (mounted) {
        NotificationService.showSuccess(context, l10n.replaySavedToGallery);
      }
    } on GalException catch (e) {
      debugPrint('[ReplayPlayer] gallery save failed: ${e.type}');
      if (mounted) {
        NotificationService.showError(
          context,
          e.type == GalExceptionType.accessDenied
              ? l10n.replayGalleryPermissionDenied
              : l10n.replaySaveToGalleryFailed,
        );
      }
    } catch (e) {
      debugPrint('[ReplayPlayer] gallery save failed: $e');
      if (mounted) {
        NotificationService.showError(context, l10n.replaySaveToGalleryFailed);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    if (_sharing || _saving) return;
    setState(() => _sharing = true);
    final l10n = AppLocalizations.of(context);
    try {
      final path = await _ensureLocalFile();
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
    } catch (e) {
      debugPrint('[ReplayPlayer] share failed: $e');
      if (mounted) {
        NotificationService.showError(context, l10n.replayShareFailed);
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    HapticService.lightImpact();
    setState(() {
      controller.value.isPlaying ? controller.pause() : controller.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              GestureDetector(
                onTap: _togglePlayback,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
              )
            else
              Center(
                child: _failed
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_off_outlined,
                              size: 32, color: AppTheme.textTertiary),
                          const SizedBox(height: 10),
                          Text(l10n.errorOccurred, style: AppTheme.caption),
                        ],
                      )
                    : const CircularProgressIndicator(color: AppTheme.primary),
              ),
            // The pause glyph only shows while the clip is stopped: a control
            // over a playing video is a control in the way of the video.
            if (ready)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, _) => value.isPlaying
                    ? const SizedBox.shrink()
                    : Center(
                        child: _GlassButton(
                          icon: Icons.play_arrow_rounded,
                          size: 64,
                          onTap: _togglePlayback,
                        ),
                      ),
              ),
            Positioned(
              top: 8,
              left: 12,
              child: _GlassButton(
                icon: Icons.close_rounded,
                tooltip: l10n.close,
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (ready) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 3,
                        child: VideoProgressIndicator(
                          controller,
                          allowScrubbing: false,
                          padding: EdgeInsets.zero,
                          colors: VideoProgressColors(
                            playedColor: AppTheme.primary,
                            bufferedColor: Colors.white.withValues(alpha: 0.16),
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _actionsDisabled ? null : _saveToGallery,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          icon: _saving
                              ? const _ButtonSpinner()
                              : const Icon(Icons.download_rounded, size: 20),
                          label: Text(
                            l10n.replaySaveToGallery,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _actionsDisabled ? null : _share,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          icon: _sharing
                              ? const _ButtonSpinner()
                              : const Icon(Icons.ios_share_rounded, size: 18),
                          label: Text(
                            l10n.replayShare,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A control that has to sit ON the video: a glass disc instead of the
/// system's surface, so it reads over any frame without hiding it.
class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double size;

  const _GlassButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    Widget button = Material(
      color: Colors.white.withValues(alpha: 0.08),
      shape: CircleBorder(
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          HapticService.lightImpact();
          onTap();
        },
        child: SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Icon(
              icon,
              size: size <= 40 ? 20 : size * 0.44,
              color: const Color(0xFFE2E8F0),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return button;
  }
}

/// Spinner sized to sit in an icon slot without resizing the button.
class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 18,
        height: 18,
        child:
            CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
}

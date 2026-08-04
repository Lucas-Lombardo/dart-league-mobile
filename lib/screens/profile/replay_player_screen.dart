import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    return Scaffold(
      backgroundColor: AppTheme.gameBackground,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready)
              GestureDetector(
                onTap: () => setState(() {
                  controller.value.isPlaying
                      ? controller.pause()
                      : controller.play();
                }),
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
                    ? const Icon(Icons.videocam_off,
                        color: AppTheme.textSecondary, size: 48)
                    : const CircularProgressIndicator(color: AppTheme.primary),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _actionsDisabled ? null : _saveToGallery,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppTheme.primary.withValues(alpha: 0.4),
                        disabledForegroundColor:
                            Colors.white.withValues(alpha: 0.7),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: _saving
                          ? const _ButtonSpinner()
                          : const Icon(Icons.download_rounded, size: 20),
                      label: Text(
                        l10n.replaySaveToGallery,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _actionsDisabled ? null : _share,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        disabledForegroundColor:
                            Colors.white.withValues(alpha: 0.4),
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.35)),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: _sharing
                          ? const _ButtonSpinner()
                          : const Icon(Icons.ios_share, size: 18),
                      label: Text(
                        l10n.replayShare,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
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

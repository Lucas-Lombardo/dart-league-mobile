import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';

/// Full-screen player for one replay clip — local file (fresh capture) or
/// presigned R2 url (library). One primary action: share. The share sheet
/// always receives a FILE (remote clips are downloaded to a temp path
/// first), so TikTok/WhatsApp get a real video, not a link.
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

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      String path = widget.source;
      if (!widget.isLocal) {
        final dir = await getTemporaryDirectory();
        final file = File(
            '${dir.path}/share_${DateTime.now().millisecondsSinceEpoch}.mp4');
        final resp = await http
            .get(Uri.parse(widget.source))
            .timeout(const Duration(minutes: 2));
        if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
        await file.writeAsBytes(resp.bodyBytes, flush: true);
        path = file.path;
      }
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
    } catch (e) {
      debugPrint('[ReplayPlayer] share failed: $e');
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
              child: ElevatedButton.icon(
                onPressed: _failed ? null : _share,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: _sharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.ios_share, size: 18),
                label: Text(
                  l10n.replayShare,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

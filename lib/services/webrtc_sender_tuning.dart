import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'camera_frame_service.dart';

/// Outgoing-video tuning shared by both match transports (P2P and
/// Cloudflare): same encoder budget, same codec preference, so a series that
/// falls back from one to the other keeps the exact same picture and heat.
class WebRtcSenderTuning {
  WebRtcSenderTuning._();

  /// Outgoing-video encoder budget (thermal audit 2026-08-10). Without caps
  /// libwebrtc's BWE pushed the static 720p board scene to ~2.5 Mbps and the
  /// encoder ran unconstrained for the whole match — a top heat source on
  /// both phones (each pays its encode AND the peer's decode). DartsMind
  /// ships the same scene at ~1.1 Mbps @ 15 fps with no visible difference.
  /// The fps cap tracks the camera cadence — one Dart home for the value.
  static const int maxVideoBitrateBps = 1100 * 1000;
  static const int maxVideoFps = CameraFrameService.cameraFps;

  /// Apply [maxVideoBitrateBps]/[maxVideoFps] to the video sender.
  /// MAINTAIN_RESOLUTION: on a near-static board sharpness (reading the
  /// darts) matters, motion doesn't — under pressure the encoder drops
  /// frames instead of blurring the board.
  static Future<void> capVideoSender(
    RTCRtpSender sender, {
    String logTag = 'RTC',
  }) async {
    try {
      final params = sender.parameters;
      final encodings = params.encodings ?? <RTCRtpEncoding>[];
      if (encodings.isEmpty) encodings.add(RTCRtpEncoding());
      for (final encoding in encodings) {
        encoding.maxBitrate = maxVideoBitrateBps;
        encoding.maxFramerate = maxVideoFps;
      }
      params.encodings = encodings;
      params.degradationPreference =
          RTCDegradationPreference.MAINTAIN_RESOLUTION;
      await sender.setParameters(params);
    } catch (e) {
      // An uncapped sender still calls fine — worse thermally, never fatally.
      debugPrint('$logTag: video sender caps failed: $e');
    }
  }

  /// Put H264 first in the video transceiver's codec list (thermal round 5).
  /// Without an explicit preference the negotiation falls back to libwebrtc's
  /// default order, which lists VP8 first — SOFTWARE encode on Android
  /// offers and ALWAYS software decode on iOS (75% of the fleet), paid for
  /// the whole match on both phones. H264 rides the dedicated video block on
  /// both platforms. Reorder only, never filter: every codec stays offered,
  /// so a peer without H264 hardware still negotiates whatever it has.
  ///
  /// Must run before the offer/answer that carries the transceiver is made.
  static Future<void> preferH264(
    RTCPeerConnection? pc,
    RTCRtpSender sender, {
    String logTag = 'RTC',
  }) async {
    try {
      final caps = await getRtpSenderCapabilities('video');
      final codecs = caps.codecs ?? const [];
      final h264 = codecs
          .where((c) => c.mimeType.toLowerCase() == 'video/h264')
          .toList();
      if (h264.isEmpty) return;
      final rest = codecs
          .where((c) => c.mimeType.toLowerCase() != 'video/h264')
          .toList();
      final transceivers = await pc?.getTransceivers() ?? const [];
      for (final transceiver in transceivers) {
        if (transceiver.sender.senderId != sender.senderId) continue;
        await transceiver.setCodecPreferences([...h264, ...rest]);
        return;
      }
    } catch (e) {
      // Preference only — the default negotiation still connects fine.
      debugPrint('$logTag: H264 preference failed: $e');
    }
  }
}

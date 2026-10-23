import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'board_safe_video.dart';

/// A remote board feed, shared by the match transports and the spectator
/// screen.
///
/// The sender's frame aspect follows THEIR phone's orientation (portrait
/// 9:16, landscape 16:9) while our panel's follows OURS. `cover` cropped
/// that mismatch straight off the dartboard, `contain` answered it with half
/// a panel of black bars — so the view is sized by [BoardSafeVideo] instead,
/// which keeps the board whole and crops only what surrounds it. The inner
/// fit is `cover` on purpose: the box it gets already has the stream's exact
/// ratio, so cover and contain agree inside it.
///
/// The renderer reports its resolution asynchronously (and re-reports it
/// when the peer rotates), hence the listenable — and `contain` until the
/// first resolution lands, so nothing is cropped on a guess.
///
/// `value.width/height` are the frame's PRE-rotation dimensions: WebRTC
/// ships Android camera frames unrotated plus a rotation flag (CVO), and
/// RTCVideoView applies that flag at paint time. Sizing the box from the
/// raw dimensions gave a portrait Android sender a landscape box around a
/// portrait picture, and the inner `cover` zoomed ~1.8× straight into the
/// board — so the box must be sized from the DISPLAYED (rotated) ones.
///
/// [zoom] is the opponent-turn dart zoom and [topInset] the badge row the
/// fitted video stays below (see [BoardSafeVideo]); both zero on screens
/// that only watch.
Widget remoteVideoView(
  RTCVideoRenderer renderer, {
  ValueListenable<VideoZoomState>? zoom,
  double topInset = 0,
}) => ValueListenableBuilder<RTCVideoValue>(
  valueListenable: renderer,
  builder: (context, value, _) {
    if (value.width <= 0 || value.height <= 0) {
      return RTCVideoView(
        renderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      );
    }
    final rotated = value.rotation == 90 || value.rotation == 270;
    return BoardSafeVideo(
      sourceWidth: rotated ? value.height : value.width,
      sourceHeight: rotated ? value.width : value.height,
      zoom: zoom,
      topInset: topInset,
      child: RTCVideoView(
        renderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      ),
    );
  },
);

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;

import '../models/rtc_v2_config.dart';
import 'p2p_rtc_session.dart';
import 'rtc_frames_service.dart';
import 'rtc_recovery_policy.dart';

/// Everything the game screen needs to run match video over P2P, in one
/// object: the session, the native capture track, and the recovery ladder.
///
/// The screen used to own all three plus eight coordination flags; keeping
/// them together is what makes the P2P path deletable — and, the day Agora
/// goes away, the ONLY thing the screen has to know about video.
///
/// Not merged with the Agora path on purpose: Agora re-keys its channel on
/// every leg and owns its own reconnection, P2P does neither. A shared
/// interface would fit neither transport and would be half-deleted anyway.
class P2pMatchVideo {
  P2pMatchVideo({
    required this.matchId,
    required this.opponentId,
    required this.config,
    required this.onChanged,
    required this.onGiveUp,
  });

  final String matchId;
  final String opponentId;
  final RtcV2Config config;

  /// Something the UI renders changed (connection, remote video).
  final VoidCallback onChanged;

  /// The ladder exhausted every option — the screen switches to Agora. Once
  /// Agora is deleted this becomes a no-op and the ladder keeps rebuilding.
  final void Function(String reason) onGiveUp;

  P2pRtcSession? _session;
  RtcRecoveryPolicy? _recovery;
  int? _trackGeneration;
  bool _rebuilding = false;
  bool _stopped = false;
  bool _remoteReady = false;

  bool get isRunning => _session != null && !_stopped;
  bool get isRemoteReady => _remoteReady;
  bool get isLinkUp => _session?.isLinkUp ?? false;

  Widget? remoteView() => _session?.remoteView();

  /// Starts the call. Returns once the connection attempt has been made —
  /// failures are handled by the ladder, not by the caller.
  Future<void> start() async {
    if (_stopped) return;
    _recovery ??= RtcRecoveryPolicy(
      onRestartIce: () => _session?.restartIce(),
      onRebuild: _rebuild,
      onGiveUp: (reason) {
        if (!_stopped) onGiveUp(reason);
      },
    );
    await _connect();
  }

  Future<void> _connect() async {
    final session = P2pRtcSession(
      matchId: matchId,
      opponentId: opponentId,
      config: config,
      onConnected: onChanged,
      onRemoteVideoReady: () {
        _remoteReady = true;
        onChanged();
      },
      onHealthy: () => _recovery?.noteHealthy(),
      onImpaired: (reason) => _recovery?.noteImpaired(reason),
    );
    _session = session;
    // The track is built INSIDE connect(), after the PeerConnection exists:
    // flutter_webrtc's native factory is only initialized once a PC was
    // created — creating it first returned no_factory on Android and
    // silently degraded the call to receive-only. A null track still
    // connects receive-only and is tagged in telemetry.
    await session.connect(localVideoTrackFactory: () async {
      final track = await RtcFramesService.createTrack();
      _trackGeneration = RtcFramesService.generation;
      if (track == null) {
        session.noteLocalVideoFailure(RtcFramesService.lastCreateError);
      }
      return track;
    });
    // Remote audio through the loudspeaker, like the Agora video profile
    // (WebRTC's iOS default is the earpiece).
    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (_) {}
  }

  /// A fresh PeerConnection re-gathers candidates on the CURRENT network and
  /// connects like a first call (~2s), where an ICE restart reuses those of
  /// the network that just died. The camera and the AI are untouched: only
  /// the session and the native track are recreated, so a rebuild costs no
  /// camera restart (and no extra heat).
  Future<void> _rebuild() async {
    if (_stopped || _rebuilding) return;
    _rebuilding = true;
    try {
      final old = _session;
      _session = null;
      _remoteReady = false;
      onChanged();
      try {
        await old
            ?.dispose(reason: 'rebuild')
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      await RtcFramesService.disposeTrack(ifGeneration: _trackGeneration);
      if (_stopped) return;
      await _connect();
    } catch (e) {
      debugPrint('[P2pMatchVideo] rebuild failed: $e');
    } finally {
      _rebuilding = false;
    }
  }

  /// The socket came back: it proves the network is usable again, so drive a
  /// renegotiation NOW instead of waiting for the ladder's next step — any
  /// offer emitted into the dead socket was lost (signals have no replay).
  void onSocketReconnected() {
    if (_stopped || isLinkUp) return;
    _session?.restartIce();
  }

  Future<void> setMicEnabled(bool enabled) async {
    await _session?.setMicEnabled(enabled);
  }

  /// Whether a mic track exists at all (permission denied ⇒ false).
  bool get hasLocalAudio => _session?.hasLocalAudio ?? false;

  /// Tears everything down. [fellBack] marks the telemetry report when the
  /// screen is switching to Agora.
  Future<void> stop({bool fellBack = false, String? reason}) async {
    if (_stopped) return;
    _stopped = true;
    _recovery?.dispose();
    _recovery = null;
    final session = _session;
    _session = null;
    _remoteReady = false;
    try {
      await session
          ?.dispose(fellBack: fellBack, reason: reason)
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
    await RtcFramesService.disposeTrack(ifGeneration: _trackGeneration);
  }

  /// Fire-and-forget teardown for `State.dispose`, which cannot await.
  void stopDetached({bool fellBack = false, String? reason}) {
    stop(fellBack: fellBack, reason: reason);
  }
}

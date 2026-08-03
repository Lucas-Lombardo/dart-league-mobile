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
    required this.configProvider,
    required this.onChanged,
    required this.onGiveUp,
  });

  final String matchId;
  final String opponentId;
  /// Read at every (re)connect, never frozen: a `game_state_sync` can carry
  /// freshly minted Cloudflare TURN credentials, and a long match rebuilding
  /// with the initial payload's expired ones could never reach the relay.
  final RtcV2Config Function() configProvider;

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
  // Survives rebuilds: a new session always starts muted, so without this
  // an unmuted player went silent for the rest of the match with no visible
  // symptom (the screen's mic icon still read "on").
  bool _micEnabled = false;
  int _rebuildCount = 0;
  // The connect currently in flight, so stop() can wait for it instead of
  // racing its track creation and orphaning the native track.
  Future<void>? _connecting;

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
    _connecting = _connect();
    await _connecting;
  }

  Future<void> _connect({bool isRebuild = false}) async {
    final session = P2pRtcSession(
      matchId: matchId,
      opponentId: opponentId,
      config: configProvider(),
      onConnected: onChanged,
      onRemoteVideoReady: () {
        _remoteReady = true;
        onChanged();
      },
      onHealthy: () => _recovery?.noteHealthy(),
      onImpaired: (reason) => _recovery?.noteImpaired(reason),
      // On a rebuild BOTH roles must offer: the polite peer stays silent
      // until the opponent speaks, so a polite-side rebuild sat mute until
      // the other end noticed the stall — ~8-10s of black video for free.
      offerOnConnect: isRebuild ? true : null,
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
    // Re-apply the player's mic choice: every new session starts muted.
    if (_micEnabled) await session.setMicEnabled(true);
  }

  /// A fresh PeerConnection re-gathers candidates on the CURRENT network and
  /// connects like a first call (~2s), where an ICE restart reuses those of
  /// the network that just died. The camera and the AI are untouched: only
  /// the session and the native track are recreated, so a rebuild costs no
  /// camera restart (and no extra heat).
  Future<void> _rebuild(String reason) async {
    if (_stopped || _rebuilding) return;
    _rebuilding = true;
    try {
      final old = _session;
      _session = null;
      _remoteReady = false;
      onChanged();
      try {
        // No telemetry on a rebuild: the backend caps reports at 6/min per
        // socket, and a burst of rebuild rows would evict the ONE report
        // that explains the outcome — plus they'd skew the connection rate
        // with connected:false rows. The terminal report carries the count.
        await old
            ?.dispose(report: false)
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      await RtcFramesService.disposeTrack(ifGeneration: _trackGeneration);
      if (_stopped) return;
      _rebuildCount++;
      _connecting = _connect(isRebuild: true);
      await _connecting;
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
    _recovery?.noteSignalingBack();
    _session?.restartIce();
  }

  /// The app returned to the foreground — see
  /// [RtcRecoveryPolicy.noteAppResumed]: background time must not consume
  /// the recovery budget.
  void onAppResumed() {
    if (_stopped) return;
    _recovery?.noteAppResumed();
  }

  Future<void> setMicEnabled(bool enabled) async {
    _micEnabled = enabled;
    await _session?.setMicEnabled(enabled);
  }

  /// Tears everything down. [fellBack] marks the telemetry report when the
  /// screen is switching to Agora.
  Future<void> stop({bool fellBack = false, String? reason}) async {
    if (_stopped) return;
    _stopped = true;
    _recovery?.dispose();
    _recovery = null;
    // A connect in flight is still creating its native track; disposing
    // around it would leave that track orphaned for the process's life.
    try {
      await _connecting?.timeout(const Duration(seconds: 5));
    } catch (_) {}
    final session = _session;
    _session = null;
    _remoteReady = false;
    try {
      await session
          ?.dispose(
            fellBack: fellBack,
            reason: _rebuildCount > 0 && reason != null
                ? '$reason after $_rebuildCount rebuild(s)'
                : reason,
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
    await RtcFramesService.disposeTrack(ifGeneration: _trackGeneration);
  }

  /// Fire-and-forget teardown for `State.dispose`, which cannot await.
  void stopDetached({bool fellBack = false, String? reason}) {
    stop(fellBack: fellBack, reason: reason);
  }
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/rtc_v2_config.dart';
import 'socket_service.dart';

/// One P2P WebRTC call with the match opponent — the RTC v2 path selected
/// when the payload carried an `rtcV2` block (both clients support it).
///
/// Lifetime: one instance per opponent pairing, owned by the game screen. It
/// deliberately SURVIVES leg transitions (BO3 and tournament): the peers
/// don't change between legs, so unlike the Agora channel-per-leg flow there
/// is nothing to re-key.
///
/// Signaling rides the existing game socket (`rtc_signal`, relayed by the
/// backend between the two participants) using the perfect-negotiation
/// pattern; the polite role comes from the server so both sides agree.
/// Signals have no replay — on any doubt (socket reconnect, ICE failure) we
/// renegotiate from scratch rather than waiting for a lost message.
class P2pRtcSession {
  P2pRtcSession({
    required this.matchId,
    required this.opponentId,
    required this.config,
    this.onConnected,
    this.onRemoteVideoReady,
    this.onFailed,
  });

  /// The matchId used as the signaling scope. For a BO3 series this stays the
  /// FIRST leg's id on both sides (both screens keep their session), which is
  /// fine: it is only a correlation key for the relay's membership check —
  /// the backend validates against leg 1's player pair, which never changes.
  final String matchId;

  /// The only peer whose signals are applied. The relay's membership check
  /// proves the sender was in the match it NAMED — but the server's pair
  /// cache is never invalidated when a match ends, so an opponent from a
  /// FINISHED match could still get signals relayed here. Filtering on the
  /// sender (not the matchId) closes that while keeping cross-leg signaling
  /// (same opponent, different leg id) working.
  final String opponentId;
  final RtcV2Config config;

  final VoidCallback? onConnected;
  final VoidCallback? onRemoteVideoReady;
  final void Function(String reason)? onFailed;

  /// How long the call may stay un-connected (from connect()) before we give
  /// up and let the screen fall back to the Agora credentials of the same
  /// payload.
  static const Duration connectTimeout = Duration(seconds: 10);

  /// ABSOLUTE budget for a mid-call outage, counted from the moment the
  /// media link first went down — not per state transition. The ICE agent
  /// bounces Disconnected↔Failed several times during a real outage, and
  /// re-arming a relative timer on each bounce made the total unbounded:
  /// ~45s of frozen video before the Agora fallback in the 2026-08-03
  /// airplane test. Every escalation is now measured against this deadline.
  static const Duration outageBudget = Duration(seconds: 15);

  /// Budget for an outage detected by the MEDIA watchdog alone (ICE still
  /// Connected). Longer, because the likeliest cause is a silent opponent
  /// (app backgrounded), where falling back to Agora rebuilds everything to
  /// display the same absent video.
  static const Duration mediaOutageBudget = Duration(seconds: 30);

  /// Poll cadence for the outage deadline while the link is down.
  static const Duration outageTick = Duration(seconds: 1);

  /// How often the decoded-frame counter is sampled once connected.
  static const Duration mediaCheckInterval = Duration(seconds: 3);

  /// No new decoded frame for this long = the remote video is frozen even
  /// though ICE still reports Connected. Happens after a network blip: the
  /// decoder waits for a keyframe that never comes, or media flows one way
  /// only. Neither the outage budget nor the socket-return kick can see it
  /// (connectionState never leaves Connected) — this is the only detector.
  static const Duration mediaStallTimeout = Duration(seconds: 6);

  /// Minimum spacing between two restart offers, whatever triggered them
  /// (socket kick, ICE failure, media stall) — stacked offers desynchronize
  /// the ICE generations and prevent convergence.
  static const Duration restartOfferThrottle = Duration(seconds: 3);

  /// How long a `Disconnected` state may self-heal before we force an ICE
  /// restart. Short: a real transient blip recovers in ~1-2s, and beyond
  /// that only a restart converges.
  static const Duration disconnectedGrace = Duration(seconds: 2);

  /// Re-emission cadence of the initial offer while the opponent has said
  /// NOTHING yet. Signals have no replay: if the polite peer registers its
  /// handler seconds after ours fired (tournament entry skew — one player
  /// arrives via the ready-state poll), the lone offer is gone, no ICE ever
  /// starts, and nothing else re-triggers — both sides would burn the 10s
  /// watchdog straight into Agora.
  static const Duration offerRetryInterval = Duration(seconds: 2);

  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStreamTrack? _localAudioTrack;
  MediaStream? _remoteStream;

  bool get polite => config.polite;
  bool _makingOffer = false;
  bool _ignoreOffer = false;
  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  bool _connected = false;
  // Live link state (unlike _connected, which is one-shot "ever connected").
  bool _linkUp = false;
  bool _disposed = false;
  // Terminal latch: once onFailed fired, no timer/state event may fire it
  // again (double fallback) or surface a late onConnected mid-fallback.
  bool _failed = false;
  bool _reportSent = false;
  // Serializes signal processing: _processSignal interleaves several awaits
  // (setRemote → createAnswer → setLocal) and a live signal racing a
  // buffered copy of itself could interleave into a state only the timers
  // could exit.
  Future<void> _signalChain = Future.value();
  // Signals received before our local tracks were attached are BUFFERED, not
  // processed: answering an offer mid-setup produces an answer without our
  // video m-line, and the polite peer never gets another clean chance —
  // that was the one-way-video prod test of 2026-08-02.
  bool _localSetupDone = false;
  final List<Map<dynamic, dynamic>> _bufferedSignals = [];
  bool _hadLocalVideo = false;
  String? _localVideoFailureDetail;

  /// Attach the native error that explains a missing local video track; it
  /// rides the telemetry report's reason.
  void noteLocalVideoFailure(String? detail) {
    _localVideoFailureDetail = detail;
  }
  DateTime? _connectStartedAt;
  int? _connectTimeMs;
  Timer? _connectWatchdog;
  Timer? _recoveryTimer;
  Timer? _disconnectedTimer;
  Timer? _offerRetryTimer;
  Timer? _mediaWatchdog;
  int? _lastFramesDecoded;
  DateTime? _lastFrameProgressAt;
  // When the media link first went down in the CURRENT outage — the origin
  // of [outageBudget]. Null while the link is up.
  DateTime? _linkDownSince;
  // True when the current outage was detected by the media watchdog only
  // (ICE never left Connected) — see [mediaOutageBudget].
  bool _mediaOriginOutage = false;
  DateTime? _lastRestartOfferAt;
  bool _remoteSignalSeen = false;
  int _iceRestartAttempts = 0;

  bool get isConnected => _connected;

  /// Live media-link state (false during an outage even if we once
  /// connected) — the screen uses it to decide whether a socket recovery
  /// should kick a renegotiation.
  bool get isLinkUp => _linkUp;

  /// Force a renegotiation NOW. Called when the SOCKET comes back while the
  /// media link is down: any restart offer emitted into the dead socket was
  /// lost forever (signals have no replay), and the polite peer otherwise
  /// has no way to drive recovery — the airplane-mode test wedged exactly
  /// here. Offering from either role is safe: glare is absorbed by the
  /// perfect-negotiation path (explicit rollback included).
  void kickIceRestart() {
    if (_disposed || _failed || _linkUp) return;
    // Throttle: the reconnect sync fires repeatedly on a flaky network, and
    // stacking restart offers desynchronizes the ICE generations (a late
    // answer to offer N applied over offer N+1, then N+1's answer dropped
    // as a duplicate) — the agent then never converges.
    final last = _lastRestartOfferAt;
    if (last != null &&
        DateTime.now().difference(last) < restartOfferThrottle) {
      return;
    }
    debugPrint('P2P: socket back while link down — kicking ICE restart');
    _restartAndOffer();
  }

  /// Restart ICE and (re)send an offer, serialized on the signal chain.
  void _restartAndOffer() {
    _lastRestartOfferAt = DateTime.now();
    try {
      _pc?.restartIce();
    } catch (e) {
      debugPrint('P2P: restartIce failed: $e');
    }
    _queueOffer(iceRestart: true);
  }

  /// Offers ride the SAME chain as incoming signals: since both peers may
  /// now restart, an offer created concurrently with an inbound one raced
  /// on the native PC and left it in a state where the answer never left.
  void _queueOffer({bool iceRestart = false}) {
    final next =
        _signalChain.then((_) => _makeOffer(iceRestart: iceRestart));
    _signalChain = next.catchError((_) {});
  }

  /// Establish the call. [localVideoTrackFactory] builds the custom-capturer
  /// track fed by the app-owned camera (see RtcFramesService); it is invoked
  /// AFTER the RTCPeerConnection exists, because flutter_webrtc's native
  /// factory is only guaranteed initialized once a PC was created — creating
  /// the track first made Android answer `no_factory` and silently degraded
  /// the call to receive-only. A null/failed track still connects
  /// (receive-only) so at least the opponent's board is visible.
  Future<void> connect({
    MediaStreamTrack? localVideoTrack,
    Future<MediaStreamTrack?> Function()? localVideoTrackFactory,
  }) async {
    if (_disposed) return;
    _connectStartedAt = DateTime.now();
    // Armed BEFORE the setup awaits, not after: a hang in
    // createPeerConnection / getUserMedia / the buffered-signal drain throws
    // nothing, so without this the session had NO timer at all — black
    // remote tile for the whole match with no fallback. Cancelled by
    // _handleConnected / _fail / dispose.
    _connectWatchdog = Timer(connectTimeout, () {
      if (!_connected && !_disposed && !_failed) {
        debugPrint('P2P: connect watchdog fired');
        _fail('connect_timeout');
      }
    });
    await remoteRenderer.initialize();

    final pc = await createPeerConnection({
      'iceServers': config.iceServers,
      'sdpSemantics': 'unified-plan',
    });
    if (_disposed) {
      // dispose() ran during the await and found nothing to close.
      try {
        await pc.close();
      } catch (_) {}
      return;
    }
    _pc = pc;

    pc.onTrack = (RTCTrackEvent event) {
      if (_disposed) return;
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        remoteRenderer.srcObject = _remoteStream;
        onRemoteVideoReady?.call();
      }
    };

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      _sendSignal({
        'type': 'candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    pc.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('P2P: connection state $state');
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          // Unconditional: _handleConnected is one-shot (first connect), but
          // every RECOVERY back to Connected must also forgive past ICE
          // failures — otherwise transient drops accumulate over a whole
          // series until they trip the permanent Agora fallback.
          _clearOutage();
          // Re-baseline the media counter: a renegotiation brings a new
          // SSRC and a counter restarting from zero.
          _lastFramesDecoded = null;
          _lastFrameProgressAt = DateTime.now();
          _handleConnected();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _linkUp = false;
          _markLinkDown();
          _handleIceFailure();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          // Disconnected is NOT always followed by Failed: after an earlier
          // ICE restart the agent can sit in Disconnected forever, and the
          // second airplane-mode outage froze exactly there — no Failed, so
          // no restart, no recovery timer, no fallback, and the socket-return
          // kick was skipped because _linkUp still read true.
          _linkUp = false;
          _markLinkDown();
          _disconnectedTimer?.cancel();
          _disconnectedTimer = Timer(disconnectedGrace, () {
            if (!_disposed && !_failed && !_linkUp) {
              debugPrint('P2P: still disconnected after grace — restarting ICE');
              _handleIceFailure();
            }
          });
          break;
        default:
          break;
      }
    };

    pc.onRenegotiationNeeded = () {
      // Never offer while local media is still being attached: every track
      // added during setup is covered by the explicit post-setup offer
      // (impolite) or by the answer to the buffered remote offer (polite).
      // Reacting mid-setup made the POLITE peer send an offer — a buffered
      // remote signal had already flipped _remoteSignalSeen — and the glare
      // that followed was fatal (see the rollback note in _processSignal).
      if (!_localSetupDone) return;
      // The polite peer stays quiet until the opponent has said ANYTHING, so
      // the two initial offers can't glare; afterwards it may renegotiate.
      if (polite && !_remoteSignalSeen) return;
      _queueOffer();
    };

    // Incoming signals. Single-slot registry is fine: there is exactly one
    // live session at a time, and dispose() releases the slot (owner-scoped).
    SocketService.on('rtc_signal', _onSignal, owner: this);

    // Mic: track added up-front but disabled, so the mute toggle is a plain
    // `enabled` flip with no renegotiation (parity with the Agora flow's
    // publishMicrophoneTrack=false default).
    try {
      final audio = await navigator.mediaDevices
          .getUserMedia({'audio': true, 'video': false});
      final audioTrack = audio.getAudioTracks().firstOrNull;
      if (_disposed) {
        // dispose() ran during getUserMedia (mic permission dialog can take
        // seconds): without this, the live capture would leak until process
        // death — OS mic indicator stuck on.
        try {
          audioTrack?.stop();
        } catch (_) {}
        return;
      }
      _localAudioTrack = audioTrack;
      if (_localAudioTrack != null) {
        _localAudioTrack!.enabled = false;
        await pc.addTrack(_localAudioTrack!, audio);
      }
    } catch (e) {
      // No mic permission is not fatal — video-only call.
      debugPrint('P2P: audio track unavailable: $e');
    }

    MediaStreamTrack? track = localVideoTrack;
    if (track == null && localVideoTrackFactory != null) {
      try {
        track = await localVideoTrackFactory();
      } catch (e) {
        debugPrint('P2P: localVideoTrackFactory failed: $e');
      }
    }
    if (track != null) {
      if (_disposed) {
        // Same late-dispose leak as the audio path.
        try {
          track.stop();
        } catch (_) {}
        return;
      }
      await attachLocalVideoTrack(track);
      _hadLocalVideo = true;
    }

    // Local media is final — process whatever the opponent sent meanwhile,
    // in order, so any buffered offer is answered WITH our video m-line.
    // Enqueue everything synchronously BEFORE awaiting: the chain preserves
    // enqueue order, so a live signal arriving mid-drain lands after every
    // buffered (older) one.
    _localSetupDone = true;
    Future<void>? lastDrained;
    for (final raw in List.of(_bufferedSignals)) {
      lastDrained = _enqueueSignal(raw);
    }
    _bufferedSignals.clear();
    if (lastDrained != null) await lastDrained;

    // Kick the first offer explicitly for the impolite peer: on some
    // platforms onRenegotiationNeeded doesn't refire reliably for tracks
    // added before the handler was useful. Then re-emit the SAME local
    // description every 2s until the opponent says anything at all — see
    // [offerRetryInterval]. Re-applying an identical offer is harmless for
    // the polite peer (it just answers again).
    if (!polite) {
      _queueOffer();
      _offerRetryTimer = Timer.periodic(offerRetryInterval, (timer) async {
        if (_disposed || _remoteSignalSeen || _linkUp) {
          timer.cancel();
          return;
        }
        try {
          final local = await _pc?.getLocalDescription();
          if (local?.sdp != null) {
            debugPrint('P2P: no signal from opponent yet — re-sending offer');
            _sendSignal({'type': local!.type, 'sdp': local.sdp});
          }
        } catch (e) {
          debugPrint('P2P: offer retry failed: $e');
        }
      });
    }
  }

  /// Attach (or replace) the local video track fed by the custom capturer.
  Future<void> attachLocalVideoTrack(MediaStreamTrack track) async {
    final pc = _pc;
    if (pc == null || _disposed) return;
    final senders = await pc.getSenders();
    final videoSender =
        senders.where((s) => s.track?.kind == 'video').firstOrNull;
    if (videoSender != null) {
      await videoSender.replaceTrack(track);
    } else {
      final stream = await createLocalMediaStream('dartrivals-local');
      await pc.addTrack(track, stream);
    }
  }

  /// Whether a live mic track exists (false when permission was denied) —
  /// lets the UI avoid showing an unmuted mic nobody can hear.
  bool get hasLocalAudio => _localAudioTrack != null;

  Future<void> setMicEnabled(bool enabled) async {
    _localAudioTrack?.enabled = enabled;
  }

  Widget remoteView() => RTCVideoView(
        remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );

  void _handleConnected() {
    if (_connected || _disposed || _failed) return;
    _connected = true;
    _connectWatchdog?.cancel();
    final started = _connectStartedAt;
    if (started != null && _connectTimeMs == null) {
      _connectTimeMs = DateTime.now().difference(started).inMilliseconds;
    }
    debugPrint('P2P: connected in ${_connectTimeMs}ms');
    _startMediaWatchdog();
    onConnected?.call();
  }

  /// Watches the DECODED-FRAME counter, not the ICE state: after a blip the
  /// connection can stay Connected while the remote picture is frozen for
  /// good (keyframe starvation / one-way media). On a stall we drive the
  /// normal recovery chain — ICE restart, then the outage budget's fallback.
  void _startMediaWatchdog() {
    _mediaWatchdog?.cancel();
    _lastFramesDecoded = null;
    _lastFrameProgressAt = DateTime.now();
    _mediaWatchdog = Timer.periodic(mediaCheckInterval, (_) async {
      if (_disposed || _failed) return;
      final pc = _pc;
      if (pc == null) return;
      // SUM over every video inbound-rtp, and never mix metrics: keeping the
      // last report only, or falling back to bytesReceived for one sample,
      // makes the counter jump scales and the comparison below false
      // forever — a permanent phantom stall.
      int? framesTotal;
      int? bytesTotal;
      try {
        final stats = await pc.getStats().timeout(const Duration(seconds: 2));
        for (final report in stats) {
          if (report.type != 'inbound-rtp') continue;
          final values = report.values;
          final kind = values['kind'] ?? values['mediaType'];
          if (kind != 'video') continue;
          final decoded = values['framesDecoded'];
          if (decoded is num) framesTotal = (framesTotal ?? 0) + decoded.toInt();
          final bytes = values['bytesReceived'];
          if (bytes is num) bytesTotal = (bytesTotal ?? 0) + bytes.toInt();
        }
      } catch (_) {
        return;
      }
      final counter = framesTotal ?? bytesTotal;
      if (counter == null || _disposed || _failed) return;
      final now = DateTime.now();
      // `!=`, not `>`: a renegotiation or an opponent relaunch brings a new
      // SSRC whose counter restarts at 0 — that IS progress, not a stall.
      if (_lastFramesDecoded == null || counter != _lastFramesDecoded) {
        _lastFramesDecoded = counter;
        _lastFrameProgressAt = now;
        // Media is the ONLY sensor for a freeze that leaves ICE Connected —
        // so it must also be the sensor of the recovery. Without this, a
        // stall that the ICE restart repaired still burned the outage
        // budget and fell back to Agora on a perfectly healthy call.
        if (!_linkUp &&
            pc.connectionState ==
                RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          debugPrint('P2P: media flowing again — outage cleared');
          _clearOutage();
        }
        return;
      }
      final since = _lastFrameProgressAt;
      if (since == null || now.difference(since) < mediaStallTimeout) return;
      debugPrint('P2P: remote video stalled (no decoded frame for '
          '${now.difference(since).inSeconds}s) — forcing recovery');
      // Re-baseline so the chain isn't re-triggered every tick while the
      // restart converges.
      _lastFrameProgressAt = now;
      _linkUp = false;
      // A media-only stall gets a longer budget: the opponent may simply
      // have backgrounded their app (nothing to repair, and falling back to
      // Agora would show the same absent video after a costly rebuild).
      _mediaOriginOutage = _linkDownSince == null;
      _handleIceFailure();
    });
  }

  /// Single place that declares the link healthy again.
  void _clearOutage() {
    _linkUp = true;
    _iceRestartAttempts = 0;
    _linkDownSince = null;
    _mediaOriginOutage = false;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _disconnectedTimer?.cancel();
    _disconnectedTimer = null;
  }

  /// Start (or keep) the current outage's clock and run the deadline poll —
  /// escalation is measured from the FIRST link-down, so a bouncing ICE
  /// agent can't extend the outage indefinitely.
  void _markLinkDown() {
    if (_disposed || _failed) return;
    _linkDownSince ??= DateTime.now();
    _recoveryTimer ??= Timer.periodic(outageTick, (_) {
      if (_disposed || _failed) return;
      if (_linkUp) {
        _recoveryTimer?.cancel();
        _recoveryTimer = null;
        return;
      }
      final since = _linkDownSince;
      final budget = _mediaOriginOutage ? mediaOutageBudget : outageBudget;
      if (since != null && DateTime.now().difference(since) >= budget) {
        _fail('ice_failed');
      }
    });
  }

  void _handleIceFailure() {
    if (_disposed || _failed) return;
    _disconnectedTimer?.cancel();
    _disconnectedTimer = null;
    _markLinkDown();
    final since = _linkDownSince;
    if (since != null && DateTime.now().difference(since) >= outageBudget) {
      _fail('ice_failed');
      return;
    }
    // Restarts stay capped per outage (the counter resets on Connected), but
    // the outage deadline above is what ultimately bounds the wait. Past the
    // cap we keep RE-SENDING the offer without restarting ICE again: the
    // relay has no replay, so an offer emitted while the opponent's socket
    // was down is gone forever and only a re-send can revive the call.
    // Either role may send it: waiting for the impolite peer wastes the
    // budget when its network is the one that died, and glare is absorbed
    // by perfect negotiation.
    final last = _lastRestartOfferAt;
    final throttled = last != null &&
        DateTime.now().difference(last) < restartOfferThrottle;
    if (throttled) return;
    if (_iceRestartAttempts < 2) {
      _iceRestartAttempts++;
      debugPrint('P2P: ICE failed — restart attempt $_iceRestartAttempts');
      _restartAndOffer();
    } else {
      debugPrint('P2P: restart cap reached — re-sending offer');
      _lastRestartOfferAt = DateTime.now();
      _queueOffer(iceRestart: true);
    }
  }

  void _fail(String reason) {
    if (_disposed || _failed) return;
    _failed = true;
    _connectWatchdog?.cancel();
    _recoveryTimer?.cancel();
    _disconnectedTimer?.cancel();
    _offerRetryTimer?.cancel();
    _mediaWatchdog?.cancel();
    debugPrint('P2P: failed ($reason)');
    onFailed?.call(reason);
  }

  Future<void> _makeOffer({bool iceRestart = false}) async {
    final pc = _pc;
    if (pc == null || _disposed) return;
    try {
      _makingOffer = true;
      final offer = await pc.createOffer(
          iceRestart ? {'iceRestart': true} : <String, dynamic>{});
      // Glare check: a remote offer may have landed while we were creating
      // ours; setLocalDescription would then throw and the perfect-
      // negotiation path already answered it.
      if (_disposed) return;
      await pc.setLocalDescription(offer);
      _sendSignal({'type': offer.type, 'sdp': offer.sdp});
    } catch (e) {
      debugPrint('P2P: makeOffer failed: $e');
    } finally {
      _makingOffer = false;
    }
  }

  Future<void> _onSignal(dynamic raw) async {
    if (_disposed || raw is! Map) return;
    // No strict matchId filter: the server already proved the sender is OUR
    // opponent (membership check on the relay), and the two sides can
    // legitimately correlate on different leg ids — the surviving session
    // keeps leg 1's id while a peer relaunched after a rejoin uses the
    // current leg's. There is exactly one live session at a time, so an
    // unexpected id is telemetry, not a reason to drop the only signal that
    // can revive the call.
    if (raw['matchId'] != matchId) {
      debugPrint('P2P: signal for ${raw['matchId']} while scoped to $matchId — accepting (cross-leg)');
    }
    // Sender filter — see [opponentId]. `from` is stamped by the relay from
    // the authenticated socket, never by the sender's payload.
    if (raw['from'] != opponentId) {
      debugPrint('P2P: dropping signal from ${raw['from']} (expected $opponentId)');
      return;
    }
    _remoteSignalSeen = true;
    _offerRetryTimer?.cancel();
    _offerRetryTimer = null;
    if (!_localSetupDone) {
      _bufferedSignals.add(raw);
      return;
    }
    await _enqueueSignal(raw);
  }

  /// All signal processing rides one chain — see [_signalChain].
  Future<void> _enqueueSignal(Map<dynamic, dynamic> raw) {
    final next = _signalChain.then((_) => _processSignal(raw));
    _signalChain = next.catchError((_) {});
    return next;
  }

  Future<void> _processSignal(Map<dynamic, dynamic> raw) async {
    if (_disposed) return;
    final data = raw['data'];
    if (data is! Map) return;
    final type = data['type'] as String?;
    final pc = _pc;
    if (pc == null) return;

    try {
      if (type == 'offer' || type == 'answer') {
        final description =
            RTCSessionDescription(data['sdp'] as String?, type);
        if (type == 'offer') {
          final offerCollision = _makingOffer ||
              (await pc.getSignalingState()) !=
                  RTCSignalingState.RTCSignalingStateStable;
          _ignoreOffer = !polite && offerCollision;
          if (_ignoreOffer) {
            debugPrint('P2P: glare — impolite peer ignoring remote offer');
            return;
          }
          if (offerCollision) {
            // EXPLICIT rollback: implicit rollback on setRemoteDescription is
            // a browser-spec behavior that native libwebrtc does not have —
            // without this, applying the offer in have-local-offer throws
            // "Called in wrong state" and the answer never leaves (the
            // both-sides connect_timeout of the 2026-08-03 prod test).
            //
            // Rollback ONLY when a local offer is actually set: a collision
            // detected via _makingOffer alone (our createOffer still in
            // flight, nothing set yet) leaves the state stable, where a
            // rollback throws and would abort THIS remote offer — the
            // in-flight setLocalDescription fails into _makeOffer's own
            // catch instead, which is the intended outcome.
            if ((await pc.getSignalingState()) ==
                RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
              debugPrint('P2P: glare — polite peer rolling back its own offer');
              await pc
                  .setLocalDescription(RTCSessionDescription('', 'rollback'));
            }
          }
          await pc.setRemoteDescription(description);
          _ignoreOffer = false;
          _remoteDescriptionSet = true;
          await _drainPendingCandidates();
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          _sendSignal({'type': answer.type, 'sdp': answer.sdp});
        } else {
          // Duplicate answer (our offer-retry can make the polite peer
          // answer more than once): applying it in stable state throws and
          // teaches nothing — skip.
          if ((await pc.getSignalingState()) ==
              RTCSignalingState.RTCSignalingStateStable) {
            return;
          }
          await pc.setRemoteDescription(description);
          _ignoreOffer = false;
          _remoteDescriptionSet = true;
          await _drainPendingCandidates();
        }
      } else if (type == 'candidate') {
        final candidate = RTCIceCandidate(
          data['candidate'] as String?,
          data['sdpMid'] as String?,
          (data['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (!_remoteDescriptionSet) {
          _pendingCandidates.add(candidate);
        } else {
          // Perfect negotiation: candidates are NEVER dropped outright —
          // they may belong to the next negotiation (an ICE restart's new
          // ufrag; dropping them kills relay-only links for good). Errors
          // are only suppressed when they stem from an offer we
          // deliberately ignored.
          try {
            await pc.addCandidate(candidate);
          } catch (e) {
            if (!_ignoreOffer) debugPrint('P2P: addCandidate failed: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('P2P: signal handling error ($type): $e');
    }
  }

  Future<void> _drainPendingCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    for (final c in List.of(_pendingCandidates)) {
      try {
        await pc.addCandidate(c);
      } catch (e) {
        debugPrint('P2P: addCandidate failed: $e');
      }
    }
    _pendingCandidates.clear();
  }

  void _sendSignal(Map<String, dynamic> data) {
    try {
      SocketService.emit('rtc_signal', {'matchId': matchId, 'data': data});
    } catch (e) {
      // Socket momentarily down — the reconnect path renegotiates anyway.
      debugPrint('P2P: sendSignal failed: $e');
    }
  }

  /// Whether the selected ICE candidate pair goes through a TURN relay.
  Future<bool?> _usedRelay() async {
    final pc = _pc;
    if (pc == null) return null;
    try {
      // Bounded: getStats on a zombie PC (mid-outage) can hang, and this
      // runs inside dispose — an unbounded await here blocked the whole
      // Agora fallback.
      final stats = await pc.getStats().timeout(const Duration(seconds: 2));
      String? selectedPairId;
      final pairs = <String, Map<dynamic, dynamic>>{};
      final localCandidates = <String, Map<dynamic, dynamic>>{};
      for (final report in stats) {
        if (report.type == 'transport') {
          selectedPairId =
              report.values['selectedCandidatePairId'] as String?;
        } else if (report.type == 'candidate-pair') {
          pairs[report.id] = report.values;
          if (report.values['selected'] == true) selectedPairId ??= report.id;
        } else if (report.type == 'local-candidate') {
          localCandidates[report.id] = report.values;
        }
      }
      final pair = selectedPairId != null ? pairs[selectedPairId] : null;
      final localId = pair?['localCandidateId'] as String?;
      final localCandidate = localId != null ? localCandidates[localId] : null;
      final candidateType =
          localCandidate == null ? null : localCandidate['candidateType'];
      if (candidateType == null) return null;
      return candidateType == 'relay';
    } catch (_) {
      return null;
    }
  }

  /// End-of-call telemetry (rtc_v2_reports). Sent at most once.
  Future<void> sendReport({bool fellBack = false, String? reason}) async {
    if (_reportSent) return;
    _reportSent = true;
    // Surface a send-only call in prod telemetry: connected=true with this
    // reason means the transport was fine but OUR camera track was never
    // attached (native capturer failure) — invisible otherwise. The native
    // error detail rides along, truncated to the DTO's 200-char cap.
    if (reason == null && !_hadLocalVideo) {
      final detail = _localVideoFailureDetail;
      reason = detail == null
          ? 'no_local_video_track'
          : 'no_local_video_track: $detail';
      if (reason.length > 200) reason = reason.substring(0, 200);
    }
    bool? usedRelay;
    if (_connected) usedRelay = await _usedRelay();
    RTCPeerConnectionState? state;
    try {
      state = _pc?.connectionState;
    } catch (_) {}
    try {
      SocketService.emit('rtc_v2_report', {
        'matchId': matchId,
        'connected': _connected,
        if (_connectTimeMs != null) 'connectTimeMs': _connectTimeMs,
        if (state != null)
          'iceFinalState':
              state.toString().replaceFirst('RTCPeerConnectionState.RTCPeerConnectionState', ''),
        'usedRelay': ?usedRelay,
        'fellBack': fellBack,
        'reason': ?reason,
      });
    } catch (e) {
      debugPrint('P2P: report emit failed: $e');
    }
  }

  Future<void> dispose({bool fellBack = false, String? reason}) async {
    if (_disposed) return;
    _disposed = true;
    _connectWatchdog?.cancel();
    _recoveryTimer?.cancel();
    _disconnectedTimer?.cancel();
    _offerRetryTimer?.cancel();
    _mediaWatchdog?.cancel();
    SocketService.off('rtc_signal', owner: this);
    await sendReport(fellBack: fellBack, reason: reason);
    try {
      await _pc?.close();
    } catch (_) {}
    try {
      // close() only closes the transport; dispose() is what deregisters the
      // native observer (flutter_webrtc keeps it in a map otherwise) —
      // without it every match leaks a PC + observer for the engine's life.
      await _pc?.dispose();
    } catch (_) {}
    _pc = null;
    try {
      _localAudioTrack?.stop();
    } catch (_) {}
    _localAudioTrack = null;
    _remoteStream = null;
    try {
      remoteRenderer.srcObject = null;
      await remoteRenderer.dispose();
    } catch (_) {}
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

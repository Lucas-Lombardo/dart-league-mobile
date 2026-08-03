import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/rtc_v2_config.dart';

/// ONE negotiation attempt with the match opponent: one PeerConnection, one
/// generation, one fixed role. When anything about it goes stale, nobody
/// repairs it in place — [P2pMatchVideo] throws it away and builds the next
/// generation. That single rule replaced the whole in-place-repair machinery
/// (ICE restarts, offer retries, perfect-negotiation rollback): recovery is
/// always "new session", so there is exactly one code path to trust.
///
/// The session is deliberately socket-free: it emits through [sendSignal] and
/// receives through [handleSignal], both owned by [P2pMatchVideo], which also
/// tags/filters the generation. Roles are fixed at construction: the
/// [offerer] makes the one offer, the other side answers it. Glare cannot
/// happen — role conflicts are resolved by the owner before a signal ever
/// reaches a session.
class P2pRtcSession {
  P2pRtcSession({
    required this.config,
    required this.offerer,
    required this.sendSignal,
    this.onConnected,
    this.onRemoteVideoReady,
    this.onHealthy,
    this.onImpaired,
  });

  final RtcV2Config config;

  /// Fixed at construction: true = this side creates THE offer once its
  /// local media is attached; false = it answers the offer it receives.
  final bool offerer;

  /// Outgoing signal transport, owned by [P2pMatchVideo] (which adds the
  /// matchId and generation tags).
  final void Function(Map<String, dynamic> data) sendSignal;

  final VoidCallback? onConnected;
  final VoidCallback? onRemoteVideoReady;

  /// Media is flowing. Reported on every recovery, not just the first
  /// connection — the recovery loop needs to know it can stand down.
  final VoidCallback? onHealthy;

  /// Media is NOT flowing (ICE down, or frames frozen while ICE still says
  /// Connected). The session reports; [P2pMatchVideo]'s loop decides.
  final void Function(String reason)? onImpaired;

  /// How often the decoded-frame counter is sampled once connected.
  static const Duration mediaCheckInterval = Duration(seconds: 3);

  /// No new decoded frame for this long = the remote video is frozen even
  /// though ICE still reports Connected (the decoder waits for a keyframe
  /// that never comes, or media flows one way only). No ICE state exposes
  /// this — it is the only sensor for that failure, and therefore also the
  /// sensor of its recovery.
  static const Duration mediaStallTimeout = Duration(seconds: 6);

  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStreamTrack? _localAudioTrack;
  MediaStream? _remoteStream;

  bool _remoteDescriptionSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];

  bool _connected = false;
  // Live link state (unlike _connected, which is one-shot "ever connected").
  bool _linkUp = false;
  bool _disposed = false;
  // Serializes signal processing: _processSignal interleaves several awaits
  // (setRemote → createAnswer → setLocal) and two signals racing each other
  // interleave into states the native PC never recovers from.
  Future<void> _signalChain = Future.value();
  // Signals received before our local tracks were attached are BUFFERED, not
  // processed: answering an offer mid-setup produces an answer without our
  // video m-line, and the peer never gets another clean chance — that was
  // the one-way-video prod test of 2026-08-02.
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
  Timer? _mediaWatchdog;
  int? _lastFramesDecoded;
  DateTime? _lastFrameProgressAt;
  bool _impairedReported = false;

  bool get isConnected => _connected;

  /// Live media state: true only while frames are actually flowing.
  bool get isLinkUp => _linkUp;

  void _setHealthy() {
    if (_disposed) return;
    _linkUp = true;
    _handleConnected();
    onHealthy?.call();
  }

  void _setImpaired(String reason) {
    if (_disposed || (!_linkUp && _impairedReported)) return;
    _linkUp = false;
    _impairedReported = true;
    onImpaired?.call(reason);
  }

  /// Establish the call. [localVideoTrackFactory] builds the custom-capturer
  /// track fed by the app-owned camera (see RtcFramesService); it is invoked
  /// AFTER the RTCPeerConnection exists, because flutter_webrtc's native
  /// factory is only guaranteed initialized once a PC was created — creating
  /// the track first returned no_factory on Android and silently degraded
  /// the call to receive-only. A null/failed track still connects
  /// (receive-only) so at least the opponent's board is visible.
  Future<void> connect({
    Future<MediaStreamTrack?> Function()? localVideoTrackFactory,
  }) async {
    if (_disposed) return;
    _connectStartedAt = DateTime.now();
    // Report impaired from the very start: an initial connection that never
    // lands is just an outage like any other, and the recovery loop owns the
    // deadline. This also covers a HANG in the setup awaits below (which
    // throws nothing) — the session used to have no timer at all there.
    onImpaired?.call('connecting');
    _impairedReported = true;
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
      sendSignal({
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
          // Re-baseline the media counter: a reconnection brings a new SSRC
          // whose counter restarts from zero.
          _lastFramesDecoded = null;
          _lastFrameProgressAt = DateTime.now();
          _setHealthy();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _setImpaired('ice_failed');
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          // Disconnected is NOT always followed by Failed: the agent can sit
          // here forever. Reporting it (instead of waiting for Failed) keeps
          // the recovery loop the single place that decides if it matters.
          _setImpaired('ice_disconnected');
          break;
        default:
          break;
      }
    };

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

    MediaStreamTrack? track;
    if (localVideoTrackFactory != null) {
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
      final stream = await createLocalMediaStream('dartrivals-local');
      await pc.addTrack(track, stream);
      _hadLocalVideo = true;
    }

    // Local media is final — process whatever the opponent sent meanwhile,
    // in order, so a buffered offer is answered WITH our video m-line.
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

    // The one offer. If it is lost (socket down, relay budget), nothing here
    // retries: the recovery loop rebuilds into a new generation, which is
    // the single retry mechanism for everything.
    if (offerer) {
      final next = _signalChain.then((_) => _makeOffer());
      _signalChain = next.catchError((_) {});
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
    if (_connected || _disposed) return;
    _connected = true;
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
  /// good. Purely a SENSOR — it reports healthy/impaired and lets the
  /// recovery loop decide what to do about it.
  void _startMediaWatchdog() {
    _mediaWatchdog?.cancel();
    _lastFramesDecoded = null;
    _lastFrameProgressAt = DateTime.now();
    _mediaWatchdog = Timer.periodic(mediaCheckInterval, (_) async {
      if (_disposed) return;
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
      if (counter == null || _disposed) return;
      final now = DateTime.now();
      // `!=`, not `>`: an opponent relaunch brings a new SSRC whose counter
      // restarts at 0 — that IS progress, not a stall.
      if (_lastFramesDecoded == null || counter != _lastFramesDecoded) {
        _lastFramesDecoded = counter;
        _lastFrameProgressAt = now;
        // Media is the ONLY sensor for a freeze that leaves ICE Connected —
        // so it must also be the sensor of the recovery. Without this, a
        // transient stall kept the loop rebuilding a perfectly healthy call.
        if (!_linkUp &&
            pc.connectionState ==
                RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          debugPrint('P2P: media flowing again');
          _setHealthy();
        }
        return;
      }
      final since = _lastFrameProgressAt;
      if (since == null || now.difference(since) < mediaStallTimeout) return;
      debugPrint('P2P: remote video stalled (no decoded frame for '
          '${now.difference(since).inSeconds}s)');
      _setImpaired('media_stalled');
    });
  }

  Future<void> _makeOffer() async {
    final pc = _pc;
    if (pc == null || _disposed) return;
    try {
      final offer = await pc.createOffer();
      if (_disposed) return;
      await pc.setLocalDescription(offer);
      sendSignal({'type': offer.type, 'sdp': offer.sdp});
    } catch (e) {
      debugPrint('P2P: makeOffer failed: $e');
    }
  }

  /// Feed one signal payload (already generation-matched and sender-filtered
  /// by [P2pMatchVideo]) into this session. Safe to call before [connect] —
  /// signals are buffered until the local media is attached.
  void handleSignal(Map<dynamic, dynamic> data) {
    if (_disposed) return;
    if (!_localSetupDone) {
      _bufferedSignals.add(data);
      return;
    }
    _enqueueSignal(data);
  }

  /// All signal processing rides one chain — see [_signalChain].
  Future<void> _enqueueSignal(Map<dynamic, dynamic> data) {
    final next = _signalChain.then((_) => _processSignal(data));
    _signalChain = next.catchError((_) {});
    return next;
  }

  Future<void> _processSignal(Map<dynamic, dynamic> data) async {
    if (_disposed) return;
    final type = data['type'] as String?;
    final pc = _pc;
    if (pc == null) return;

    try {
      if (type == 'offer') {
        // Role guard: the owner only routes an offer to an ANSWERER session
        // (an offer from a conflicting generation replaces the session
        // instead). Reaching here as offerer is a routing bug — ignore
        // rather than corrupt the PC state.
        if (offerer) {
          debugPrint('P2P: offer reached an offerer session — dropped');
          return;
        }
        await pc.setRemoteDescription(
            RTCSessionDescription(data['sdp'] as String?, type));
        _remoteDescriptionSet = true;
        await _drainPendingCandidates();
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        sendSignal({'type': answer.type, 'sdp': answer.sdp});
      } else if (type == 'answer') {
        // Duplicate answer: applying it in stable state throws and teaches
        // nothing — skip.
        if ((await pc.getSignalingState()) ==
            RTCSignalingState.RTCSignalingStateStable) {
          return;
        }
        await pc.setRemoteDescription(
            RTCSessionDescription(data['sdp'] as String?, type));
        _remoteDescriptionSet = true;
        await _drainPendingCandidates();
      } else if (type == 'candidate') {
        final candidate = RTCIceCandidate(
          data['candidate'] as String?,
          data['sdpMid'] as String?,
          (data['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (!_remoteDescriptionSet) {
          _pendingCandidates.add(candidate);
        } else {
          try {
            await pc.addCandidate(candidate);
          } catch (e) {
            debugPrint('P2P: addCandidate failed: $e');
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

  /// Whether the selected ICE candidate pair goes through a TURN relay.
  Future<bool?> _usedRelay() async {
    final pc = _pc;
    if (pc == null) return null;
    try {
      // Bounded: getStats on a zombie PC (mid-outage) can hang, and this
      // runs inside teardown — an unbounded await here blocked the whole
      // match exit.
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

  /// The telemetry fields this session can vouch for; [P2pMatchVideo] adds
  /// the matchId and emits the terminal report. Called BEFORE [dispose] so
  /// the stats query still has a PC to talk to.
  Future<Map<String, dynamic>> reportPayload() async {
    String? reason;
    // Surface a send-only call in prod telemetry: connected=true with this
    // reason means the transport was fine but OUR camera track was never
    // attached (native capturer failure) — invisible otherwise. The native
    // error detail rides along, truncated to the DTO's 200-char cap.
    if (!_hadLocalVideo) {
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
    return {
      'connected': _connected,
      'connectTimeMs': ?_connectTimeMs,
      'iceFinalState': ?state
          ?.toString()
          .replaceFirst('RTCPeerConnectionState.RTCPeerConnectionState', ''),
      'usedRelay': ?usedRelay,
      'reason': ?reason,
    };
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _mediaWatchdog?.cancel();
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

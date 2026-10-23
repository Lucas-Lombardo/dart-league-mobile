import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/rtc_v2_config.dart';
import '../widgets/board_safe_video.dart';
import '../widgets/remote_video_view.dart';
import 'match_audio_route.dart';
import 'match_video.dart';
import 'rtc_quality_probe.dart';
import 'rtc_frames_service.dart';
import 'socket_service.dart';
import 'webrtc_sender_tuning.dart';

/// Match video through Cloudflare Realtime (SFU): ONE PeerConnection to
/// Cloudflare that publishes this phone's camera + mic and receives the
/// opponent's. The opponent pulls the very same publication, and so does
/// every spectator — one encode, whatever the audience.
///
/// The backend holds the Cloudflare credentials; every exchange is a socket
/// request with an ACK:
///  1. `sfu_publish` (my offer, sendonly) → Cloudflare's answer;
///  2. `sfu_tracks` (server push) says what the opponent published;
///  3. `sfu_pull` → Cloudflare's OFFER adding their tracks to my session,
///     `sfu_answer` → my answer.
///
/// Recovery is one move, like P2P: rebuild the whole connection (republish +
/// re-pull) when it stays down; re-pull alone when only the opponent
/// republished. There is no glare and no role: Cloudflare always answers.
///
/// Giving up is NOT a local decision: [onFailed] asks [MatchVideo] to ask
/// the server, which moves BOTH players to P2P.
class SfuMatchVideo implements MatchVideoTransport {
  SfuMatchVideo({
    required this.matchId,
    required this.opponentId,
    required this.configProvider,
    required this.onChanged,
    required this.onFailed,
  });

  final String matchId;
  final String opponentId;

  /// ICE servers (Cloudflare TURN) come from the P2P block: the same relay
  /// also reaches the SFU, at no extra cost.
  final RtcV2Config Function() configProvider;
  final VoidCallback onChanged;
  final void Function(String reason) onFailed;

  /// No picture from the opponent this long after their tracks were pulled
  /// (or my own connection never up after publishing) → ask for P2P.
  static const Duration firstPictureDeadline = Duration(seconds: 8);

  /// A working call that stays down this long with the socket up is not
  /// coming back on Cloudflare → ask for P2P.
  static const Duration outageDeadline = Duration(seconds: 45);

  /// Outage age before the first rebuild (blips self-heal).
  static const Duration stalledGrace = Duration(seconds: 4);
  static const Duration rebuildInterval = Duration(seconds: 10);
  static const Duration fastRebuildSpacing = Duration(seconds: 3);
  static const Duration repullInterval = Duration(seconds: 8);
  static const Duration mediaCheckInterval = Duration(seconds: 3);
  static const Duration mediaStallTimeout = Duration(seconds: 6);

  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _rendererReady = false;

  RTCPeerConnection? _pc;
  MediaStreamTrack? _localAudioTrack;
  int? _trackGeneration;
  bool _hadLocalVideo = false;

  bool _stopped = false;
  bool _micEnabled = false;
  bool _remoteReady = false;
  bool _pcConnected = false;
  bool _mediaFlowing = false;
  bool _everConnected = false;
  bool _failedReported = false;
  bool _reportSent = false;
  String _lastImpairReason = 'connecting';

  // Serializes every mutation of the Cloudflare session (publish, pull,
  // answer): Cloudflare requires each exchange to finish before the next.
  Future<void> _chain = Future.value();
  bool _busy = false;
  Future<void>? _connecting;
  Timer? _loop;
  Timer? _mediaWatchdog;

  int _connectionGen = 0;
  bool _published = false;
  // Opponent's current publishing session (from sfu_tracks) and the one
  // whose tracks this connection pulled.
  String? _opponentSessionId;
  String? _pulledSessionId;
  // Audio is pulled on its own, after the picture: Cloudflare holds a pull
  // open until the track's first packet, and a mic that sends nothing must
  // never hold the board back. Retried a few times per publication.
  String? _audioPulledSessionId;
  int _audioPullAttempts = 0;
  DateTime? _lastAudioPullAt;
  static const int _maxAudioPullAttempts = 6;
  static const Duration audioRepullInterval = Duration(seconds: 10);
  DateTime? _pulledAt;
  DateTime? _publishedAt;
  DateTime? _lastPullAttemptAt;

  final DateTime _startedAt = DateTime.now();
  int? _firstFrameMs;
  // First time each step was reached, in ms since [_startedAt] — where the
  // connect time goes (report `diagnostics.phases`).
  final Map<String, int> _phases = {};
  late final RtcQualityProbe _quality = RtcQualityProbe(() => _pc);
  DateTime? _impairedSince;
  DateTime? _lastRebuildAt;
  int _rebuildCount = 0;
  bool _resumePending = false;
  int? _lastFramesDecoded;
  DateTime? _lastFrameProgressAt;

  @override
  bool get isRemoteReady => _remoteReady;

  /// Media is actually flowing on a connected PeerConnection.
  @override
  bool get isLinkUp => _pcConnected && _mediaFlowing;

  @override
  Widget? remoteView({
    ValueListenable<VideoZoomState>? zoom,
    double topInset = 0,
  }) => _rendererReady
      ? remoteVideoView(_renderer, zoom: zoom, topInset: topInset)
      : null;

  @override
  Future<void> start() async {
    if (_stopped) return;
    SocketService.onShared('sfu_tracks', _onTracks, owner: this);
    SocketService.addReconnectListener(_onSocketReconnected);
    _loop = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _quality.start();
    await MatchAudioRoute.prepare();
    try {
      await _renderer.initialize();
      _rendererReady = true;
    } catch (e) {
      debugPrint('SFU: renderer init failed: $e');
    }
    _connecting = _connect();
    try {
      // Bounded like P2P's: a hung native call must not also hang the
      // screen's camera/AI init that awaits start().
      await _connecting?.timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('SFU: initial connect failed: $e');
    }
  }

  // ── Connection ────────────────────────────────────────────────────────────

  /// One full connection: fresh PeerConnection, publish, then pull the
  /// opponent if they're already up. Replaces any previous one.
  Future<void> _connect() => _enqueue(() async {
    final gen = ++_connectionGen;
    _lastRebuildAt = DateTime.now();
    await _teardownConnection();
    if (_stopped) return;
    _published = false;
    _pulledSessionId = null;
    _audioPulledSessionId = null;
    _audioPullAttempts = 0;
    _pulledAt = null;
    _publishedAt = null;
    _impairedSince ??= DateTime.now();

    final pc = await createPeerConnection({
      'iceServers': configProvider().iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
    });
    if (_stopped || gen != _connectionGen) {
      await _closePc(pc);
      return;
    }
    _pc = pc;
    pc.onTrack = (event) => _onRemoteTrack(gen, event);
    pc.onConnectionState = (state) => _onConnectionState(gen, state);

    // Mic: sendonly, disabled until the player unmutes (no renegotiation
    // for the toggle).
    final audioStream = await _openMic();
    if (_stopped || gen != _connectionGen) return;
    if (_localAudioTrack != null && audioStream != null) {
      await pc.addTransceiver(
        track: _localAudioTrack!,
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.SendOnly,
          streams: [audioStream],
        ),
      );
    }

    // The native board track — AFTER the PC exists: flutter_webrtc's
    // native factory is only initialized once a PC was created.
    MediaStreamTrack? video;
    try {
      video = await RtcFramesService.createTrack();
      _trackGeneration = RtcFramesService.generation;
    } catch (e) {
      debugPrint('SFU: createTrack failed: $e');
    }
    if (_stopped || gen != _connectionGen) {
      await RtcFramesService.disposeTrack(ifGeneration: _trackGeneration);
      return;
    }
    if (video != null) {
      final stream = await createLocalMediaStream('dartrivals-sfu');
      final transceiver = await pc.addTransceiver(
        track: video,
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.SendOnly,
          streams: [stream],
        ),
      );
      _hadLocalVideo = true;
      await WebRtcSenderTuning.capVideoSender(
        transceiver.sender,
        logTag: 'SFU',
      );
      await WebRtcSenderTuning.preferH264(
        pc,
        transceiver.sender,
        logTag: 'SFU',
      );
    }
    if (video == null && _localAudioTrack == null) {
      // Nothing to publish: Cloudflare can't host a session for us, and
      // P2P can still run receive-only.
      _reportFailure('no_local_media');
      return;
    }

    final firstCandidate = Completer<void>();
    pc.onIceCandidate = (_) {
      if (!firstCandidate.isCompleted) firstCandidate.complete();
    };
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await _waitFirstCandidate(firstCandidate.future);
    final local = await pc.getLocalDescription();
    if (_stopped || gen != _connectionGen || local?.sdp == null) return;
    final tracks = _sendTracksOf(local!.sdp!);

    final ack = await _request('sfu_publish', {
      'matchId': matchId,
      'sdp': local.sdp,
      'tracks': tracks,
    });
    if (_stopped || gen != _connectionGen) return;
    if (ack == null) return; // socket down / timeout: the loop retries
    if (ack['ok'] != true) {
      _onRefusal('publish', ack);
      return;
    }
    await pc.setRemoteDescription(
      RTCSessionDescription(ack['sdp'] as String?, 'answer'),
    );
    _published = true;
    _publishedAt = DateTime.now();
    _phase('published');
    await MatchAudioRoute.routeToLoudspeaker();
    if (_micEnabled) _localAudioTrack?.enabled = true;
    debugPrint(
      'SFU: published (session ${ack['sessionId']}) in '
      '${DateTime.now().difference(_startedAt).inMilliseconds}ms',
    );
    unawaited(_announceWhenSending(gen, pc));
    if (_opponentSessionId != null) await _pullLocked(gen);
  });

  /// Tell the server my publication can be pulled (`sfu_ready`): once my
  /// connection is up AND my camera has sent packets — Cloudflare holds a
  /// pull of a packet-less track open, and the camera starts after start()
  /// returns. Never awaited by the connection chain. A camera that never
  /// sends is announced anyway after a while (the opponent's pull then fails
  /// cleanly and retries) rather than hiding the mic too.
  Future<void> _announceWhenSending(int gen, RTCPeerConnection pc) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!_stopped && gen == _connectionGen) {
      final timedOut = DateTime.now().isAfter(deadline);
      if (_pcConnected &&
          (timedOut || !_hadLocalVideo || await _videoPacketsSent(pc) > 0)) {
        if (_stopped || gen != _connectionGen) return;
        final ack = await _request('sfu_ready', {'matchId': matchId});
        if (ack != null && ack['ok'] == true) {
          _phase('ready');
          debugPrint(
            'SFU: announced ready after '
            '${DateTime.now().difference(_startedAt).inMilliseconds}ms'
            '${timedOut ? ' (camera still silent)' : ''}',
          );
          return;
        }
        if (ack != null && ack['transport'] == 'p2p') {
          _onRefusal('ready', ack);
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  Future<int> _videoPacketsSent(RTCPeerConnection pc) async {
    try {
      final stats = await pc.getStats().timeout(const Duration(seconds: 2));
      var sent = 0;
      for (final report in stats) {
        if (report.type != 'outbound-rtp') continue;
        final kind = report.values['kind'] ?? report.values['mediaType'];
        final packets = report.values['packetsSent'];
        if (kind == 'video' && packets is num) sent += packets.toInt();
      }
      return sent;
    } catch (_) {
      return 0;
    }
  }

  Future<MediaStream?> _openMic() async {
    try {
      final audio = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': false,
      });
      final track = audio.getAudioTracks().isEmpty
          ? null
          : audio.getAudioTracks().first;
      if (_stopped) {
        // Stopped during the mic permission dialog: release the capture or
        // the OS mic indicator stays on.
        try {
          track?.stop();
        } catch (_) {}
        return null;
      }
      _localAudioTrack = track;
      track?.enabled = false;
      return audio;
    } catch (e) {
      // No mic permission is not fatal — video-only.
      debugPrint('SFU: audio track unavailable: $e');
      return null;
    }
  }

  /// `{mid, kind}` of each m-line of [sdp] — what Cloudflare needs to name
  /// the published tracks. Read from the SDP (not the transceivers) because
  /// mids are only assigned by setLocalDescription.
  @visibleForTesting
  static List<Map<String, String>> sendTracksOf(String sdp) {
    final tracks = <Map<String, String>>[];
    String? kind;
    for (final raw in sdp.split('\n')) {
      final line = raw.trim();
      if (line.startsWith('m=')) {
        kind = line.startsWith('m=video')
            ? 'video'
            : line.startsWith('m=audio')
            ? 'audio'
            : null;
      } else if (line.startsWith('a=mid:') && kind != null) {
        if (!tracks.any((t) => t['kind'] == kind)) {
          tracks.add({'mid': line.substring(6), 'kind': kind});
        }
        kind = null;
      }
    }
    return tracks;
  }

  List<Map<String, String>> _sendTracksOf(String sdp) => sendTracksOf(sdp);

  /// Cloudflare is ICE-lite and takes no trickle — but it doesn't need my
  /// candidates either: I connect to ITS candidates (from the answer) and it
  /// learns my address from my checks, relayed ones included (candidates
  /// gathered later still pair locally). So the offer leaves with the first
  /// host candidate instead of waiting out the whole gathering — the TURN
  /// TLS allocation alone kept it ~1.5 s (measured 2026-10-23: 5.8 s to the
  /// first frame on two iPhones).
  Future<void> _waitFirstCandidate(Future<void> firstCandidate) async {
    try {
      await firstCandidate.timeout(const Duration(milliseconds: 300));
    } catch (_) {}
  }

  /// Pull the opponent's current publication onto my session.
  Future<void> _pull() => _enqueue(() => _pullLocked(_connectionGen));

  /// The opponent's picture first; their voice follows on its own.
  Future<void> _pullLocked(int gen) async {
    final target = _opponentSessionId;
    if (target == null || target == _pulledSessionId) return;
    _lastPullAttemptAt = DateTime.now();
    final ack = await _pullKinds(gen, const ['video']);
    if (ack == null) return;
    _pulledSessionId = ack['opponentSessionId'] as String? ?? target;
    _pulledAt = DateTime.now();
    _phase('pulled');
    // New SSRCs: the decoded-frame counter restarts — re-baseline it.
    _lastFramesDecoded = null;
    _lastFrameProgressAt = DateTime.now();
    debugPrint('SFU: pulled opponent video ($_pulledSessionId)');
    unawaited(_enqueue(() => _pullAudioLocked(gen)));
  }

  Future<void> _pullAudioLocked(int gen) async {
    final target = _pulledSessionId;
    if (target == null || target == _audioPulledSessionId) return;
    if (_audioPullAttempts >= _maxAudioPullAttempts) return;
    _audioPullAttempts++;
    _lastAudioPullAt = DateTime.now();
    final ack = await _pullKinds(gen, const ['audio']);
    if (ack == null) return;
    _audioPulledSessionId = target;
    await MatchAudioRoute.routeToLoudspeaker();
    debugPrint('SFU: pulled opponent audio ($target)');
  }

  /// One `sfu_pull` + answer exchange on my session. Returns the pull's ack
  /// on success, null otherwise (refusals are handled here).
  Future<Map?> _pullKinds(int gen, List<String> kinds) async {
    final pc = _pc;
    if (_stopped || gen != _connectionGen || pc == null || !_published) {
      return null;
    }
    final ack = await _request('sfu_pull', {
      'matchId': matchId,
      'kinds': kinds,
    });
    if (_stopped || gen != _connectionGen || ack == null) return null;
    if (ack['ok'] != true) {
      _onRefusal('pull_${kinds.join('_')}', ack);
      return null;
    }
    final offer = ack['sdp'] as String?;
    if (offer != null) {
      await pc.setRemoteDescription(RTCSessionDescription(offer, 'offer'));
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      final answerAck = await _request('sfu_answer', {
        'matchId': matchId,
        'sdp': answer.sdp,
      });
      if (_stopped || gen != _connectionGen || answerAck == null) return null;
      if (answerAck['ok'] != true) {
        _onRefusal('answer', answerAck);
        return null;
      }
    }
    return ack;
  }

  /// A refused request. `transport: p2p` = the server already moved the
  /// series (its `video_transport_changed` follows); anything else is
  /// retried by the loop.
  void _onRefusal(String op, Map ack) {
    debugPrint('SFU: $op refused: ${ack['error']}');
    if (ack['transport'] == 'p2p') {
      _reportFailure('server_p2p_on_$op');
    }
  }

  Future<Map?> _request(String event, Map<String, dynamic> data) async {
    try {
      final ack = await SocketService.request(event, data);
      return ack is Map ? ack : {'ok': false, 'error': 'empty_ack'};
    } catch (e) {
      debugPrint('SFU: $event failed: $e');
      return null;
    }
  }

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _chain.then((_) async {
      if (_stopped) return;
      _busy = true;
      try {
        await op();
      } catch (e) {
        debugPrint('SFU: operation failed: $e');
      } finally {
        _busy = false;
      }
    });
    _chain = next.catchError((_) {});
    return next;
  }

  // ── Remote media ──────────────────────────────────────────────────────────

  void _onRemoteTrack(int gen, RTCTrackEvent event) {
    if (_stopped || gen != _connectionGen) return;
    if (event.track.kind != 'video') return; // audio plays on its own
    Future<void>(() async {
      MediaStream stream;
      if (event.streams.isNotEmpty) {
        stream = event.streams.first;
      } else {
        stream = await createLocalMediaStream('sfu-remote');
        await stream.addTrack(event.track);
      }
      if (_stopped || gen != _connectionGen || !_rendererReady) return;
      _renderer.srcObject = stream;
      _remoteReady = true;
      onChanged();
    });
  }

  void _onConnectionState(int gen, RTCPeerConnectionState state) {
    if (_stopped || gen != _connectionGen) return;
    debugPrint('SFU: connection state $state');
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _pcConnected = true;
        _everConnected = true;
        _phase('connected');
        _startMediaWatchdog(gen);
        unawaited(MatchAudioRoute.routeToLoudspeaker());
        onChanged();
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        _pcConnected = false;
        _setImpaired(
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed
              ? 'ice_failed'
              : 'ice_disconnected',
        );
        break;
      default:
        break;
    }
  }

  void _setImpaired(String reason) {
    _lastImpairReason = reason;
    _mediaFlowing = false;
    _impairedSince ??= DateTime.now();
    onChanged();
  }

  /// framesDecoded is the only reliable sensor: a picture can freeze with
  /// the connection still "connected". Summed over every inbound video (a
  /// re-pull adds a new one), progress = the value CHANGES.
  void _startMediaWatchdog(int gen) {
    _mediaWatchdog?.cancel();
    _lastFramesDecoded = null;
    _lastFrameProgressAt = DateTime.now();
    _mediaWatchdog = Timer.periodic(mediaCheckInterval, (_) async {
      final pc = _pc;
      if (_stopped || gen != _connectionGen || pc == null) return;
      int? frames;
      try {
        final stats = await pc.getStats().timeout(const Duration(seconds: 2));
        for (final report in stats) {
          if (report.type != 'inbound-rtp') continue;
          final kind = report.values['kind'] ?? report.values['mediaType'];
          if (kind != 'video') continue;
          final decoded = report.values['framesDecoded'];
          if (decoded is num) frames = (frames ?? 0) + decoded.toInt();
        }
      } catch (_) {
        return;
      }
      if (_stopped || gen != _connectionGen) return;
      final now = DateTime.now();
      if (frames != null && frames > 0 && frames != _lastFramesDecoded) {
        _lastFramesDecoded = frames;
        _lastFrameProgressAt = now;
        if (_firstFrameMs == null) {
          _firstFrameMs = now.difference(_startedAt).inMilliseconds;
          _phase('frame');
          // P0 metric: match entry → first decoded opponent frame.
          debugPrint('SFU: first opponent frame after ${_firstFrameMs}ms');
        }
        if (!_mediaFlowing) {
          _mediaFlowing = true;
          _impairedSince = null;
          onChanged();
        }
        return;
      }
      final since = _lastFrameProgressAt;
      if (_mediaFlowing &&
          since != null &&
          now.difference(since) >= mediaStallTimeout) {
        debugPrint('SFU: opponent picture stalled');
        _setImpaired('media_stalled');
      }
    });
  }

  void _phase(String name) => _phases.putIfAbsent(
    name,
    () => DateTime.now().difference(_startedAt).inMilliseconds,
  );

  // ── Signals from the server ───────────────────────────────────────────────

  void _onTracks(dynamic data) {
    if (_stopped || data is! Map) return;
    final players = data['players'];
    if (players is! Map) return;
    final theirs = players[opponentId];
    if (theirs is! Map) return;
    final session = theirs['sessionId'] as String?;
    if (session == null || session == _opponentSessionId) return;
    _opponentSessionId = session;
    _audioPullAttempts = 0;
    _phase('tracks');
    debugPrint('SFU: opponent published session $session');
    _pull();
  }

  void _onSocketReconnected() {
    if (_stopped || isLinkUp) return;
    _rebuild('socket_reconnected', fast: true);
  }

  @override
  void onSocketReconnected() => _onSocketReconnected();

  /// Android can keep audio/ICE alive while the video codec or surface was
  /// lost in the background: rebuild once back in front.
  @override
  void onAppResumed() {
    if (_stopped) return;
    _resumePending = true;
    _tick();
  }

  // ── The recovery loop ─────────────────────────────────────────────────────

  bool _rebuild(String reason, {bool fast = false}) {
    if (_stopped || _busy) return false;
    final last = _lastRebuildAt;
    final spacing = fast ? fastRebuildSpacing : rebuildInterval;
    if (last != null && DateTime.now().difference(last) < spacing) {
      return false;
    }
    debugPrint('SFU: rebuilding ($reason)');
    _rebuildCount++;
    _remoteReady = false;
    _pcConnected = false;
    _mediaFlowing = false;
    onChanged();
    _connecting = _connect();
    return true;
  }

  void _tick() {
    if (_stopped || _busy) return;
    final now = DateTime.now();
    if (_resumePending && SocketService.isConnected) {
      _resumePending = false;
      if (_rebuild('app_resumed', fast: true)) return;
    }

    // First picture deadline: Cloudflare is not working for this pair.
    if (_firstFrameMs == null && !_failedReported) {
      final pulledAt = _pulledAt;
      final publishedAt = _publishedAt;
      if (pulledAt != null && now.difference(pulledAt) > firstPictureDeadline) {
        _reportFailure('no_remote_video_8s');
        return;
      }
      if (publishedAt != null &&
          !_pcConnected &&
          now.difference(publishedAt) > firstPictureDeadline) {
        _reportFailure('not_connected_8s');
        return;
      }
    }

    // The voice, pulled on its own after the picture: retry while missing.
    final lastAudio = _lastAudioPullAt;
    if (_pulledSessionId != null &&
        _pulledSessionId == _opponentSessionId &&
        _audioPulledSessionId != _pulledSessionId &&
        _audioPullAttempts < _maxAudioPullAttempts &&
        (lastAudio == null ||
            now.difference(lastAudio) > audioRepullInterval)) {
      final gen = _connectionGen;
      _enqueue(() => _pullAudioLocked(gen));
      return;
    }

    if (isLinkUp) return;
    if (!SocketService.isConnected) return;

    // A call that worked and stays down: give up on Cloudflare.
    final since = _impairedSince;
    if (_firstFrameMs != null &&
        since != null &&
        now.difference(since) > outageDeadline) {
      _reportFailure('outage_${outageDeadline.inSeconds}s:$_lastImpairReason');
      return;
    }

    if (!_published) {
      // Publish never landed (socket down, refusal): retry on the interval.
      _rebuild('not_published');
      return;
    }
    if (!_pcConnected) {
      if (since != null && now.difference(since) >= stalledGrace) {
        _rebuild(_lastImpairReason);
      }
      return;
    }
    // Connected but no picture: the opponent's publication may have
    // changed under us (they republished) — pull again, spaced out.
    final lastPull = _lastPullAttemptAt;
    if (_opponentSessionId != null &&
        (lastPull == null || now.difference(lastPull) > repullInterval) &&
        since != null &&
        now.difference(since) >= stalledGrace) {
      _pulledSessionId = null;
      _pull();
    }
  }

  void _reportFailure(String reason) {
    if (_failedReported || _stopped) return;
    _failedReported = true;
    _lastImpairReason = reason;
    onFailed(reason);
  }

  // ── Mic / teardown ────────────────────────────────────────────────────────

  @override
  Future<void> setMicEnabled(bool enabled) async {
    _micEnabled = enabled;
    _localAudioTrack?.enabled = enabled;
  }

  Future<void> _teardownConnection() async {
    _mediaWatchdog?.cancel();
    _mediaWatchdog = null;
    final pc = _pc;
    _pc = null;
    _pcConnected = false;
    _mediaFlowing = false;
    if (pc != null) await _closePc(pc);
    try {
      _localAudioTrack?.stop();
    } catch (_) {}
    _localAudioTrack = null;
    await RtcFramesService.disposeTrack(ifGeneration: _trackGeneration);
  }

  Future<void> _closePc(RTCPeerConnection pc) async {
    try {
      await pc.close().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      // close() alone leaves the native observer registered for the
      // engine's life.
      await pc.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  /// Tears everything down and sends the one terminal telemetry report.
  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _loop?.cancel();
    _mediaWatchdog?.cancel();
    _quality.stop();
    SocketService.offShared('sfu_tracks', owner: this);
    SocketService.removeReconnectListener(_onSocketReconnected);
    try {
      await _connecting?.timeout(const Duration(seconds: 5));
    } catch (_) {}
    if (!_reportSent) {
      _reportSent = true;
      final reason = [
        if (!_hadLocalVideo) 'no_local_video_track',
        if (!isLinkUp) _lastImpairReason,
        if (_rebuildCount > 0) '$_rebuildCount rebuild(s)',
      ].join(', ');
      try {
        SocketService.emit('rtc_v2_report', {
          'matchId': matchId,
          'transport': 'sfu',
          'connected': isLinkUp,
          'everConnected': _everConnected,
          // Match entry → first decoded opponent frame (the P0 metric).
          'connectTimeMs': ?_firstFrameMs,
          'fellBack': _failedReported,
          if (reason.isNotEmpty)
            'reason': reason.length > 200 ? reason.substring(0, 200) : reason,
          'diagnostics': {'phases': _phases, ..._quality.snapshot()},
        });
      } catch (e) {
        debugPrint('SFU: report emit failed: $e');
      }
    }
    // Bounded: a wedged native call must not hang the caller.
    try {
      await _teardownConnection().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('SFU: teardown failed: $e');
    }
    _remoteReady = false;
    try {
      _renderer.srcObject = null;
      await _renderer.dispose();
    } catch (_) {}
  }

  @override
  void stopDetached() {
    stop();
  }
}

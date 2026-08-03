import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;

import '../models/rtc_v2_config.dart';
import 'p2p_rtc_session.dart';
import 'rtc_frames_service.dart';
import 'socket_service.dart';

/// Everything the game screen needs to run match video over P2P, in one
/// object: the current session, the native capture track, and the recovery
/// loop. There is NO fallback: when the payload carried an rtcV2 block, both
/// clients are new and P2P is the transport for the whole series — an outage
/// is recovered by rebuilding, forever, never by switching to Agora.
///
/// ## How recovery works (all of it)
///
/// A session is one negotiation GENERATION with a fixed offerer/answerer
/// role. Nothing is ever repaired in place; the one recovery move is
/// "replace the session with generation N+1 and offer again". The loop below
/// decides when:
///
///  - media stopped (or never started) for ≥ [stalledGrace],
///  - AND the socket is up (signals have no replay — offering into a dead
///    socket wastes the relay budget and desynchronizes the pair),
///  - AND the current negotiation made no progress for ≥ [progressHold]
///    (a landing answer/candidate means the peer is actively converging —
///    rebuilding NOW is how a freshly recovered call got destroyed in the
///    2026-08-03 airplane test),
///  - AND the previous rebuild is ≥ [rebuildInterval] old,
///  → rebuild. The socket coming back triggers one immediately (the outage
///    just ended; waiting a full interval is dead video for free).
///
/// Both sides run the same loop, so both may rebuild at once; generations
/// make that safe instead of a glare: every signal is tagged, stale
/// generations are dropped, a HIGHER-generation offer replaces our session
/// (we answer it), and an equal-generation offer race is settled by the
/// server-assigned polite flag (polite adopts, impolite ignores). A peer
/// that relaunched at generation 0 mid-series is caught by the stale-offer
/// fast path in [_onSignal].
///
/// Not merged with the Agora path on purpose: Agora only remains for matches
/// against an old client and is on its way out entirely.
class P2pMatchVideo {
  P2pMatchVideo({
    required this.matchId,
    required this.opponentId,
    required this.configProvider,
    required this.onChanged,
  });

  /// The signaling scope. For a BO3 series this stays the FIRST leg's id on
  /// both sides (both screens keep their P2pMatchVideo), which is fine: it is
  /// only a correlation key for the relay's membership check — the backend
  /// validates against leg 1's player pair, which never changes.
  final String matchId;

  /// The only peer whose signals are applied. `from` is stamped by the relay
  /// from the authenticated socket, never by the sender's payload.
  final String opponentId;

  /// Read at every (re)connect, never frozen: a `game_state_sync` can carry
  /// freshly minted Cloudflare TURN credentials, and a long match rebuilding
  /// with the initial payload's expired ones could never reach the relay.
  final RtcV2Config Function() configProvider;

  /// Something the UI renders changed (connection, remote video).
  final VoidCallback onChanged;

  // ── Recovery timings ──────────────────────────────────────────────────────
  /// Outage age before the first rebuild: shorter blips self-heal (ICE
  /// Disconnected often recovers alone in 1-2s).
  static const Duration stalledGrace = Duration(seconds: 4);

  /// A signal from the peer landed this recently = the negotiation is alive,
  /// let it finish instead of rebuilding it from under itself.
  static const Duration progressHold = Duration(seconds: 3);

  /// Spacing between rebuild attempts — mostly "wait for the network". One
  /// attempt costs ~40-60 relayed signals; the relay budget (80/10s per
  /// match) fits one attempt per window with room for the peer's half.
  static const Duration rebuildInterval = Duration(seconds: 10);

  /// Spacing for the FAST paths (socket reconnect, stale-offer): they bypass
  /// the interval but must not turn a flapping socket into a rebuild storm.
  static const Duration fastRebuildSpacing = Duration(seconds: 3);

  P2pRtcSession? _session;
  Timer? _loop;
  int _gen = 0;
  int? _trackGeneration;
  bool _swapping = false;
  bool _stopped = false;
  bool _remoteReady = false;
  // Survives rebuilds: a new session always starts muted, so without this
  // an unmuted player went silent for the rest of the match with no visible
  // symptom (the screen's mic icon still read "on").
  bool _micEnabled = false;
  int _rebuildCount = 0;
  DateTime? _impairedSince;
  String _lastImpairReason = 'connecting';
  DateTime? _lastProgressAt;
  DateTime? _lastRebuildAt;
  // Signals for a generation whose session does not exist yet (adoption in
  // flight, swap window): kept in ARRIVAL order and re-routed through
  // _onSignal once the swap completes — stale generations drop themselves.
  final List<Map<dynamic, dynamic>> _swapBuffer = [];
  // The connect currently in flight, so stop() can wait for it instead of
  // racing its track creation and orphaning the native track.
  Future<void>? _connecting;
  bool _reportSent = false;

  bool get isRemoteReady => _remoteReady;
  bool get isLinkUp => _session?.isLinkUp ?? false;

  Widget? remoteView() => _session?.remoteView();

  /// Starts the call. Returns once the first connection attempt has been
  /// made — failures are handled by the recovery loop, not by the caller.
  Future<void> start() async {
    if (_stopped) return;
    SocketService.on('rtc_signal', _onSignal, owner: this);
    SocketService.addReconnectListener(_onSocketReconnected);
    _loop = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    // Initial roles come from the server so both sides agree with no
    // round-trip: the impolite peer offers, the polite peer answers.
    _connecting = _connect(offerer: !configProvider().polite);
    await _connecting;
  }

  Future<void> _connect({required bool offerer}) async {
    final gen = _gen;
    // EVERY new session counts as an attempt, adoption and first connect
    // included: ICE checks run for seconds AFTER the last signal landed, so
    // without this stamp the loop's progress-hold expires mid-convergence
    // and kills a negotiation that was about to succeed — the interval is
    // the per-attempt budget, not just rebuild spacing.
    _lastRebuildAt = DateTime.now();
    final session = P2pRtcSession(
      config: configProvider(),
      offerer: offerer,
      // Capture THIS session's generation: a disposed session draining its
      // last candidates must tag them with its own (stale) generation, not
      // whatever the counter says by then.
      sendSignal: (data) => _emitSignal(gen, data),
      onConnected: () {
        _noteProgress();
        onChanged();
      },
      onRemoteVideoReady: () {
        _remoteReady = true;
        onChanged();
      },
      onHealthy: () {
        _impairedSince = null;
        onChanged();
      },
      onImpaired: (reason) {
        _lastImpairReason = reason;
        _impairedSince ??= DateTime.now();
        onChanged();
      },
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

  void _emitSignal(int gen, Map<String, dynamic> data) {
    try {
      SocketService.emit('rtc_signal', {
        'matchId': matchId,
        'data': {...data, 'gen': gen},
      });
    } catch (e) {
      // Socket down — the signal is gone by design; the loop rebuilds once
      // the socket is back.
      debugPrint('P2P: sendSignal failed: $e');
    }
  }

  void _noteProgress() {
    _lastProgressAt = DateTime.now();
  }

  // ── Signal routing ────────────────────────────────────────────────────────

  void _onSignal(dynamic raw) {
    if (_stopped || raw is! Map) return;
    if (raw['from'] != opponentId) {
      debugPrint('P2P: dropping signal from ${raw['from']} '
          '(expected $opponentId)');
      return;
    }
    // No strict matchId filter: the relay already proved the sender is OUR
    // opponent, and the two sides can legitimately correlate on different
    // leg ids (the surviving side keeps leg 1's id, a relaunched peer uses
    // the current leg's).
    final data = raw['data'];
    if (data is! Map) return;
    final type = data['type'] as String?;
    final gen = (data['gen'] as num?)?.toInt() ?? 0;

    if (gen == _gen) {
      _noteProgress();
      final session = _session;
      if (session == null) {
        // Swap window: keep it for the session being built.
        _swapBuffer.add(raw);
        return;
      }
      if (type == 'offer' && session.offerer) {
        // Equal-generation offer race (both sides rebuilt at once): the
        // server-assigned polite flag settles it — polite adopts the peer's
        // offer, impolite ignores it and lets its own offer win.
        if (configProvider().polite) {
          _swapBuffer.add(raw);
          _adopt(gen);
        } else {
          debugPrint('P2P: gen $gen offer race — impolite keeps its own');
        }
        return;
      }
      session.handleSignal(data);
      return;
    }

    if (gen > _gen) {
      // The peer moved on to a newer generation. Only its OFFER can seed a
      // session on our side; candidates that outran a dropped offer are
      // useless without it (the peer will rebuild again).
      if (type == 'offer') {
        _noteProgress();
        _swapBuffer.add(raw);
        _adopt(gen);
      }
      return;
    }

    // gen < _gen: stale traffic from a generation we already abandoned —
    // EXCEPT an offer while we're down, which means the peer RELAUNCHED
    // (its counter restarted at 0) and will drop everything we sent so far:
    // jump to a fresh generation now so it can adopt ours.
    if (type == 'offer' && !isLinkUp) {
      debugPrint('P2P: offer from relaunched peer (gen $gen < $_gen)');
      _rebuild('peer_relaunched', fast: true);
    }
  }

  /// Answer the peer's generation [gen]: the triggering offer is already in
  /// [_swapBuffer] and reaches the new session via the post-swap drain. A
  /// no-op while a swap runs — the buffered offer is re-routed afterwards
  /// and adoption retries then.
  void _adopt(int gen) {
    if (_stopped || _swapping) return;
    debugPrint('P2P: adopting peer generation $gen (was $_gen)');
    _gen = gen;
    _swapSession(offerer: false);
  }

  /// Abandon the current session and negotiate generation N+1 as offerer.
  Future<void> _rebuild(String reason, {bool fast = false}) async {
    if (_stopped || _swapping) return;
    final last = _lastRebuildAt;
    if (fast &&
        last != null &&
        DateTime.now().difference(last) < fastRebuildSpacing) {
      return;
    }
    debugPrint('P2P: rebuilding ($reason) → generation ${_gen + 1}');
    _gen += 1;
    _rebuildCount++;
    _lastRebuildAt = DateTime.now();
    await _swapSession(offerer: true);
  }

  /// A fresh PeerConnection re-gathers candidates on the CURRENT network and
  /// connects like a first call (~2s). The camera and the AI are untouched:
  /// only the session and the native track are recreated, so a swap costs no
  /// camera restart (and no extra heat).
  Future<void> _swapSession({required bool offerer}) async {
    _swapping = true;
    try {
      final old = _session;
      _session = null;
      _remoteReady = false;
      onChanged();
      try {
        await old?.dispose().timeout(const Duration(seconds: 3));
      } catch (_) {}
      await RtcFramesService.disposeTrack(ifGeneration: _trackGeneration);
      if (_stopped) return;
      _connecting = _connect(offerer: offerer);
      // Bounded: a native call that hangs (createPeerConnection,
      // getUserMedia) must not leave _swapping stuck and freeze recovery
      // for the rest of the match. On timeout the loop simply tries the
      // next generation; a late completion is disposed by that swap.
      await _connecting?.timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('P2P: session swap failed: $e');
    } finally {
      _swapping = false;
    }
    // Re-route everything that arrived while there was no session to take
    // it (the adoption offer included). Full routing on purpose: stale
    // generations drop themselves, and an adoption that was refused because
    // THIS swap was running retries now that it is over.
    if (_swapBuffer.isNotEmpty && !_stopped) {
      final queued = List.of(_swapBuffer);
      _swapBuffer.clear();
      for (final raw in queued) {
        if (_stopped) break;
        _onSignal(raw);
      }
    }
  }

  // ── The recovery loop ─────────────────────────────────────────────────────

  void _tick() {
    if (_stopped || _swapping) return;
    if (isLinkUp) return;
    final since = _impairedSince;
    if (since == null) return;
    if (!SocketService.isConnected) return;
    final now = DateTime.now();
    if (now.difference(since) < stalledGrace) return;
    final progress = _lastProgressAt;
    if (progress != null && now.difference(progress) < progressHold) return;
    final last = _lastRebuildAt;
    if (last != null && now.difference(last) < rebuildInterval) return;
    _rebuild(_lastImpairReason);
  }

  /// The socket came back: the outage is over and everything sent during it
  /// is lost, so renegotiate NOW instead of waiting for the loop's interval.
  void _onSocketReconnected() {
    if (_stopped || isLinkUp) return;
    _rebuild('socket_reconnected', fast: true);
  }

  /// Kept for the screens' game_state_sync path, which can prove the socket
  /// works again before the socket-level listener has fired.
  void onSocketReconnected() => _onSocketReconnected();

  Future<void> setMicEnabled(bool enabled) async {
    _micEnabled = enabled;
    await _session?.setMicEnabled(enabled);
  }

  /// Tears everything down and sends the one terminal telemetry report.
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _loop?.cancel();
    _loop = null;
    _swapBuffer.clear();
    SocketService.off('rtc_signal', owner: this);
    SocketService.removeReconnectListener(_onSocketReconnected);
    // A connect in flight is still creating its native track; disposing
    // around it would leave that track orphaned for the process's life.
    try {
      await _connecting?.timeout(const Duration(seconds: 5));
    } catch (_) {}
    final session = _session;
    _session = null;
    _remoteReady = false;
    if (session != null && !_reportSent) {
      _reportSent = true;
      try {
        final payload =
            await session.reportPayload().timeout(const Duration(seconds: 3));
        // The reason ties the report to what the match ENDED as: a broken
        // link keeps its cause, and the rebuild count rides along.
        final parts = <String>[
          if (!session.isLinkUp && payload['reason'] == null)
            _lastImpairReason,
          if (_rebuildCount > 0) '$_rebuildCount rebuild(s)',
        ];
        SocketService.emit('rtc_v2_report', {
          'matchId': matchId,
          'fellBack': false,
          ...payload,
          if (parts.isNotEmpty && payload['reason'] == null)
            'reason': parts.join(', '),
        });
      } catch (e) {
        debugPrint('P2P: report emit failed: $e');
      }
    }
    try {
      await session?.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {}
    await RtcFramesService.disposeTrack(ifGeneration: _trackGeneration);
  }

  /// Fire-and-forget teardown for `State.dispose`, which cannot await.
  void stopDetached() {
    stop();
  }
}

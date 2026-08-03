import 'dart:async';

import 'package:flutter/foundation.dart';

/// THE recovery ladder for match video — the single place that decides what
/// happens when the picture stops, and for how long we keep trying.
///
/// It exists because that decision used to be split between the session
/// (grace → ICE restart → outage budget) and the game screen (rebuild ×N →
/// Agora): nobody could read the whole behavior in one place, and the
/// accidental worst case was ~84s that no one had chosen.
///
/// The transport only REPORTS health ([noteHealthy] / [noteImpaired]); every
/// timing decision lives here:
///
/// ```
/// Mid-call outage (the session was connected):
///  t+0s   picture stops   → nothing (blips self-heal)
///  t+2s   still down      → onRestartIce()  (cheap, keeps the media path)
///  t+8s   still down      → onRebuild()     (fresh PeerConnection, re-gathers on
///                                            the CURRENT network — the universal fix)
///  +10s each             → onRebuild() again
///  t+40s                 → onGiveUp()       (Agora, while it still exists)
///
/// First connection (nothing to restart):
///  t+10s  never connected → onRebuild(), then the same cadence
/// ```
///
/// The clock is wall-clock and restarts on [noteNetworkBack]: an outage
/// spent in the background must not consume the budget.
///
/// [onGiveUp] is optional BY DESIGN: once every install supports RTC v2 and
/// Agora is deleted, pass null and the ladder simply keeps rebuilding until
/// the network comes back — which is the behavior we actually want, since a
/// fresh session connects in ~2s the moment the network is usable again.
class RtcRecoveryPolicy {
  RtcRecoveryPolicy({
    required this.onRestartIce,
    required this.onRebuild,
    this.onGiveUp,
  });

  /// Cheap in-place recovery: keeps the PeerConnection and its tracks.
  final void Function() onRestartIce;

  /// Full session rebuild — a new PeerConnection gathering candidates on the
  /// current network. Works for every outage shape; costs ~2s of video.
  final Future<void> Function(String reason) onRebuild;

  /// Last resort while the legacy transport still exists. Null = keep
  /// rebuilding forever (post-Agora).
  final void Function(String reason)? onGiveUp;

  // ── The ladder ────────────────────────────────────────────────────────────
  /// A blip shorter than this fixes itself; reacting would cost more video
  /// than it saves.
  static const Duration selfHeal = Duration(seconds: 2);

  /// Time given to the ICE restart before escalating to a rebuild.
  static const Duration iceRestartWindow = Duration(seconds: 6);

  /// Budget for the FIRST connection, which has nothing to restart. It must
  /// not be `selfHeal`: negotiation legitimately takes seconds (TURN
  /// allocation, cold start, mic permission dialog), and rebuilding at t+2s
  /// destroyed a session that was still connecting.
  static const Duration firstConnectBudget = Duration(seconds: 10);

  /// A rebuild that hangs (native channel, getUserMedia) must not freeze the
  /// ladder: without a bound, `onGiveUp: null` — the post-Agora setup —
  /// would mean dead video for the rest of the match with no recourse.
  static const Duration rebuildTimeout = Duration(seconds: 20);

  /// Spacing between two rebuild attempts. A rebuild connects in ~2s when
  /// the network is back, so this is mostly "wait for the network".
  static const Duration rebuildInterval = Duration(seconds: 10);

  /// When [onGiveUp] is wired, how long we try before handing over.
  static const Duration giveUpAfter = Duration(seconds: 40);

  static const Duration _tick = Duration(seconds: 1);

  Timer? _timer;
  DateTime? _downSince;
  bool _restartIssued = false;
  DateTime? _lastRebuildAt;
  bool _rebuildInFlight = false;
  bool _finished = false;
  String _reason = 'unknown';

  /// Whether the transport ever reached a healthy state — an initial
  /// connection that never lands skips the ICE restart (there is no media
  /// path to salvage) and goes straight to rebuilds.
  bool _everHealthy = false;

  /// The transport is delivering media again.
  void noteHealthy() {
    _everHealthy = true;
    if (_downSince != null) {
      debugPrint('[RtcRecovery] healthy again after '
          '${DateTime.now().difference(_downSince!).inSeconds}s');
    }
    _downSince = null;
    _restartIssued = false;
    _lastRebuildAt = null;
    _timer?.cancel();
    _timer = null;
  }

  /// The transport is not delivering media (ICE down, or frames frozen).
  /// Idempotent: only the FIRST call starts the clock, so a bouncing ICE
  /// agent cannot extend the deadline — that unbounded-wait bug is what the
  /// absolute clock is for.
  void noteImpaired(String reason) {
    if (_finished) return;
    // Always keep the LATEST cause, even mid-outage: the clock starts once
    // (a bouncing ICE agent must not extend the deadline), but telemetry
    // needs the reason that actually characterizes the failure — otherwise
    // every report reads 'connecting', the state connect() opens with.
    _reason = reason;
    if (_downSince != null) return;
    _downSince = DateTime.now();
    debugPrint('[RtcRecovery] impaired ($reason) — ladder started');
    _timer = Timer.periodic(_tick, (_) => _step());
  }

  /// The socket reconnected: allow ONE more immediate ICE restart, because
  /// any offer emitted while the socket was dead is gone for good (no
  /// replay). It deliberately does NOT touch the clock — on a flaky network
  /// the socket bounces every few seconds, and rewinding the deadline each
  /// time meant the ladder never escalated past the restart: no rebuild, no
  /// hand-over, frozen video for the rest of the match.
  void noteSignalingBack() {
    if (_finished || _downSince == null) return;
    _restartIssued = false;
  }

  /// The app came back to the foreground. THIS is what restarts the clock:
  /// the budget is wall-clock, so a call or a locked screen was spending it
  /// while nothing could possibly reconnect — any absence longer than the
  /// budget handed over to Agora the very instant the user returned, before
  /// the renegotiation had a chance. Foreground time is real trying time;
  /// background time is not.
  void noteAppResumed() {
    if (_finished || _downSince == null) return;
    debugPrint('[RtcRecovery] app resumed — outage clock restarted');
    _downSince = DateTime.now();
    _restartIssued = false;
    _lastRebuildAt = null;
  }

  void _step() {
    final since = _downSince;
    if (_finished || since == null) return;
    final elapsed = DateTime.now().difference(since);

    if (elapsed >= giveUpAfter && onGiveUp != null) {
      _finished = true;
      _timer?.cancel();
      _timer = null;
      debugPrint('[RtcRecovery] giving up after ${elapsed.inSeconds}s');
      onGiveUp!(_reason);
      return;
    }

    if (!_restartIssued && elapsed >= selfHeal) {
      _restartIssued = true;
      if (_everHealthy) {
        debugPrint('[RtcRecovery] ICE restart');
        onRestartIce();
        return;
      }
      // Never connected: nothing to salvage, fall through to a rebuild.
    }

    final firstRebuildAt =
        _everHealthy ? selfHeal + iceRestartWindow : firstConnectBudget;
    final rebuildDue = _lastRebuildAt == null
        ? elapsed >= firstRebuildAt
        : DateTime.now().difference(_lastRebuildAt!) >= rebuildInterval;
    if (rebuildDue && !_rebuildInFlight) {
      _rebuildInFlight = true;
      _lastRebuildAt = DateTime.now();
      debugPrint('[RtcRecovery] rebuilding session');
      // `_restartIssued` deliberately stays true: a freshly rebuilt session
      // is mid-negotiation, and firing an ICE restart into it one tick later
      // is the very glare this ladder exists to avoid. The next rebuild is
      // the escalation, not a restart.
      onRebuild(_reason).timeout(rebuildTimeout).whenComplete(() {
        _rebuildInFlight = false;
      }).catchError((Object e) {
        debugPrint('[RtcRecovery] rebuild failed/timed out: $e');
      });
    }
  }

  void dispose() {
    _finished = true;
    _timer?.cancel();
    _timer = null;
  }
}

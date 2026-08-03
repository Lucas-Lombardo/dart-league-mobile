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
///  t+0s   picture stops                     → nothing (blips self-heal)
///  t+2s   still down, session was connected → onRestartIce()   (cheap, keeps the media path)
///  t+8s   still down                        → onRebuild()      (fresh PeerConnection, re-gathers
///                                                               on the CURRENT network — the
///                                                               universal fix)
///  every 10s after that                     → onRebuild() again
///  t+40s                                    → onGiveUp()       (Agora, while it still exists)
/// ```
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
  final Future<void> Function() onRebuild;

  /// Last resort while the legacy transport still exists. Null = keep
  /// rebuilding forever (post-Agora).
  final void Function(String reason)? onGiveUp;

  // ── The ladder ────────────────────────────────────────────────────────────
  /// A blip shorter than this fixes itself; reacting would cost more video
  /// than it saves.
  static const Duration selfHeal = Duration(seconds: 2);

  /// Time given to the ICE restart before escalating to a rebuild.
  static const Duration iceRestartWindow = Duration(seconds: 6);

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

  bool get isRecovering => _downSince != null;

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
    if (_finished || _downSince != null) return;
    _reason = reason;
    _downSince = DateTime.now();
    debugPrint('[RtcRecovery] impaired ($reason) — ladder started');
    _timer = Timer.periodic(_tick, (_) => _step());
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

    final rebuildDue = _lastRebuildAt == null
        ? elapsed >= selfHeal + (_everHealthy ? iceRestartWindow : Duration.zero)
        : DateTime.now().difference(_lastRebuildAt!) >= rebuildInterval;
    if (rebuildDue && !_rebuildInFlight) {
      _rebuildInFlight = true;
      _lastRebuildAt = DateTime.now();
      debugPrint('[RtcRecovery] rebuilding session');
      onRebuild().whenComplete(() {
        _rebuildInFlight = false;
        // A rebuilt session starts from scratch: let it earn its ICE restart
        // again if it too goes down.
        _restartIssued = false;
      });
    }
  }

  void dispose() {
    _finished = true;
    _timer?.cancel();
    _timer = null;
  }
}

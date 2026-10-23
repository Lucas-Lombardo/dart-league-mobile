import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../widgets/remote_video_view.dart';
import 'socket_service.dart';

/// A spectator's receive-only connection to Cloudflare Realtime: the two
/// players' cameras (VIDEO only — the backend never adds their mics), one
/// renderer per player. Both are pulled so a turn change switches the picture
/// instantly; the screen shows only the thrower's.
///
/// One [watch] = one fresh Cloudflare session (`spectator_video_watch` →
/// Cloudflare's offer → my answer via `spectator_video_answer`). When a player
/// republishes, the owner throws this away and watches again — no in-place
/// renegotiation to get wrong.
class SpectatorVideoSession {
  SpectatorVideoSession({required this.matchId, required this.onChanged});

  /// The leg being spectated (the server checks it against this socket).
  final String matchId;
  final VoidCallback onChanged;

  static const Duration mediaCheckInterval = Duration(seconds: 3);
  static const Duration mediaStallTimeout = Duration(seconds: 8);

  RTCPeerConnection? _pc;
  String? _sessionId;
  final Map<String, String> _midToPlayer = {};
  // Fallback key for the stats: older libwebrtc builds omit `mid` from
  // inbound-rtp, but always carry the receiving track's id.
  final Map<String, String> _trackToPlayer = {};
  final Map<String, RTCVideoRenderer> _renderers = {};
  final Map<String, int> _framesByMid = {};
  final Map<String, DateTime> _progressByPlayer = {};
  final Set<String> _flowing = {};
  Timer? _watchdog;
  bool _disposed = false;

  /// Whether [playerId]'s camera is actually delivering frames.
  bool hasVideoFor(String? playerId) =>
      playerId != null && _flowing.contains(playerId);

  Widget? viewFor(String playerId) {
    final renderer = _renderers[playerId];
    if (renderer == null) return null;
    return remoteVideoView(renderer);
  }

  /// Returns the server's refusal code, or null on success. `not_sfu` means
  /// the series is (now) on P2P: the owner falls back to the virtual board.
  Future<String?> watch() async {
    if (_disposed) return 'disposed';
    dynamic ack;
    try {
      ack = await SocketService.request('spectator_video_watch', {
        'matchId': matchId,
      });
    } catch (e) {
      debugPrint('SpectatorVideo: watch request failed: $e');
      return 'unreachable';
    }
    if (_disposed) return 'disposed';
    if (ack is! Map || ack['ok'] != true) {
      return ack is Map ? (ack['error']?.toString() ?? 'error') : 'error';
    }
    final sessionId = ack['sessionId'] as String?;
    final offer = ack['sdp'] as String?;
    final tracks = ack['tracks'];
    if (sessionId == null || offer == null || tracks is! List) return 'error';
    _sessionId = sessionId;
    for (final t in tracks) {
      if (t is Map && t['mid'] != null && t['playerId'] != null) {
        _midToPlayer['${t['mid']}'] = '${t['playerId']}';
      }
    }

    final iceServers = (ack['iceServers'] is List)
        ? (ack['iceServers'] as List)
              .whereType<Map>()
              .map((s) => Map<String, dynamic>.from(s))
              .toList()
        : <Map<String, dynamic>>[];
    try {
      final pc = await createPeerConnection({
        'iceServers': iceServers,
        'sdpSemantics': 'unified-plan',
        'bundlePolicy': 'max-bundle',
      });
      if (_disposed) {
        await _close(pc);
        return 'disposed';
      }
      _pc = pc;
      pc.onTrack = _onTrack;
      await pc.setRemoteDescription(RTCSessionDescription(offer, 'offer'));
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      final answerAck = await SocketService.request('spectator_video_answer', {
        'matchId': matchId,
        'sessionId': sessionId,
        'sdp': answer.sdp,
      });
      if (answerAck is! Map || answerAck['ok'] != true) {
        return answerAck is Map
            ? (answerAck['error']?.toString() ?? 'error')
            : 'error';
      }
      _startWatchdog();
      return null;
    } catch (e) {
      debugPrint('SpectatorVideo: negotiation failed: $e');
      return 'error';
    }
  }

  void _onTrack(RTCTrackEvent event) {
    if (_disposed || event.track.kind != 'video') return;
    final mid = event.transceiver?.mid;
    final playerId = mid != null ? _midToPlayer[mid] : null;
    if (playerId == null) {
      debugPrint('SpectatorVideo: track on unknown mid $mid');
      return;
    }
    final trackId = event.track.id;
    if (trackId != null) _trackToPlayer[trackId] = playerId;
    Future<void>(() async {
      final renderer = RTCVideoRenderer();
      await renderer.initialize();
      MediaStream stream;
      if (event.streams.isNotEmpty) {
        stream = event.streams.first;
      } else {
        stream = await createLocalMediaStream('spectate-$playerId');
        await stream.addTrack(event.track);
      }
      if (_disposed) {
        await renderer.dispose();
        return;
      }
      renderer.srcObject = stream;
      final previous = _renderers[playerId];
      _renderers[playerId] = renderer;
      if (previous != null) {
        previous.srcObject = null;
        await previous.dispose();
      }
      onChanged();
    });
  }

  /// Per-player decoded-frame progress, keyed by the inbound-rtp's mid. A
  /// player whose picture stops is shown as unavailable (virtual board), not
  /// as a frozen frame.
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(mediaCheckInterval, (_) async {
      final pc = _pc;
      if (_disposed || pc == null) return;
      final now = DateTime.now();
      try {
        final stats = await pc.getStats().timeout(const Duration(seconds: 2));
        for (final report in stats) {
          if (report.type != 'inbound-rtp') continue;
          final values = report.values;
          final kind = values['kind'] ?? values['mediaType'];
          if (kind != 'video') continue;
          final mid = values['mid']?.toString();
          final trackId = values['trackIdentifier']?.toString();
          final playerId =
              (mid != null ? _midToPlayer[mid] : null) ??
              (trackId != null ? _trackToPlayer[trackId] : null);
          final decoded = values['framesDecoded'];
          if (playerId == null || decoded is! num) continue;
          final frames = decoded.toInt();
          final key = mid ?? trackId!;
          if (frames > 0 && frames != _framesByMid[key]) {
            _framesByMid[key] = frames;
            _progressByPlayer[playerId] = now;
          }
        }
      } catch (_) {
        return;
      }
      if (_disposed) return;
      var changed = false;
      for (final playerId in _midToPlayer.values) {
        final last = _progressByPlayer[playerId];
        final flowing =
            last != null && now.difference(last) < mediaStallTimeout;
        if (flowing != _flowing.contains(playerId)) {
          changed = true;
          flowing ? _flowing.add(playerId) : _flowing.remove(playerId);
        }
      }
      if (changed) onChanged();
    });
  }

  /// Diagnostics: the Cloudflare session this spectator holds.
  String? get sessionId => _sessionId;

  Future<void> _close(RTCPeerConnection pc) async {
    try {
      await pc.close().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      await pc.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _watchdog?.cancel();
    final pc = _pc;
    _pc = null;
    if (pc != null) await _close(pc);
    for (final renderer in _renderers.values) {
      try {
        renderer.srcObject = null;
        await renderer.dispose();
      } catch (_) {}
    }
    _renderers.clear();
    _flowing.clear();
  }
}

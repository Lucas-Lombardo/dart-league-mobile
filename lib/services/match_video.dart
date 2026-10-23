import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../models/rtc_v2_config.dart';
import '../widgets/board_safe_video.dart';
import 'p2p_match_video.dart';
import 'sfu_match_video.dart';
import 'socket_service.dart';

/// What the game screen needs from a match video transport. Two exist:
/// [P2pMatchVideo] (phone to phone, every app since 1.2.29) and
/// [SfuMatchVideo] (through Cloudflare Realtime, which also lets spectators
/// watch). The screen never picks one — [MatchVideo] does, from the server's
/// verdict.
abstract class MatchVideoTransport {
  bool get isRemoteReady;
  bool get isLinkUp;
  Widget? remoteView({ValueListenable<VideoZoomState>? zoom, double topInset});
  Future<void> start();
  Future<void> setMicEnabled(bool enabled);
  void onAppResumed();
  void onSocketReconnected();
  Future<void> stop();
  void stopDetached();
}

/// The match's video, whichever transport the server chose for the series.
///
/// The `rtcV2.sfu` block present → [SfuMatchVideo], else [P2pMatchVideo].
/// A series only ever moves Cloudflare → P2P, and ONLY on the server's word
/// (`video_transport_changed`, or a later payload whose `rtcV2` lost its
/// `sfu` block): when this app gives up on Cloudflare it asks the server
/// (`sfu_failed`), which switches both players together — a local switch
/// would leave the opponent alone on the other transport. The match itself
/// never pauses: only the video session is replaced.
class MatchVideo implements MatchVideoTransport {
  MatchVideo({
    required this.matchId,
    required this.opponentId,
    required this.configProvider,
    required this.onChanged,
  });

  /// Correlation key of every signaling request (leg 1's id for a series).
  final String matchId;
  final String opponentId;
  final RtcV2Config Function() configProvider;
  final VoidCallback onChanged;

  MatchVideoTransport? _active;
  bool _stopped = false;
  bool _switching = false;
  bool _micEnabled = false;
  bool _failureReported = false;
  Timer? _failureRetry;

  /// Which transport runs right now — 'sfu' or 'p2p' (diagnostics, tests).
  String get transport => _active is SfuMatchVideo ? 'sfu' : 'p2p';

  @override
  bool get isRemoteReady => _active?.isRemoteReady ?? false;

  @override
  bool get isLinkUp => _active?.isLinkUp ?? false;

  @override
  Widget? remoteView({
    ValueListenable<VideoZoomState>? zoom,
    double topInset = 0,
  }) => _active?.remoteView(zoom: zoom, topInset: topInset);

  @override
  Future<void> start() async {
    if (_stopped) return;
    SocketService.onShared(
      'video_transport_changed',
      _onTransportChanged,
      owner: this,
    );
    final config = configProvider();
    final MatchVideoTransport transport = config.usesSfu
        ? SfuMatchVideo(
            matchId: matchId,
            opponentId: opponentId,
            configProvider: configProvider,
            onChanged: onChanged,
            onFailed: _reportSfuFailure,
          )
        : _newP2p();
    debugPrint(
      'MatchVideo: starting on ${config.usesSfu ? 'Cloudflare' : 'P2P'}'
      '${config.sfu != null ? ' (series ${config.sfu!.seriesId})' : ''}',
    );
    _active = transport;
    if (_micEnabled) await transport.setMicEnabled(true);
    await transport.start();
  }

  P2pMatchVideo _newP2p() => P2pMatchVideo(
    matchId: matchId,
    opponentId: opponentId,
    configProvider: configProvider,
    onChanged: onChanged,
  );

  /// Cloudflare doesn't work for this phone: ask the server to move the
  /// series to P2P. Retried until acknowledged — the socket may be down, and
  /// both players must hear the verdict from the server.
  void _reportSfuFailure(String reason) {
    if (_stopped || _failureReported || _active is! SfuMatchVideo) return;
    _failureReported = true;
    debugPrint('MatchVideo: Cloudflare failed ($reason) — asking for P2P');
    SocketService.request('sfu_failed', {'matchId': matchId, 'reason': reason})
        .then((ack) {
          if (ack is Map && ack['transport'] == 'p2p') {
            _switchToP2p('sfu_failed');
          }
        })
        .catchError((Object e) {
          debugPrint('MatchVideo: sfu_failed not acknowledged: $e');
          _failureReported = false;
          _failureRetry?.cancel();
          _failureRetry = Timer(
            const Duration(seconds: 5),
            () => _reportSfuFailure(reason),
          );
        });
  }

  void _onTransportChanged(dynamic data) {
    if (_stopped || data is! Map || data['transport'] != 'p2p') return;
    final players = data['players'];
    if (players is List && !players.contains(opponentId)) return;
    _switchToP2p('server: ${data['reason'] ?? 'fallback'}');
  }

  /// Replace the Cloudflare session with the P2P one, camera and AI
  /// untouched (both transports feed on the same native track source).
  Future<void> _switchToP2p(String why) async {
    if (_stopped || _switching || _active is P2pMatchVideo) return;
    _switching = true;
    _failureRetry?.cancel();
    debugPrint('MatchVideo: switching to P2P ($why)');
    try {
      final old = _active;
      _active = null;
      onChanged();
      try {
        await old?.stop().timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('MatchVideo: Cloudflare stop failed: $e');
      }
      if (_stopped) return;
      final p2p = _newP2p();
      _active = p2p;
      if (_micEnabled) await p2p.setMicEnabled(true);
      onChanged();
      await p2p.start();
    } finally {
      _switching = false;
    }
    onChanged();
  }

  @override
  Future<void> setMicEnabled(bool enabled) async {
    _micEnabled = enabled;
    await _active?.setMicEnabled(enabled);
  }

  @override
  void onAppResumed() => _active?.onAppResumed();

  /// The screens call this when a sync proves the socket works again. A
  /// sync whose verdict lost the `sfu` block means the series fell back
  /// while we weren't listening (socket down, app backgrounded): follow it.
  @override
  void onSocketReconnected() {
    if (_active is SfuMatchVideo && !configProvider().usesSfu) {
      _switchToP2p('sync without sfu');
      return;
    }
    _active?.onSocketReconnected();
  }

  @override
  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _failureRetry?.cancel();
    SocketService.offShared('video_transport_changed', owner: this);
    final active = _active;
    _active = null;
    await active?.stop();
  }

  @override
  void stopDetached() {
    stop();
  }
}

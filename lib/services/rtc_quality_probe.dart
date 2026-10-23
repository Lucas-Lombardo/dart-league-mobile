import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Samples a match call's video quality from `getStats()` — what was really
/// sent and received (bitrate, resolution, fps, codec, what limited the
/// encoder) — so Cloudflare and P2P can be compared on picture, not feel.
/// Rides the end-of-call `rtc_v2_report` as `diagnostics.send/recv`.
///
/// Follows the transport's CURRENT PeerConnection through [pcProvider]: a
/// rebuild swaps it, and the byte counters restart with it.
class RtcQualityProbe {
  RtcQualityProbe(this.pcProvider);

  final RTCPeerConnection? Function() pcProvider;

  static const Duration sampleInterval = Duration(seconds: 5);
  // Bounded memory over a long match: ~25 min of samples.
  static const int _maxSamples = 300;

  Timer? _timer;
  bool _sampling = false;
  RTCPeerConnection? _pc;
  DateTime? _prevAt;
  int? _prevSentBytes;
  int? _prevRecvBytes;

  final List<int> _sendKbps = [];
  final List<int> _recvKbps = [];
  final List<double> _sendFps = [];
  final List<double> _recvFps = [];
  final List<int> _bweKbps = [];
  final List<int> _rttMs = [];
  final Map<String, int> _limits = {};
  int? _sendW, _sendH, _recvW, _recvH;
  String? _sendCodec, _recvCodec, _encoder, _decoder;
  int _recvPackets = 0, _recvLost = 0, _freezes = 0;

  void start() {
    _timer ??= Timer.periodic(sampleInterval, (_) => unawaited(sample()));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> sample() async {
    final pc = pcProvider();
    if (pc == null || _sampling) return;
    _sampling = true;
    try {
      if (!identical(pc, _pc)) {
        _pc = pc;
        _prevAt = null;
        _prevSentBytes = null;
        _prevRecvBytes = null;
      }
      final stats = await pc.getStats().timeout(const Duration(seconds: 2));
      final codecs = <String, String>{};
      for (final r in stats) {
        if (r.type == 'codec') {
          final mime = r.values['mimeType'];
          if (mime is String) codecs[r.id] = mime.split('/').last;
        }
      }
      var sentBytes = 0, recvBytes = 0;
      var hasSend = false, hasRecv = false;
      for (final r in stats) {
        final v = r.values;
        final kind = v['kind'] ?? v['mediaType'];
        if (r.type == 'outbound-rtp' && kind == 'video') {
          hasSend = true;
          sentBytes += _int(v['bytesSent']) ?? 0;
          _sendW = _int(v['frameWidth']) ?? _sendW;
          _sendH = _int(v['frameHeight']) ?? _sendH;
          final fps = _num(v['framesPerSecond']);
          if (fps != null) _sendFps.add(fps.toDouble());
          _sendCodec = codecs[v['codecId']] ?? _sendCodec;
          _encoder = v['encoderImplementation'] as String? ?? _encoder;
          final limit = v['qualityLimitationReason'];
          if (limit is String) _limits[limit] = (_limits[limit] ?? 0) + 1;
        } else if (r.type == 'inbound-rtp' && kind == 'video') {
          hasRecv = true;
          recvBytes += _int(v['bytesReceived']) ?? 0;
          _recvW = _int(v['frameWidth']) ?? _recvW;
          _recvH = _int(v['frameHeight']) ?? _recvH;
          final fps = _num(v['framesPerSecond']);
          if (fps != null) _recvFps.add(fps.toDouble());
          _recvCodec = codecs[v['codecId']] ?? _recvCodec;
          _decoder = v['decoderImplementation'] as String? ?? _decoder;
          _recvPackets = _int(v['packetsReceived']) ?? _recvPackets;
          _recvLost = _int(v['packetsLost']) ?? _recvLost;
          _freezes = _int(v['freezeCount']) ?? _freezes;
        } else if (r.type == 'candidate-pair' &&
            v['state'] == 'succeeded' &&
            v['nominated'] == true) {
          final bwe = _num(v['availableOutgoingBitrate']);
          if (bwe != null) _bweKbps.add(bwe ~/ 1000);
          final rtt = _num(v['currentRoundTripTime']);
          if (rtt != null) _rttMs.add((rtt * 1000).round());
        }
      }
      final now = DateTime.now();
      final prevAt = _prevAt;
      if (prevAt != null) {
        final secs = now.difference(prevAt).inMilliseconds / 1000;
        if (secs > 0) {
          if (hasSend && _prevSentBytes != null) {
            _sendKbps.add(
              ((sentBytes - _prevSentBytes!) * 8 / 1000 / secs).round(),
            );
          }
          if (hasRecv && _prevRecvBytes != null) {
            _recvKbps.add(
              ((recvBytes - _prevRecvBytes!) * 8 / 1000 / secs).round(),
            );
          }
        }
      }
      _prevAt = now;
      _prevSentBytes = hasSend ? sentBytes : null;
      _prevRecvBytes = hasRecv ? recvBytes : null;
      for (final list in <List>[
        _sendKbps,
        _recvKbps,
        _sendFps,
        _recvFps,
        _bweKbps,
        _rttMs,
      ]) {
        if (list.length > _maxSamples) list.removeAt(0);
      }
    } catch (_) {
      // Telemetry only: a failed sample is just a missing point.
    } finally {
      _sampling = false;
    }
  }

  /// Compact summary for the report (medians over the call; resolution and
  /// codec as last seen). Empty sides are left out.
  Map<String, dynamic> snapshot() {
    final send = <String, dynamic>{
      'kbps': ?_median(_sendKbps),
      'kbpsMax': ?_max(_sendKbps),
      'w': ?_sendW,
      'h': ?_sendH,
      'fps': ?_median(_sendFps)?.round(),
      'codec': ?_sendCodec,
      'enc': ?_encoder,
      'bweKbps': ?_median(_bweKbps),
      if (_limits.isNotEmpty) 'limits': Map.of(_limits),
    };
    final lossPct = _recvPackets + _recvLost > 0
        ? (_recvLost * 1000 / (_recvPackets + _recvLost)).round() / 10
        : null;
    final recv = <String, dynamic>{
      'kbps': ?_median(_recvKbps),
      'kbpsMax': ?_max(_recvKbps),
      'w': ?_recvW,
      'h': ?_recvH,
      'fps': ?_median(_recvFps)?.round(),
      'codec': ?_recvCodec,
      'dec': ?_decoder,
      'lossPct': ?lossPct,
      'freezes': _freezes,
    };
    return {
      if (send.isNotEmpty) 'send': send,
      if (_recvKbps.isNotEmpty || _recvW != null) 'recv': recv,
      'rttMs': ?_median(_rttMs),
      'samples': _sendKbps.length > _recvKbps.length
          ? _sendKbps.length
          : _recvKbps.length,
    };
  }

  static int? _int(Object? v) => v is num ? v.toInt() : null;
  static num? _num(Object? v) => v is num ? v : null;

  static T? _median<T extends num>(List<T> values) {
    if (values.isEmpty) return null;
    final sorted = List<T>.of(values)..sort();
    return sorted[sorted.length ~/ 2];
  }

  static int? _max(List<int> values) =>
      values.isEmpty ? null : values.reduce((a, b) => a > b ? a : b);
}

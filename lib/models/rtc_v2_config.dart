/// The `rtcV2` block of a credential-carrying match payload — the server's
/// verdict that BOTH players' sockets support P2P WebRTC for this match.
///
/// Presence of this object is the ONLY signal that the match has video at
/// all: P2P is the sole transport, so no block means no video, and there is
/// nothing to fall back to.
class RtcV2Config {
  const RtcV2Config({
    required this.iceServers,
    required this.polite,
    this.sfu,
  });

  /// Ready-to-use RTCPeerConnection `iceServers` list (Cloudflare TURN + STUN).
  final List<Map<String, dynamic>> iceServers;

  /// Perfect-negotiation role, decided server-side so both peers agree
  /// without a round-trip: the polite peer rolls back on offer glare.
  final bool polite;

  /// Present while the server runs this series over Cloudflare Realtime
  /// (both apps support it and the kill-switch is open). Null = P2P. A later
  /// payload whose `rtcV2` has no `sfu` means the series fell back to P2P —
  /// [adopt] replaces the whole config, so that verdict is picked up too.
  final SfuConfig? sfu;

  bool get usesSfu => sfu != null;

  /// Adopts a verdict carried by [payload], keeping [current] when the
  /// payload has none.
  ///
  /// Absence is NOT a denial: periodic syncs and partial payloads omit the
  /// block, and clearing on them would tear down a live P2P session. Only a
  /// NEW match may reset the verdict — that is the providers' job (`isNewMatch`
  /// in initGame, a changed matchId in the invite flow), not this one's.
  static RtcV2Config? adopt(dynamic payload, RtcV2Config? current) {
    if (payload is! Map) return current;
    return tryParse(payload['rtcV2']) ?? current;
  }

  /// Defensive parse of `payload['rtcV2']`. Null on anything malformed —
  /// callers treat null exactly like a payload with no block: no video.
  static RtcV2Config? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final servers = raw['iceServers'];
    if (servers is! List || servers.isEmpty) return null;
    final parsed = <Map<String, dynamic>>[];
    for (final s in servers) {
      if (s is Map) parsed.add(Map<String, dynamic>.from(s));
    }
    if (parsed.isEmpty) return null;
    return RtcV2Config(
      iceServers: parsed,
      polite: raw['polite'] == true,
      sfu: SfuConfig.tryParse(raw['sfu']),
    );
  }
}

/// The nested `rtcV2.sfu` block: this series' video goes through Cloudflare
/// Realtime. [seriesId] identifies the server-side series (diagnostics only:
/// every SFU request is keyed by the matchId, like the P2P relay).
class SfuConfig {
  const SfuConfig({required this.seriesId});

  final String seriesId;

  static SfuConfig? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['seriesId'];
    if (id is! String || id.isEmpty) return null;
    return SfuConfig(seriesId: id);
  }
}

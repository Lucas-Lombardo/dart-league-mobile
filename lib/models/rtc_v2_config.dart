/// The `rtcV2` block of a credential-carrying match payload — the server's
/// verdict that BOTH players' sockets support P2P WebRTC for this match.
///
/// Presence of this object is the ONLY signal that selects the P2P path,
/// and the selection is final: there is no Agora fallback. The Agora fields
/// emitted next to it only serve OLD clients (which don't see this block).
class RtcV2Config {
  const RtcV2Config({required this.iceServers, required this.polite});

  /// Ready-to-use RTCPeerConnection `iceServers` list (Cloudflare TURN + STUN).
  final List<Map<String, dynamic>> iceServers;

  /// Perfect-negotiation role, decided server-side so both peers agree
  /// without a round-trip: the polite peer rolls back on offer glare.
  final bool polite;

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
  /// callers treat null exactly like an old-style payload (Agora path).
  static RtcV2Config? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final servers = raw['iceServers'];
    if (servers is! List || servers.isEmpty) return null;
    final parsed = <Map<String, dynamic>>[];
    for (final s in servers) {
      if (s is Map) parsed.add(Map<String, dynamic>.from(s));
    }
    if (parsed.isEmpty) return null;
    return RtcV2Config(iceServers: parsed, polite: raw['polite'] == true);
  }
}

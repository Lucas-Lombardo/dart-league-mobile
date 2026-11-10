import 'package:flutter/foundation.dart';

import '../../services/api_service.dart';
import 'ghost_models.dart';

/// HTTP client of the ghost match (/ghost, CONTRACT.md §14.5). The server
/// owns everything that matters — which ghost, the score, the legs, the ELO:
/// the app posts its visits and replays what comes back.
class GhostService {
  GhostService._();

  /// The ghost proposed right now. Only asked from the ranked queue: the
  /// ghost is its fallback after 5 min without an opponent (CONTRACT §14.12),
  /// the server offers it nowhere else.
  static Future<GhostOfferResponse> offer() async {
    final fake = debugOffer;
    if (fake != null) return fake();
    final res = await ApiService.get('/ghost/offer?context=queue');
    return GhostOfferResponse.fromJson(res);
  }

  /// Replaces [offer] in tests.
  @visibleForTesting
  static Future<GhostOfferResponse> Function()? debugOffer;

  /// Starts the offered ghost; the server takes the player out of the
  /// ranked queue in the same step (`403 GHOST_QUEUE_ONLY` when they are no
  /// longer in it, e.g. a real opponent was found first).
  static Future<GhostMatchState> start(String offerId) async {
    final res = await ApiService.post('/ghost/matches', {'offerId': offerId});
    final match = GhostMatchState.fromJson(res);
    if (match == null) throw Exception('Bad ghost match payload');
    return match;
  }

  static Future<GhostMatchState?> active() async {
    final res = await ApiService.get('/ghost/active');
    return res is Map ? GhostMatchState.fromJson(res['match']) : null;
  }

  static Future<GhostMatchState> match(String id) async {
    final res = await ApiService.get('/ghost/matches/$id');
    final match = GhostMatchState.fromJson(res);
    if (match == null) throw Exception('Bad ghost match payload');
    return match;
  }

  static Future<GhostVisitResult> postVisit({
    required String matchId,
    required int leg,
    required int index,
    required List<GhostPostedDart> darts,
  }) async {
    final res = await ApiService.post('/ghost/matches/$matchId/visits', {
      'leg': leg,
      'index': index,
      'darts': darts.map((d) => d.toJson()).toList(),
    });
    final result = GhostVisitResult.fromJson(res);
    if (result == null) throw Exception('Bad ghost visit payload');
    return result;
  }

  static Future<GhostMatchState?> abandon(String matchId) async {
    try {
      final res = await ApiService.post('/ghost/matches/$matchId/abandon', {});
      return GhostMatchState.fromJson(res);
    } catch (e) {
      debugPrint('[Ghost] abandon failed: $e');
      return null;
    }
  }

  static Future<GhostDigest> digest() async =>
      GhostDigest.fromJson(await ApiService.get('/ghost/owner/digest'));

  static Future<void> markDigestSeen() async {
    try {
      await ApiService.post('/ghost/owner/digest/seen', {});
    } catch (e) {
      debugPrint('[Ghost] digest seen failed: $e');
    }
  }

  static Future<GhostSettings> settings() async =>
      GhostSettings.fromJson(await ApiService.get('/ghost/settings'));

  static Future<GhostSettings> updateSettings({bool? enabled, bool? notify}) async {
    final res = await ApiService.put('/ghost/settings', {
      'enabled': ?enabled,
      'notify': ?notify,
    });
    return GhostSettings.fromJson(res);
  }

  static Future<List<String>> pendingProofs() async {
    final res = await ApiService.get('/ghost/proof/pending');
    final ids = res is Map ? res['matchIds'] : null;
    return ids is List ? ids.whereType<String>().toList() : const [];
  }
}

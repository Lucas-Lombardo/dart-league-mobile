import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/progression.dart';
import '../utils/api_config.dart';
import 'api_service.dart';

/// Progression & rewards API — docs/progression/CONTRACT.md §8.
class ProgressionService {
  /// The content catalog. Null when the server says the cached [have]
  /// version is still current.
  static Future<Map<String, dynamic>?> fetchContentJson({String? have}) async {
    final query = have == null || have.isEmpty ? '' : '?have=${Uri.encodeQueryComponent(have)}';
    final response = await ApiService.get('/progression/content$query');
    if (response is! Map<String, dynamic>) throw Exception('Unexpected content response');
    if (response['unchanged'] == true) return null;
    return response;
  }

  static Future<ProgressionSummary> getMe() async =>
      ProgressionSummary.fromJson(await ApiService.get('/progression/me'));

  static Future<void> markLevelSeen(int level) async {
    await ApiService.post('/progression/me/level-seen', {'level': level});
  }

  static Future<XpFeed> getXpSince(DateTime since) async {
    final iso = Uri.encodeQueryComponent(since.toUtc().toIso8601String());
    return XpFeed.fromJson(await ApiService.get('/progression/me/xp?since=$iso'));
  }

  static Future<QuestsSnapshot> getQuests() async =>
      QuestsSnapshot.fromJson(await ApiService.get('/progression/quests'));

  /// Returns the refreshed daily section.
  static Future<QuestSection> reroll(String userQuestId) async =>
      QuestSection.fromJson(await ApiService.post('/progression/quests/$userQuestId/reroll', const {}));

  static Future<Inventory> getInventory() async =>
      Inventory.fromJson(await ApiService.get('/progression/inventory'));

  static Future<void> markSeen(List<String> itemIds) async {
    if (itemIds.isEmpty) return;
    await ApiService.post('/progression/inventory/seen', {'itemIds': itemIds});
  }

  static Future<Equipment> equip(EquipRequest request) async {
    final response = await ApiService.put('/progression/equipment', request.body);
    final m = response is Map ? response : const {};
    return Equipment.fromJson(m['equipment']);
  }

  /// Quest actions only the phone sees (camera set up, replay watched…).
  /// Never throws: a quest tick is not worth an error.
  static Future<void> reportClientAction(String action) async {
    try {
      await ApiService.post('/progression/client-events', {'action': action});
    } catch (e) {
      debugPrint('ProgressionService: client action "$action" not sent: $e');
    }
  }

  /// Rank + cosmetics of a few players (GET /progression/cosmetics?ids=),
  /// for the match screens. Unknown ids are absent from the map.
  static Future<Map<String, PlayerLook>> getPlayers(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final response = await ApiService.get('/progression/cosmetics?ids=${ids.map(Uri.encodeQueryComponent).join(',')}');
    final players = response is Map ? response['players'] : null;
    final out = <String, PlayerLook>{};
    if (players is Map) {
      players.forEach((id, value) {
        if (id is String && value is Map) {
          out[id] = PlayerLook(
            rank: value['rank'] is String ? value['rank'] as String : 'unranked',
            cosmetics: PublicCosmetics.fromJson(value['cosmetics']),
          );
        }
      });
    }
    return out;
  }
}

/// A player's rank and public cosmetics, as the match screens draw them.
class PlayerLook {
  final String rank;
  final PublicCosmetics? cosmetics;
  const PlayerLook({required this.rank, this.cosmetics});
}

/// The content JSON on disk, so the catalog renders offline and at launch.
class ProgressionContentCache {
  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/progression/content.json');
  }

  static Future<Map<String, dynamic>?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      debugPrint('ProgressionContentCache: unreadable cache: $e');
      return null;
    }
  }

  static Future<void> save(Map<String, dynamic> json) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(json), flush: true);
    } catch (e) {
      debugPrint('ProgressionContentCache: cannot save: $e');
    }
  }
}

/// Item visuals (SVG / WebP / PNG) downloaded once and kept on disk, keyed by
/// item id + content hash: a new hash is a new file (CONTRACT.md §10).
class ProgressionAssetCache {
  static final Map<String, Future<File?>> _inFlight = {};

  /// Tests and the PNG preview harnesses: a folder standing in for the app
  /// support directory (no path_provider in the test engine).
  @visibleForTesting
  static Directory? debugDirectory;

  static Future<File?> file(ItemAsset asset, String itemId) {
    final key = '$itemId.${asset.hash}.${asset.format}';
    return _inFlight.putIfAbsent(key, () => _load(asset, key));
  }

  static Future<File?> _load(ItemAsset asset, String key) async {
    try {
      final dir = debugDirectory ?? await getApplicationSupportDirectory();
      final file = File('${dir.path}/progression/assets/$key');
      if (await file.exists()) return file;
      final url = asset.url.startsWith('http') ? asset.url : '$baseUrl${asset.url}';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        _inFlight.remove(key);
        return null;
      }
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file;
    } catch (e) {
      debugPrint('ProgressionAssetCache: $key not loaded: $e');
      _inFlight.remove(key);
      return null;
    }
  }
}

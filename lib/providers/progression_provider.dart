import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/progression.dart';
import '../services/progression_service.dart';

/// Content catalog, my progression, quests and locker — CONTRACT.md §11.4.
/// Keeps the last good value on failure: a flaky network never blanks a card.
class ProgressionProvider extends ChangeNotifier {
  ProgressionContent? _content;
  ProgressionSummary? _summary;
  QuestsSnapshot? _quests;
  Inventory? _inventory;
  bool _bootstrapped = false;
  bool _busy = false;

  ProgressionContent? get content => _content;
  ProgressionSummary? get summary => _summary;
  QuestsSnapshot? get quests => _quests;
  Inventory? get inventory => _inventory;
  bool get isBusy => _busy;

  ItemDef? item(String? id) => _content?.item(id);

  // ---- Other players' looks (match screens), cached for the session ----
  final Map<String, PlayerLook> _players = {};
  final Set<String> _playersInFlight = {};

  /// The cached look of [userId], or null until [ensurePlayers] loaded it.
  PlayerLook? player(String? userId) => userId == null ? null : _players[userId];

  /// Loads the players not cached yet (one request); never throws.
  Future<void> ensurePlayers(Iterable<String?> userIds) async {
    final missing = userIds
        .whereType<String>()
        .where((id) => id.isNotEmpty && !_players.containsKey(id) && !_playersInFlight.contains(id))
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    _playersInFlight.addAll(missing);
    try {
      final loaded = await ProgressionService.getPlayers(missing);
      if (loaded.isNotEmpty) {
        _players.addAll(loaded);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('ProgressionProvider.ensurePlayers: $e');
    } finally {
      _playersInFlight.removeAll(missing);
    }
  }

  @visibleForTesting
  void debugSeedPlayer(String userId, PlayerLook look) {
    _players[userId] = look;
    notifyListeners();
  }

  /// True while the app owes the player a "Level up" screen.
  bool get hasUnseenLevelUp {
    final s = _summary;
    return s != null && s.level > s.levelSeen;
  }

  /// Content from disk first (instant), then network; then me + quests.
  Future<void> bootstrap() async {
    if (!_bootstrapped) {
      _bootstrapped = true;
      final cached = await ProgressionContentCache.load();
      if (cached != null && _content == null) {
        _content = ProgressionContent.fromJson(cached);
        notifyListeners();
      }
    }
    await Future.wait([refreshContent(), refreshSummary(), refreshQuests()]);
  }

  Future<void> refreshContent() async {
    try {
      final json = await ProgressionService.fetchContentJson(have: _content?.version);
      if (json == null) return;
      _content = ProgressionContent.fromJson(json);
      notifyListeners();
      unawaited(ProgressionContentCache.save(json));
    } catch (e) {
      debugPrint('ProgressionProvider.refreshContent: $e');
    }
  }

  Future<void> refreshSummary() async {
    try {
      _summary = await ProgressionService.getMe();
      notifyListeners();
    } catch (e) {
      debugPrint('ProgressionProvider.refreshSummary: $e');
    }
  }

  Future<void> refreshQuests() async {
    try {
      _quests = await ProgressionService.getQuests();
      notifyListeners();
    } catch (e) {
      debugPrint('ProgressionProvider.refreshQuests: $e');
    }
  }

  /// False when the server refused (reroll already used, quest finished…).
  Future<bool> reroll(String userQuestId) async {
    try {
      final daily = await ProgressionService.reroll(userQuestId);
      _quests = (_quests ?? const QuestsSnapshot()).withDaily(daily);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('ProgressionProvider.reroll: $e');
      return false;
    }
  }

  Future<void> refreshInventory() async {
    try {
      _inventory = await ProgressionService.getInventory();
      notifyListeners();
    } catch (e) {
      debugPrint('ProgressionProvider.refreshInventory: $e');
    }
  }

  Future<bool> equip(EquipRequest request) async {
    if (_busy) return false;
    _busy = true;
    notifyListeners();
    try {
      await ProgressionService.equip(request);
      await Future.wait([refreshSummary(), refreshInventory()]);
      return true;
    } catch (e) {
      debugPrint('ProgressionProvider.equip: $e');
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> markItemsSeen(List<String> itemIds) async {
    try {
      await ProgressionService.markSeen(itemIds);
    } catch (e) {
      debugPrint('ProgressionProvider.markItemsSeen: $e');
    }
  }

  /// XP earned since [since]. XP is awarded asynchronously after a match, so
  /// this retries (0 s, 1.5 s, 3 s) until [expectRefId] appears.
  Future<XpFeed?> waitForXp(DateTime since, {String? expectRefId}) async {
    XpFeed? feed;
    for (final delay in const [0, 1500, 1500]) {
      if (delay > 0) await Future<void>.delayed(Duration(milliseconds: delay));
      try {
        feed = await ProgressionService.getXpSince(since);
        if (expectRefId == null || feed.entries.any((e) => e.refId == expectRefId)) break;
      } catch (e) {
        debugPrint('ProgressionProvider.waitForXp: $e');
      }
    }
    if (feed != null) {
      _summary = feed.progression;
      notifyListeners();
      unawaited(refreshQuests());
    }
    return feed;
  }

  Future<void> markLevelSeen(int level) async {
    final s = _summary;
    if (s != null && level > s.levelSeen) {
      _summary = ProgressionSummary(
        level: s.level,
        xpTotal: s.xpTotal,
        xpIntoLevel: s.xpIntoLevel,
        xpToNext: s.xpToNext,
        levelSeen: level,
        isPremium: s.isPremium,
        nextRewards: s.nextRewards,
        itemsOwned: s.itemsOwned,
        itemsTotal: s.itemsTotal,
        equipment: s.equipment,
        cosmetics: s.cosmetics,
      );
      notifyListeners();
    }
    try {
      await ProgressionService.markLevelSeen(level);
    } catch (e) {
      debugPrint('ProgressionProvider.markLevelSeen: $e');
    }
  }

  void reset() {
    _summary = null;
    _quests = null;
    _inventory = null;
    notifyListeners();
  }

  @visibleForTesting
  void debugSeed({
    ProgressionContent? content,
    ProgressionSummary? summary,
    QuestsSnapshot? quests,
    Inventory? inventory,
  }) {
    _content = content ?? _content;
    _summary = summary ?? _summary;
    _quests = quests ?? _quests;
    _inventory = inventory ?? _inventory;
    _bootstrapped = true;
    notifyListeners();
  }
}

/// The provider when it is in the tree, else null — for widgets that also
/// render in tests or previews built without it.
ProgressionProvider? maybeWatchProgression(BuildContext context) {
  try {
    return context.watch<ProgressionProvider>();
  } on ProviderNotFoundException {
    return null;
  }
}

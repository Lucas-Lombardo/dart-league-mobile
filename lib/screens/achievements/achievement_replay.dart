import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/api_service.dart';
import '../../services/replay_clips_store.dart';
import '../profile/replay_player_screen.dart';

/// "Revoir la fléchette": the replay that already exists for the match, when
/// the player captured one — the clip of this session first (it is on the
/// phone), else their cloud library. Nothing is recorded for achievements.
class AchievementReplay {
  /// A clip of this match is on the phone (the button can show right away).
  static bool hasLocal(String? matchId) => matchId != null && ReplayClipsStore.forMatch(matchId).isNotEmpty;

  /// Opens the clip of [matchId] (the one of the visit worth [value] when
  /// several), or says there is none. True when a clip was opened.
  static Future<bool> open(BuildContext context, {required String matchId, double? value}) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    final local = ReplayClipsStore.forMatch(matchId);
    if (local.isNotEmpty) {
      final clip = local.firstWhere((c) => value != null && c.turnTotal == value.round(), orElse: () => local.first);
      await nav.push(MaterialPageRoute(builder: (_) => ReplayPlayerScreen(source: clip.path, isLocal: true)));
      return true;
    }
    try {
      final response = await ApiService.get('/replays/mine?limit=50');
      final clips = (response is Map && response['clips'] is List) ? response['clips'] as List : const [];
      final mine = clips.whereType<Map>().where((c) => c['matchId'] == matchId && c['url'] is String).toList();
      if (mine.isNotEmpty) {
        final clip = mine.firstWhere(
          (c) => value != null && c['turnTotal'] is num && (c['turnTotal'] as num).round() == value.round(),
          orElse: () => mine.first,
        );
        await nav.push(
          MaterialPageRoute(builder: (_) => ReplayPlayerScreen(source: clip['url'] as String, isLocal: false)),
        );
        return true;
      }
    } catch (e) {
      debugPrint('AchievementReplay: library not loaded: $e');
    }
    messenger?.showSnackBar(SnackBar(content: Text(l10n.achievementNoReplay)));
    return false;
  }
}

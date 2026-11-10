import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/matchmaking_provider.dart';
import '../../providers/progression_provider.dart';
import '../../services/auto_scoring_service.dart';
import '../../utils/rank_utils.dart';
import '../../widgets/matchmaking_navigation_gate.dart';
import '../progression/match_found_screen.dart';
import 'ghost_match_screen.dart';
import 'ghost_models.dart';
import 'ghost_service.dart';
import 'ghost_widgets.dart';

/// Accepting a ghost from the ranked queue (CONTRACT §14.12): start the
/// match on the server — which takes the player out of the queue in the same
/// step — then stop the local search and show the same 6 s "Match found"
/// screen as ranked (opponent labelled "Fantôme", the ghost match's ELO
/// stakes) through [MatchmakingNavigationGate], then the match.
///
/// The real match always wins: if an opponent was paired first, the server
/// refuses the ghost (`GHOST_QUEUE_ONLY`) and the gate is already on its way
/// to the real match; nothing is shown.
class GhostLauncher {
  GhostLauncher._();

  static bool _launching = false;

  /// How long a `GHOST_QUEUE_ONLY` refusal waits for the real match's
  /// `match_found` before telling the player the ghost is gone.
  @visibleForTesting
  static Duration realMatchGrace = const Duration(seconds: 2);

  /// Returns false when nothing was opened (error already shown, or a real
  /// match is on its way).
  static Future<bool> launch(BuildContext context, GhostOffer offer) async {
    if (_launching) return false;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!AutoScoringService.isSupported) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.ghostCameraRequired)));
      return false;
    }
    final auth = context.read<AuthProvider>();
    final matchmaking = context.read<MatchmakingProvider>();
    final me = auth.currentUser;
    final myCosmetics = maybeWatchProgressionRead(context)?.summary?.cosmetics ?? me?.cosmetics;
    final subtitle = l10n.ghostMatchFoundSubtitle(offer.bestOf);
    final record = l10n.ghostMatchFoundRecord(
      ghostShortDate(context, offer.ghost.playedAt),
      ghostAverage(context, offer.ghost.average),
    );
    _launching = true;
    try {
      // A real opponent already found: the real match wins.
      if (matchmaking.matchFound) return false;

      GhostMatchState? match;
      try {
        match = await GhostService.start(offer.id);
      } catch (e) {
        match = await _startedAnyway(e);
        if (match == null) {
          if (await _realMatchComing(e, matchmaking)) return false;
          messenger?.showSnackBar(SnackBar(content: Text(ghostErrorMessage(l10n, e))));
          return false;
        }
      }
      if (matchmaking.matchFound) {
        // Cannot happen once the server took us out of the queue; free cancel.
        await GhostService.abandon(match.id);
        return false;
      }
      // Out of the queue on the server already: stop the search here.
      matchmaking.endSearchForGhost();

      final started = match;
      // The started match is the truth (null when it doesn't count for ELO);
      // the offer only fills a gap.
      final countsForElo = started.eloEligible;
      final opened = await MatchmakingNavigationGate.openGhostMatch(
        matchFound: MatchFoundScreen(
          subtitle: subtitle,
          isGhost: true,
          recordLine: record,
          seconds: MatchFoundScreen.defaultSeconds,
          eloIfWin: countsForElo ? (started.eloIfWin ?? offer.eloIfWin) : null,
          eloIfLoss: countsForElo ? (started.eloIfLoss ?? offer.eloIfLoss) : null,
          me: MatchFoundPlayer(
            username: me?.username ?? '',
            rank: me?.rank ?? 'unranked',
            elo: me?.elo,
            cosmetics: myCosmetics,
            isPremium: me?.isPremiumActive ?? false,
          ),
          opponent: MatchFoundPlayer(
            username: offer.ghost.username,
            rank: rankFromElo(offer.ghost.elo),
            elo: offer.ghost.elo,
            cosmetics: offer.ghost.cosmetics,
          ),
        ),
        destination: (_) => GhostMatchScreen(initial: started),
      );
      if (!opened) {
        // Nothing was played: the server cancels it at no cost, and the
        // player goes back to searching a real opponent.
        await GhostService.abandon(started.id);
        if (me != null) unawaited(matchmaking.joinQueue(me.id));
      }
      return opened;
    } finally {
      _launching = false;
    }
  }

  /// The start failed without an answer from the server (network): it may
  /// have started all the same (and taken us out of the queue). A refusal
  /// from the server started nothing.
  static Future<GhostMatchState?> _startedAnyway(Object error) async {
    final s = error.toString();
    const refusals = ['GHOST_', 'OFFER_', 'PLACEMENT_REQUIRED', 'DAILY_MATCH_LIMIT_REACHED'];
    if (refusals.any(s.contains)) return null;
    try {
      return await GhostService.active();
    } catch (_) {
      return null;
    }
  }

  /// `GHOST_QUEUE_ONLY` while searching: most likely a real opponent was
  /// paired a moment before — its `match_found` follows. True when it came.
  static Future<bool> _realMatchComing(Object error, MatchmakingProvider matchmaking) async {
    if (matchmaking.matchFound) return true;
    if (!error.toString().contains('GHOST_QUEUE_ONLY')) return false;
    final until = DateTime.now().add(realMatchGrace);
    while (!matchmaking.matchFound && DateTime.now().isBefore(until)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return matchmaking.matchFound;
  }
}

/// [ProgressionProvider] when one is mounted (tests may not have it).
ProgressionProvider? maybeWatchProgressionRead(BuildContext context) {
  try {
    return context.read<ProgressionProvider>();
  } on ProviderNotFoundException {
    return null;
  }
}

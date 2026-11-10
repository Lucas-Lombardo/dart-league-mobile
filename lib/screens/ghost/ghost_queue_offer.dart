import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../providers/subscription_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/progression/player_showcase_card.dart';
import '../settings/subscription_screen.dart';
import 'ghost_launcher.dart';
import 'ghost_models.dart';
import 'ghost_service.dart';
import 'ghost_widgets.dart';

/// `defs.ghost` → `params` (GET /progression/content), null without it.
Map? _ghostParams(ProgressionContent? content) {
  final defs = content?.raw['defs'];
  final ghost = defs is Map ? defs['ghost'] : null;
  if (ghost is! List) return null;
  for (final d in ghost) {
    if (d is Map && d['id'] == 'params') return d;
  }
  return null;
}

/// The queue delay the server serves (GET /progression/content →
/// defs.ghost → params.queueDelaySec), [kGhostQueueDelay] without it.
int ghostQueueDelayOf(ProgressionContent? content) {
  final v = _ghostParams(content)?['queueDelaySec'];
  return v is num && v > 0 ? v.toInt() : kGhostQueueDelay;
}

/// XP of a ghost match: `content.xp.ghost` (what the server pays, from
/// `defs/ghost.json` → `matchXp`), else `defs.ghost` → `params.matchXp`;
/// null leaves it out of the button.
int? ghostMatchXpOf(ProgressionContent? content) {
  final served = content?.xp?.ghost;
  if (served != null && served > 0) return served;
  final v = _ghostParams(content)?['matchXp'];
  return v is num && v > 0 ? v.toInt() : null;
}

/// The ghost as the ranked queue's fallback (CONTRACT §14.12, card B of
/// mockups FgBp / FgBg). Owned by `MatchmakingScreen`, fed every second
/// with the search time ([tick]):
/// - after [delaySec] (5 min) of searching, asks the server once;
/// - premium, an offer → [showCard]: the ghost's card, « Jouer +40 XP » or
///   « Attendre »;
/// - free, a [preview] → the same card blurred behind a lock, « Premium »
///   (the subscription screen, [upgrade]) or « Attendre ». Becoming premium
///   (back from it, or any other way) asks again: the real offer, card open;
/// - « Attendre » ([keepWaiting]) folds the card into a small link at the
///   bottom of the screen ([showLink]) for the rest of the search; the link
///   unfolds it again ([expand]);
/// - nothing to show (no ghost in the band, a match already running…):
///   nothing, the search goes on. The server's « not yet » (`queue_wait`,
///   the queue join came a little after the search started) is asked again.
class GhostQueueOfferController extends ChangeNotifier {
  GhostQueueOfferController({this.delaySec = kGhostQueueDelay});

  /// Seconds of searching before the ghost is offered.
  int delaySec;

  static const int _maxAttempts = 4;
  static const int _retryAfterErrorSec = 30;

  /// Became premium but the server still answers `premium` (its view of the
  /// purchase lags a little): asked again this often, this many times.
  static const int _upgradeRetrySec = 5;
  static const int _maxUpgradeTries = 3;

  /// Replaces the subscription screen in tests.
  @visibleForTesting
  static Future<void> Function(BuildContext context)? debugOpenPremium;

  GhostOfferResponse? _response;
  bool _inFlight = false;
  bool _gaveUp = false;
  bool _collapsed = false;
  bool _launching = false;
  bool _upgrading = false;
  bool _closed = false;
  bool _disposed = false;
  int _attempts = 0;
  int _upgradeTries = 0;
  int? _nextAskAt;
  int? _upgradeAskAt;
  int _lastSeconds = 0;

  GhostOffer? get offer {
    final res = _response;
    if (_closed || res == null || !res.available) return null;
    return res.offer;
  }

  /// A free player's ghost (the locked card); null once there is an offer.
  GhostPreview? get preview {
    final res = _response;
    if (_closed || res == null || res.available) return null;
    return res.preview;
  }

  /// The card is the free player's: blurred, a lock, « Premium ».
  bool get locked => offer == null && preview != null;

  bool get _hasCard => offer != null || preview != null;
  bool get showCard => _hasCard && !_collapsed;
  bool get showLink => _hasCard && _collapsed;
  bool get launching => _launching;

  /// The search clock moved. Never notifies synchronously (called from a
  /// build): only the server's answer does.
  void tick({required int searchSeconds, required bool premium, int? delaySec}) {
    _lastSeconds = searchSeconds;
    if (delaySec != null && delaySec > 0 && _attempts == 0) this.delaySec = delaySec;
    if (premium && locked) {
      _askAsPremium();
      return;
    }
    if (_inFlight || _gaveUp || _closed || _hasCard) return;
    if (searchSeconds < (_nextAskAt ?? this.delaySec)) return;
    _ask();
  }

  /// The locked card while the player is premium now: the real offer.
  void _askAsPremium() {
    if (_inFlight || !locked || _upgradeTries >= _maxUpgradeTries) return;
    final at = _upgradeAskAt;
    if (at != null && _lastSeconds < at) return;
    _upgradeTries++;
    _ask();
  }

  Future<void> _ask() async {
    _inFlight = true;
    _attempts++;
    final wasLocked = locked;
    try {
      final res = await GhostService.offer();
      if (_disposed) return;
      if ((res.available && res.offer != null) || res.preview != null) {
        _response = res;
        if (wasLocked && res.offer != null) {
          // Became premium: the premium card, open.
          _collapsed = false;
        } else if (wasLocked) {
          _upgradeAskAt = _lastSeconds + _upgradeRetrySec;
        }
        notifyListeners();
        return;
      }
      if (_response != null) {
        // The locked card has nothing behind it any more.
        _response = null;
        notifyListeners();
      }
      final retry = switch (res.reason) {
        // Not long enough in the queue for the server yet: ask again then.
        GhostUnavailable.queueWait => (res.retryInSec ?? 5).clamp(1, 60),
        // The queue join is not on the server yet (socket coming back).
        GhostUnavailable.queueOnly => _retryAfterErrorSec,
        _ => null,
      };
      _scheduleOrGiveUp(retry);
    } catch (_) {
      // A network hiccup: the queue goes on, one more try a bit later.
      if (_disposed) return;
      if (wasLocked) {
        _upgradeAskAt = _lastSeconds + _upgradeRetrySec;
      } else {
        _scheduleOrGiveUp(_retryAfterErrorSec);
      }
    } finally {
      _inFlight = false;
    }
  }

  void _scheduleOrGiveUp(int? retryInSec) {
    if (retryInSec == null || _attempts >= _maxAttempts) {
      _gaveUp = true;
      return;
    }
    _nextAskAt = _lastSeconds + retryInSec;
  }

  /// « Attendre »: the card folds into the bottom link.
  void keepWaiting() {
    if (_collapsed) return;
    _collapsed = true;
    notifyListeners();
  }

  /// The bottom link: the card again. An offer past its time is asked anew.
  void expand() {
    if (!_collapsed) return;
    _collapsed = false;
    final expiresAt = offer?.expiresAt;
    if (expiresAt != null && !expiresAt.isAfter(DateTime.now())) {
      _response = null;
      _attempts = 0;
      _gaveUp = false;
      _nextAskAt = _lastSeconds;
    }
    notifyListeners();
    if (_response == null) _ask();
  }

  /// « Jouer »: the launcher (the real match wins). When nothing opened,
  /// the proposal goes away for this search.
  Future<void> play(BuildContext context) async {
    final o = offer;
    if (o == null || _launching) return;
    _launching = true;
    notifyListeners();
    final opened = await GhostLauncher.launch(context, o);
    if (_disposed) return;
    _launching = false;
    if (!opened) _closed = true;
    notifyListeners();
  }

  /// « Premium »: the subscription screen over the queue — the search goes
  /// on under it, like « S'entraîner en attendant ». Back as a premium
  /// player: the offer is asked at once and shown open.
  Future<void> upgrade(BuildContext context) async {
    if (_upgrading || !locked) return;
    _upgrading = true;
    try {
      final open = debugOpenPremium ?? _openSubscription;
      await open(context);
      if (_disposed || !context.mounted) return;
      SubscriptionProvider? subscription;
      try {
        subscription = context.read<SubscriptionProvider>();
      } on ProviderNotFoundException {
        subscription = null;
      }
      await subscription?.refresh();
      if (_disposed || subscription == null || !subscription.isPremiumActive) return;
      _upgradeTries = 0;
      _upgradeAskAt = null;
      _askAsPremium();
    } finally {
      _upgrading = false;
    }
  }

  static Future<void> _openSubscription(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SubscriptionScreen()));

  @visibleForTesting
  void debugSeed(GhostOfferResponse response, {bool collapsed = false}) {
    _response = response;
    _collapsed = collapsed;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Card B (mockups FgBp / FgBg, `b_card` of docs/progression/svg/
/// gen_fantome2.py), under the search card: « PERSONNE DEPUIS 5 MIN », the
/// ghost's player card (S1) faded with a « FANTÔME » chip, « Ses vraies
/// fléchettes, rejouées », then « Jouer +40 XP » and « Attendre ». A free
/// player gets the same card blurred behind a gold lock, and « Premium »
/// instead of « Jouer ». Nothing else: the ELO at stake is on Match trouvé.
class GhostQueueOfferCard extends StatelessWidget {
  final GhostQueueOfferController controller;

  /// XP of a ghost match ([ghostMatchXpOf]); null leaves it out of the button.
  final int? xp;

  const GhostQueueOfferCard({super.key, required this.controller, this.xp});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.showCard) return const SizedBox.shrink();
        final offer = controller.offer;
        final preview = controller.preview;
        final l10n = AppLocalizations.of(context);
        final minutes = (controller.delaySec / 60).round().clamp(1, 60);
        final showcase = offer != null
            ? GhostQueueShowcase(
                username: offer.ghost.username,
                rank: offer.ghost.rank,
                cosmetics: offer.ghost.cosmetics,
              )
            : GhostQueueShowcase(
                username: preview!.username,
                rank: preview.rank,
                cosmetics: preview.cosmetics,
                locked: true,
              );
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.ghostQueueNobody(minutes).toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              showcase,
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const GhostReplayIcon(),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      l10n.ghostQueueReplayed,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: offer != null
                        ? _PlayButton(
                            label: l10n.ghostQueuePlay,
                            xp: xp == null ? null : l10n.homeXpGain(xp!),
                            busy: controller.launching,
                            onTap: () => controller.play(context),
                          )
                        : _PremiumButton(label: l10n.ghostQueuePremium, onTap: () => controller.upgrade(context)),
                  ),
                  const SizedBox(width: 8),
                  _WaitButton(
                    label: l10n.ghostQueueWait,
                    onTap: controller.launching ? null : controller.keepWaiting,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The ghost's player card (S1, `ghost_card` of gen_fantome2.py), without
/// « Modifier » nor XP bar: at 62 % with a « FANTÔME » chip top left; when
/// [locked], blurred and partly greyed at 50 % under a gold lock.
class GhostQueueShowcase extends StatelessWidget {
  final String username;
  final String rank;
  final PublicCosmetics? cosmetics;
  final bool locked;

  const GhostQueueShowcase({
    super.key,
    required this.username,
    required this.rank,
    this.cosmetics,
    this.locked = false,
  });

  /// CSS `grayscale(.35)` (Filter Effects spec, s = 0.65).
  static const List<double> _grayscale35 = [
    0.72441, 0.25032, 0.02527, 0, 0, //
    0.07441, 0.90032, 0.02527, 0, 0, //
    0.07441, 0.25032, 0.67527, 0, 0, //
    0, 0, 0, 1, 0, //
  ];

  @override
  Widget build(BuildContext context) {
    final card = PlayerShowcaseCard(
      username: username,
      // The rank badge stands in for a missing avatar, never a wrong one.
      rank: rank == 'unranked' || rank.isEmpty ? null : rank,
      cosmetics: cosmetics,
    );
    final Widget faded = locked
        ? ExcludeSemantics(
            child: Opacity(
              opacity: 0.5,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5, tileMode: TileMode.decal),
                child: ColorFiltered(colorFilter: const ColorFilter.matrix(_grayscale35), child: card),
              ),
            ),
          )
        : Opacity(opacity: 0.62, child: card);
    return Stack(
      children: [
        faded,
        const Positioned(left: 10, top: 10, child: _GhostChip()),
        if (locked) const Positioned.fill(child: Center(child: GhostQueueLock())),
      ],
    );
  }
}

/// « FANTÔME » on the ghost's card: dark pill, blue hairline, ghost glyph.
class _GhostChip extends StatelessWidget {
  const _GhostChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xD90A0E18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.playerBlueBright),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const GhostIcon(size: 13, color: AppTheme.playerBlueBright),
          const SizedBox(width: 6),
          Text(
            AppLocalizations.of(context).ghostBadge,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              height: 1.2,
              color: AppTheme.playerBlueBright,
            ),
          ),
        ],
      ),
    );
  }
}

/// The gold lock over a free player's ghost card: 44 pt dark disc, gold rim.
class GhostQueueLock extends StatelessWidget {
  const GhostQueueLock({super.key});

  static const String _svg = '<svg viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2" '
      'stroke-linecap="round" stroke-linejoin="round"><rect width="18" height="11" x="3" y="11" rx="2"/>'
      '<path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context).ghostQueueLocked,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xD90A0E18),
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.accent, width: 1.5),
        ),
        child: SvgPicture.string(
          _svg,
          width: 20,
          height: 20,
          colorFilter: const ColorFilter.mode(Color(0xFFFDE68A), BlendMode.srcIn),
        ),
      ),
    );
  }
}

/// The replay glyph of the mockups (a circling arrow around a play
/// triangle), in the light blue.
class GhostReplayIcon extends StatelessWidget {
  final double size;
  const GhostReplayIcon({super.key, this.size = 18});

  static const String _svg = '<svg viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2" '
      'stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7L3 8"/>'
      '<path d="M3 3v5h5"/><path d="m10 9 5 3-5 3z"/></svg>';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      _svg,
      width: size,
      height: size,
      colorFilter: const ColorFilter.mode(AppTheme.playerBlueBright, BlendMode.srcIn),
    );
  }
}

const _buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(14)));

/// « Jouer +40 XP »: the blue button, it takes the room.
class _PlayButton extends StatelessWidget {
  final String label;
  final String? xp;
  final bool busy;
  final VoidCallback onTap;
  const _PlayButton({required this.label, required this.xp, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryLight,
          foregroundColor: AppTheme.background,
          disabledBackgroundColor: AppTheme.primaryLight,
          disabledForegroundColor: AppTheme.background,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 52),
          shape: _buttonShape,
          elevation: 0,
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.background),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.background),
                    ),
                  ),
                  if (xp != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      xp!,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0C4A6E)),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// « Premium »: the gold outline with its crown (the one gold of the card).
class _PremiumButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PremiumButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFFDE68A),
          side: const BorderSide(color: AppTheme.accent, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: const Size(0, 52),
          shape: _buttonShape,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PremiumCrown(size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFFFDE68A)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// « Attendre »: the narrow outlined button next to the main one.
class _WaitButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _WaitButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textPrimary,
          side: const BorderSide(color: AppTheme.surfaceLight, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          minimumSize: const Size(0, 52),
          shape: _buttonShape,
        ),
        child: Text(
          label,
          maxLines: 1,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// « Jouer contre un fantôme », the folded card: a small link at the bottom
/// of the queue screen for the rest of the search, to change one's mind.
/// A small crown on a free player's (the card behind it is locked).
class GhostQueueLink extends StatelessWidget {
  final GhostQueueOfferController controller;
  const GhostQueueLink({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.showLink) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context);
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SizedBox(
            height: 40,
            child: TextButton.icon(
              onPressed: controller.expand,
              style: TextButton.styleFrom(foregroundColor: AppTheme.playerBlueBright),
              icon: const GhostIcon(size: 16, color: AppTheme.playerBlueBright),
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      l10n.ghostPlayButton,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (controller.locked) ...[
                    const SizedBox(width: 6),
                    PremiumCrown(size: 14, semanticLabel: l10n.premiumBadgeLabel),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

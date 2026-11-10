import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/push_notification_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import 'ghost_digest_screen.dart';
import 'ghost_match_screen.dart';
import 'ghost_models.dart';
import 'ghost_proof_uploader.dart';
import 'ghost_service.dart';
import 'ghost_widgets.dart';

/// What the home knows about the ghost: a match to resume and the owner's
/// digest. Loaded and shown by [GhostHomeRows] (mounted with the Play tab).
/// Silent until the server answers (nothing shows on a backend without
/// /ghost).
class GhostHomeStore extends ChangeNotifier {
  GhostHomeStore._();
  static final GhostHomeStore instance = GhostHomeStore._();

  bool _loaded = false;
  GhostMatchState? _active;
  GhostDigest? _digest;

  bool get loaded => _loaded;
  GhostMatchState? get active => _active;
  GhostDigest? get digest => _digest;

  Future<void> load() async {
    try {
      final results = await Future.wait([GhostService.active(), GhostService.digest()]);
      _active = results[0] as GhostMatchState?;
      _digest = results[1] as GhostDigest;
      _loaded = true;
      notifyListeners();
    } catch (_) {
      // Backend without /ghost: nothing to resume, no digest.
    }
  }

  /// A new session (log in as someone else): forget the last player's ghost.
  void reset() {
    _loaded = false;
    _active = null;
    _digest = null;
    notifyListeners();
  }

  @visibleForTesting
  void debugSeed({GhostMatchState? active, GhostDigest? digest}) {
    _loaded = true;
    _active = active;
    _digest = digest;
    notifyListeners();
  }
}

/// The ghost on the Play tab (CONTRACT §14.12: no way to START a ghost from
/// here any more, only the ranked queue offers one):
/// - « Reprendre le match fantôme » when a match is in progress (always,
///   premium lapsed or not);
/// - the owner's row « Ton fantôme a joué N fois » when games are waiting to
///   be seen (other players against MY ghost).
/// Nothing otherwise. Also loads [GhostHomeStore], opens the digest from its
/// push (warm or cold start), and sends the pending proof videos.
class GhostHomeRows extends StatefulWidget {
  const GhostHomeRows({super.key});

  @override
  State<GhostHomeRows> createState() => _GhostHomeRowsState();
}

class _GhostHomeRowsState extends State<GhostHomeRows> {
  @override
  void initState() {
    super.initState();
    PushNotificationService.addOpenedListener(_onPushOpened);
    // App killed, then opened by the digest push: claim the launch tap the
    // listeners registered before this row already consumed (once).
    final launch = PushNotificationService.claimLaunchData((d) => d['type'] == 'ghost_digest');
    if (launch != null) _onPushOpened(launch);
    GhostHomeStore.instance.load();
    GhostProofUploader.uploadPending();
  }

  @override
  void dispose() {
    PushNotificationService.removeOpenedListener(_onPushOpened);
    super.dispose();
  }

  /// "Your ghost played N times" push tap → the digest screen.
  void _onPushOpened(Map<String, dynamic> data) {
    if (data['type'] != 'ghost_digest' || !mounted) return;
    PushNotificationService.markHandled(data);
    // Never navigate in the middle of a build: after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GhostDigestScreen()));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openDigest(GhostDigest digest) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GhostDigestScreen(initial: digest)));
    if (mounted) await GhostHomeStore.instance.load();
  }

  Future<void> _resume(GhostMatchState active) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GhostMatchScreen(initial: active)));
    if (mounted) await GhostHomeStore.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GhostHomeStore.instance,
      builder: (context, _) {
        final active = GhostHomeStore.instance.active;
        final digest = GhostHomeStore.instance.digest;
        final hasDigest = digest != null && !digest.isEmpty;
        if (active == null && !hasDigest) return const SizedBox.shrink();
        final l10n = AppLocalizations.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (active != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _Row(
                  title: l10n.ghostResume,
                  subtitle: '${l10n.ghostVs(active.ghost.username)} · ${active.playerLegsWon} – ${active.ghostLegsWon}',
                  onTap: () => _resume(active),
                  accent: true,
                ),
              ),
            if (hasDigest)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _Row(
                  title: l10n.ghostDigestTitle(digest.count),
                  subtitle: l10n.ghostDigestRowSubtitle(digest.ghostWins, digest.xp),
                  onTap: () => _openDigest(digest),
                  accent: true,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The owner's digest row (accent ghost, title, subtitle, chevron).
class _Row extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool accent;

  const _Row({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
        onTap: onTap,
        child: Row(
          children: [
            GhostIcon(size: 20, color: accent ? AppTheme.playerBlueBright : const Color(0xFFE2E8F0)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(dsSentence(title), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.rowTitle),
                  const SizedBox(height: 3),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.caption),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}

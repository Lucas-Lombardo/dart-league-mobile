import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../profile/player_stats_screen.dart';
import 'ghost_models.dart';
import 'ghost_service.dart';
import 'ghost_widgets.dart';

/// "Your ghost played 3 times" (mockup FantomeNuit): what the owner's ghost
/// did while they were away. Opening it marks those games as seen. The ELO
/// never moved — only the owner XP (20 per ghost win, 3 a day) did.
class GhostDigestScreen extends StatefulWidget {
  final GhostDigest? initial;
  const GhostDigestScreen({super.key, this.initial});

  @override
  State<GhostDigestScreen> createState() => _GhostDigestScreenState();
}

class _GhostDigestScreenState extends State<GhostDigestScreen> {
  GhostDigest? _digest;

  @override
  void initState() {
    super.initState();
    _digest = widget.initial;
    if (_digest == null) {
      GhostService.digest().then((d) {
        if (mounted) setState(() => _digest = d);
      }).catchError((Object _) {
        if (mounted) setState(() => _digest = const GhostDigest());
      });
    }
    GhostService.markDigestSeen();
  }

  void _openProfile(String userId, String username) {
    if (userId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PlayerStatsScreen(userId: userId, username: username)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final d = _digest;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final dayTime = DateFormat('EEEE, HH:mm', locale).format(DateTime.now());
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: d == null
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DsScreenHeader(title: dayTime, showBack: true),
                    const SizedBox(height: 18),
                    Row(children: [
                      const GhostIcon(size: 18),
                      const SizedBox(width: 8),
                      Text(
                        l10n.ghostDigestWhileAway,
                        style: AppTheme.rowTitle.copyWith(color: AppTheme.playerBlueBright, fontSize: 14),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text(_noWidow(l10n.ghostDigestTitle(d.count)), style: AppTheme.displayMedium.copyWith(fontSize: 30)),
                    if (d.sourcePlayedAt != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.ghostDigestReplays(
                          ghostShortDate(context, d.sourcePlayedAt),
                          ghostAverage(context, d.sourceAverage),
                        ),
                        style: AppTheme.caption.copyWith(fontSize: 14),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final g in d.games) ...[
                            _GameRow(game: g, onProfile: () => _openProfile(g.opponentId, g.opponentUsername)),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 10),
                          // Side by side at the same height, whichever label wraps.
                          IntrinsicHeight(
                            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              _Tile(
                                value: '+${d.xp} XP',
                                label: l10n.ghostDigestWins(d.ghostWins),
                                color: AppTheme.playerBlueBright,
                              ),
                              const SizedBox(width: 8),
                              _Tile(value: '${d.ghostWins} – ${d.ghostLosses}', label: l10n.ghostDigestRecord),
                            ]),
                          ),
                          if (d.beatenByUsername != null && d.beatenByDarts > 0) ...[
                            const SizedBox(height: 18),
                            Text(
                              l10n.ghostDigestBeaten(d.beatenByUsername!, d.beatenByDarts),
                              style: AppTheme.bodyMedium.copyWith(color: const Color(0xFFE2E8F0), height: 1.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (d.beatenByUsername != null && d.beatenByUserId != null) ...[
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () => _openProfile(d.beatenByUserId!, d.beatenByUsername!),
                          child: Text(dsSentence(l10n.ghostDigestChallenge(d.beatenByUsername!))),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Text(
                      l10n.ghostDigestFooter,
                      textAlign: TextAlign.center,
                      style: AppTheme.caption.copyWith(fontSize: 12, height: 1.45),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The last two words stay together: never one word alone on the last line
/// (« Ton fantôme a joué / 3 fois », not « … 3 / fois »).
String _noWidow(String s) {
  final i = s.lastIndexOf(' ');
  return i <= 0 ? s : '${s.substring(0, i)}\u00A0${s.substring(i + 1)}';
}

class _GameRow extends StatelessWidget {
  final GhostDigestGame game;
  final VoidCallback onProfile;
  const _GameRow({required this.game, required this.onProfile});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final time = game.finishedAt == null ? '' : DateFormat.Hm().format(game.finishedAt!);
    return Container(
      height: 60,
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusRow)),
      child: Row(
        children: [
          DsResultSquare(
            won: game.ghostWon,
            letter: game.ghostWon ? l10n.ghostResultWin : l10n.ghostResultLoss,
            size: 26,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(game.opponentUsername, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.rowTitle),
                const SizedBox(height: 1),
                Text(
                  '${game.ghostLegs} – ${game.opponentLegs}${time.isEmpty ? '' : ' · $time'}',
                  style: AppTheme.caption.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: OutlinedButton(
              onPressed: onProfile,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
              child: Text(dsSentence(l10n.ghostDigestChallengeShort)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _Tile({required this.value, required this.label, this.color = AppTheme.textPrimary});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(AppTheme.radiusRow)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: AppTheme.caption.copyWith(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

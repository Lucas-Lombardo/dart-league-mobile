import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/season.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/notification_service.dart';
import '../../utils/rank_translation.dart';
import '../../utils/rank_utils.dart';
import '../../utils/season_format.dart';
import '../../widgets/design_system.dart';
import '../../widgets/trophy_image.dart';
import 'season_new_elo_screen.dart';

/// End-of-season recap, shown once per closed season (gate:
/// users.seasonRecapSeenNumber, bumped at the end of [SeasonNewEloScreen]).
/// The vocabulary of the ELO overlay: an 88 px disc with the rank badge, a
/// spaced label + "Votre bilan", one card with the final ELO, the rank band
/// and three stat tiles, the champion card, then the primary button to the
/// new ELO (the only way out) and the share button as a secondary.
class SeasonRecapScreen extends StatefulWidget {
  final SeasonRecap recap;

  const SeasonRecapScreen({super.key, required this.recap});

  /// The fade-in route used for every full-screen overlay (game_screen).
  static Route<void> route(SeasonRecap recap) {
    return PageRouteBuilder<void>(
      opaque: true,
      pageBuilder: (_, _, _) => SeasonRecapScreen(recap: recap),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      transitionDuration: const Duration(milliseconds: 300),
    );
  }

  @override
  State<SeasonRecapScreen> createState() => _SeasonRecapScreenState();
}

class _SeasonRecapScreenState extends State<SeasonRecapScreen>
    with SingleTickerProviderStateMixin {
  final _shareKey = GlobalKey();
  late final AnimationController _ctrl;
  late final Animation<double> _headerIn;
  late final Animation<double> _cardIn;
  late final Animation<double> _championIn;
  late final Animation<double> _footerIn;
  bool _sharing = false;
  bool _reducedMotionApplied = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _headerIn = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
    );
    _cardIn = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.2, 0.6, curve: Curves.easeOutCubic),
    );
    _championIn = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.45, 0.8, curve: Curves.easeOutCubic),
    );
    _footerIn = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.7, 1.0, curve: Curves.easeIn),
    );
    _ctrl.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the OS "reduce motion" setting: jump straight to the final
    // state (same guard as tournament_end_screen).
    if (!_reducedMotionApplied && MediaQuery.of(context).disableAnimations) {
      _reducedMotionApplied = true;
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _reveal(Animation<double> animation, Widget child) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    );
  }

  void _seeNewElo() {
    HapticService.mediumImpact();
    Navigator.of(context).pushReplacement(SeasonNewEloScreen.route(widget.recap));
  }

  /// Renders the recap (disc, title, cards) to a PNG and hands it to the
  /// share sheet (pattern: replay_player_screen).
  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    HapticService.lightImpact();
    final l10n = AppLocalizations.of(context);
    try {
      final boundary = _shareKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('recap card not rendered');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('png encoding failed');
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/season_${widget.recap.season.number}_recap_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } catch (e) {
      debugPrint('[SeasonRecap] share failed: $e');
      if (mounted) {
        NotificationService.showError(context, l10n.seasonRecapShareFailed);
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recap = widget.recap;
    final username = context.watch<AuthProvider>().currentUser?.username ?? '';
    final next = recap.nextSeason;
    final ended = recap.season.endAt ?? next?.startedAt;
    final nextStart = ended == null ? null : seasonStartAfter(ended);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: RepaintBoundary(
                      key: _shareKey,
                      child: ColoredBox(
                        color: AppTheme.background,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _reveal(_headerIn, _buildHeader(l10n, recap)),
                            const SizedBox(height: 28),
                            _reveal(_cardIn, _RecapCard(recap: recap, username: username)),
                            if (recap.champion != null) ...[
                              const SizedBox(height: 14),
                              _reveal(_championIn, _ChampionCard(recap: recap)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: _reveal(
                  _footerIn,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (next != null) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 14,
                              color: AppTheme.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                nextStart != null
                                    ? l10n.seasonRecapNextStarts(
                                        next.number,
                                        formatSeasonDayShort(context, nextStart),
                                      )
                                    : l10n.seasonRecapNextStarted(next.number),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.caption.copyWith(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _seeNewElo,
                          child: Text(l10n.seasonRecapSeeNewElo),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _sharing ? null : _share,
                          icon: _sharing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.textSecondary,
                                  ),
                                )
                              : const Icon(Icons.ios_share_rounded, size: 18),
                          label: Text(l10n.seasonRecapShare),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 88 px primary disc carrying the final rank badge, "SAISON 1 TERMINÉE"
  /// as a spaced label, "Votre bilan" as the title.
  Widget _buildHeader(AppLocalizations l10n, SeasonRecap recap) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.6),
              width: 2,
            ),
          ),
          child: Center(child: RankUtils.getRankBadge(recap.rankBefore, size: 52)),
        ),
        const SizedBox(height: 18),
        Text(
          l10n.seasonRecapEnded(recap.season.number),
          textAlign: TextAlign.center,
          style: AppTheme.labelSmall.copyWith(letterSpacing: 1.3),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.seasonRecapTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
            height: 1,
          ),
        ),
      ],
    );
  }
}

/// The surface card: "ELO FINAL", the hero number with the rank pill, the
/// rank-band progress framed by the two floors, "Rang final · name", then
/// the three tiles (position / W – L / record).
class _RecapCard extends StatelessWidget {
  final SeasonRecap recap;
  final String username;

  const _RecapCard({required this.recap, required this.username});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final standing = recap.standing;
    final total = recap.season.playersCount ?? 0;
    final best = recap.peakElo ?? standing.elo;
    final rank = _bandRank(recap.rankBefore);

    return DsCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Text(
            l10n.seasonEloFinal.toUpperCase(),
            style: AppTheme.labelSmall.copyWith(letterSpacing: 1.3),
          ),
          const SizedBox(height: 10),
          // scaleDown keeps the hero line on one row whatever the rank name,
          // the locale or the user's text scale.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${recap.eloBefore}', style: _heroStyle),
                const SizedBox(width: 14),
                _ValuePill(
                  label: RankTranslation.translate(l10n, recap.rankBefore),
                  color: AppTheme.primaryLight,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          DsProgressBar(
            value: rank == 'master' ? 1 : rankProgress(rank, recap.eloBefore),
            height: 4,
          ),
          const SizedBox(height: 8),
          _BandCaptions(rank: rank),
          if (username.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              l10n.seasonRecapFinalRankOf(username),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(fontSize: 13),
            ),
          ],
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 14),
          Row(
            children: [
              _Tile(value: '#${standing.position}', label: l10n.seasonOf(total)),
              _Tile(
                value: '${standing.wins}–${standing.losses}',
                label: l10n.seasonRecapWinsLosses,
              ),
              _Tile(value: '$best', label: l10n.seasonRecapRecord),
            ],
          ),
        ],
      ),
    );
  }
}

/// 56 / 800 tabular hero number (the ELO overlay's).
const TextStyle _heroStyle = TextStyle(
  color: AppTheme.textPrimary,
  fontSize: 56,
  fontWeight: FontWeight.w800,
  letterSpacing: -1.7,
  height: 1,
  fontFeatures: [FontFeature.tabularFigures()],
);

/// The band a rating is read on: unranked is drawn as bronze.
String _bandRank(String rank) {
  final r = rank.toLowerCase();
  return kRankThresholds.containsKey(r) ? r : 'bronze';
}

/// 34 px tinted pill next to the hero number (rank name, delta).
class _ValuePill extends StatelessWidget {
  final String label;
  final Color color;

  const _ValuePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// "Or · 1200 ........ Platine · 1600" under the progress bar.
class _BandCaptions extends StatelessWidget {
  final String rank;

  const _BandCaptions({required this.rank});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isMax = rank == 'master';
    final style = AppTheme.caption.copyWith(fontWeight: FontWeight.w600);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            '${RankTranslation.translate(l10n, rank)} · ${kRankThresholds[rank]}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            isMax
                ? l10n.maxRankReached
                : '${RankTranslation.translate(l10n, nextRank(rank))} · ${kRankThresholds[nextRank(rank)]}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: style,
          ),
        ),
      ],
    );
  }
}

/// One of the three stat tiles: 22 / 700 tabular value over a spaced label.
class _Tile extends StatelessWidget {
  final String value;
  final String label;

  const _Tile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
                height: 1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label.toUpperCase(), style: AppTheme.labelSmall),
          ),
        ],
      ),
    );
  }
}

/// Flat champion card: the trophy render (a physical trophy) or the outlined
/// icon, "CHAMPION DE LA SAISON N", the name and what they win. Season 0 has
/// no prize: no trophy, no "wins".
class _ChampionCard extends StatelessWidget {
  final SeasonRecap recap;

  const _ChampionCard({required this.recap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final champion = recap.champion;
    if (champion == null) return const SizedBox.shrink();
    final season = recap.season;
    const icon = Icon(Icons.emoji_events_outlined, size: 24, color: AppTheme.textSecondary);
    return DsCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          if (season.hasReward) ...[
            SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: season.hasTrophyImage
                    ? TrophyImage(url: season.trophyThumbUrl, size: 40, fallback: icon)
                    : icon,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.seasonRecapChampionOf(season.number), style: AppTheme.labelSmall),
                const SizedBox(height: 4),
                Text(
                  champion.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.sectionTitle,
                ),
                const SizedBox(height: 3),
                Text(
                  season.hasReward
                      ? l10n.seasonRecapChampionWins(champion.elo)
                      : l10n.seasonRecapChampionElo(champion.elo),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

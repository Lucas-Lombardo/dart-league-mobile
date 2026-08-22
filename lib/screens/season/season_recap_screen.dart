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
import '../../widgets/trophy_image.dart';
import 'season_new_elo_screen.dart';

/// End-of-season recap, shown once per closed season (gate:
/// users.seasonRecapSeenNumber, bumped at the end of [SeasonNewEloScreen]).
/// Personal result first, champion second; the only way out is the button
/// to the new ELO — nobody discovers their compressed rating by surprise in
/// the ladder.
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

  /// Renders the recap card to a PNG and hands it to the share sheet
  /// (pattern: replay_player_screen).
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
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -1.15),
              radius: 0.9,
              colors: [Color(0x590EA5E9), Colors.transparent],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: RepaintBoundary(
                        key: _shareKey,
                        child: ColoredBox(
                          color: AppTheme.background,
                          child: Column(
                            children: [
                              _reveal(
                                _headerIn,
                                Column(
                                  children: [
                                    Text(
                                      l10n.seasonRecapEnded(recap.season.number),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 2.2,
                                        color: Color(0xFF38BDF8),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      l10n.seasonRecapTitle,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                        height: 1.15,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                              _reveal(_cardIn, _RecapCard(recap: recap, username: username)),
                              const SizedBox(height: 12),
                              _reveal(_championIn, _ChampionCard(recap: recap)),
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _reveal(
                    _footerIn,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (next != null)
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
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _seeNewElo,
                            child: Text(l10n.seasonRecapSeeNewElo),
                          ),
                        ),
                        SizedBox(
                          height: 44,
                          child: TextButton.icon(
                            onPressed: _sharing ? null : _share,
                            icon: _sharing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppTheme.primary,
                                    ),
                                  )
                                : const Icon(Icons.ios_share, size: 16),
                            label: Text(
                              l10n.seasonRecapShare,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rank badge, final rank, and the four tiles: position, final ELO, W – L,
/// best rating of the season.
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
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          RankUtils.getRankBadge(recap.rankBefore, size: 92),
          const SizedBox(height: 10),
          Text(
            RankTranslation.translate(l10n, recap.rankBefore),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.seasonRecapFinalRankOf(username),
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          Container(
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: AppTheme.surfaceLight.withValues(alpha: 0.6)),
              ),
            ),
            child: Row(
              children: [
                _Tile(value: '#${standing.position}', label: l10n.seasonOf(total)),
                _Tile(value: '${recap.eloBefore}', label: l10n.seasonEloFinal),
                _Tile(
                  value: '${standing.wins}–${standing.losses}',
                  label: l10n.seasonRecapWinsLosses,
                ),
                _Tile(value: '$best', label: l10n.seasonRecapRecord),
              ],
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
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Gold-tinted champion card. Season 0 has no prize: no trophy, no "wins".
class _ChampionCard extends StatelessWidget {
  final SeasonRecap recap;

  const _ChampionCard({required this.recap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final champion = recap.champion;
    if (champion == null) return const SizedBox.shrink();
    final season = recap.season;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x2EFFD700), Color(0x0FEAB308)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x66EAB308)),
      ),
      child: Row(
        children: [
          if (season.hasReward) ...[
            season.hasTrophyImage
                ? TrophyImage(
                    url: season.trophyThumbUrl,
                    size: 56,
                    fallback: const Icon(Icons.emoji_events, size: 48, color: AppTheme.gold),
                  )
                : const Icon(Icons.emoji_events, size: 48, color: AppTheme.gold),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.seasonRecapChampionOf(season.number),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: AppTheme.gold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  champion.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  season.hasReward
                      ? l10n.seasonRecapChampionWins(champion.elo)
                      : l10n.seasonRecapChampionElo(champion.elo),
                  style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

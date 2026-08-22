import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/season.dart';
import '../../providers/season_provider.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/rank_translation.dart';
import '../../utils/rank_utils.dart';
import '../../utils/season_format.dart';
import '../../widgets/season_chips.dart' show DashedRRectBorder;
import '../../widgets/trophy_image.dart';

/// One poster per season in a horizontal PageView, opened on the active one.
/// Almost no text: number, state, trophy, who leads (or the champion), your
/// position, one button. "Standings ›" pops with the season number so the
/// caller selects that chip.
class SeasonsScreen extends StatefulWidget {
  /// Poster to open on; defaults to the active season.
  final int? initialNumber;

  const SeasonsScreen({super.key, this.initialNumber});

  @override
  State<SeasonsScreen> createState() => _SeasonsScreenState();
}

class _SeasonsScreenState extends State<SeasonsScreen> {
  PageController? _controller;
  int _page = 0;

  List<Season> _seasonsOf(SeasonProvider provider) {
    final list = [...provider.seasons]..sort((a, b) => a.number.compareTo(b.number));
    if (list.isEmpty && provider.activeSeason != null) list.add(provider.activeSeason!);
    return list;
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = context.watch<SeasonProvider>();
    final seasons = _seasonsOf(provider);

    if (_controller == null && seasons.isNotEmpty) {
      final target = widget.initialNumber ?? provider.activeSeason?.number;
      var initial = seasons.indexWhere((s) => s.number == target);
      if (initial < 0) initial = seasons.indexWhere((s) => s.isActive);
      if (initial < 0) initial = 0;
      _page = initial;
      _controller = PageController(viewportFraction: 0.8, initialPage: initial);
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(l10n.seasonsTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => AppNavigator.back(context),
        ),
      ),
      body: seasons.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : LayoutBuilder(
              builder: (context, constraints) {
                final height = math.min(540.0, constraints.maxHeight - 60);
                return Column(
                  children: [
                    const SizedBox(height: 6),
                    SizedBox(
                      height: height,
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: seasons.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, i) {
                          final season = seasons[i];
                          return Center(
                            child: SizedBox(
                              width: 290,
                              height: height,
                              child: SeasonPoster(
                                season: season,
                                me: season.isActive
                                    ? provider.current?.me
                                    : season.myStanding,
                                timeLeft: season.isActive ? provider.timeLeft : null,
                                previousEnd: season.isScheduled
                                    ? provider.activeSeason?.endAt
                                    : null,
                                onStandings: season.isScheduled
                                    ? null
                                    : () {
                                        HapticService.lightImpact();
                                        AppNavigator.back(context, season.number);
                                      },
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < seasons.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _page ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? AppTheme.primary
                                  : AppTheme.textSecondary.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// The 290 × 540 poster: active (gradient), closed (surface + crown or
/// trophy), scheduled (dashed, greyed trophy).
class SeasonPoster extends StatelessWidget {
  final Season season;
  final SeasonStanding? me;
  final Duration? timeLeft;
  /// For a scheduled poster: the active season's end = this one's start.
  final DateTime? previousEnd;
  final VoidCallback? onStandings;

  const SeasonPoster({
    super.key,
    required this.season,
    this.me,
    this.timeLeft,
    this.previousEnd,
    this.onStandings,
  });

  static const _activeGradient = LinearGradient(
    begin: Alignment(-0.35, -1),
    end: Alignment(0.35, 1),
    colors: [Color(0xFF0EA5E9), Color(0xFF0284C7), Color(0xFF1E3A8A)],
    stops: [0.0, 0.5, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final Widget body;
    if (season.isActive) {
      body = _buildActive(context, l10n);
    } else if (season.isClosed) {
      body = _buildClosed(context, l10n);
    } else {
      body = _buildScheduled(context, l10n);
    }

    final watermarkAlpha = season.isActive ? 0.07 : (season.isClosed ? 0.05 : 0.04);
    final content = ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          Positioned(
            right: -18,
            bottom: -60,
            child: Text(
              '${season.number}',
              style: TextStyle(
                fontSize: 260,
                fontWeight: FontWeight.w900,
                letterSpacing: -14,
                height: 1,
                color: Colors.white.withValues(alpha: watermarkAlpha),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: body,
          ),
        ],
      ),
    );

    if (season.isActive) {
      return Container(
        decoration: BoxDecoration(
          gradient: _activeGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 48,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        child: content,
      );
    }
    if (season.isClosed) {
      return Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.6)),
        ),
        child: content,
      );
    }
    return DashedRRectBorder(
      color: AppTheme.textSecondary.withValues(alpha: 0.4),
      radius: 22,
      child: content,
    );
  }

  // ------------------------------------------------------------ pieces

  Widget _header(String title, Color titleColor, Widget pill) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.98,
            color: titleColor,
          ),
        ),
        const Spacer(),
        pill,
      ],
    );
  }

  Widget _pill({
    required Color background,
    required Color foreground,
    IconData? icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _trophy({double opacity = 1, bool grey = false, bool shadow = false}) {
    Widget image = season.hasTrophyImage
        ? TrophyImage(
            url: season.trophyImageUrl,
            size: 168,
            fallback: Icon(
              Icons.emoji_events,
              size: 120,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          )
        : Icon(
            Icons.emoji_events,
            size: 120,
            color: Colors.white.withValues(alpha: 0.9),
          );
    if (grey) {
      image = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: image,
      );
    }
    if (shadow) {
      image = DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: image,
      );
    }
    return SizedBox(
      width: 168,
      height: 168,
      child: Center(child: Opacity(opacity: opacity, child: image)),
    );
  }

  Widget _personRow({
    required Widget avatar,
    required String label,
    required Color labelColor,
    required String main,
    required String secondary,
    required Color mainColor,
    required Color secondaryColor,
  }) {
    return Row(
      children: [
        avatar,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: labelColor,
                ),
              ),
              Text.rich(
                TextSpan(
                  text: main,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: mainColor,
                  ),
                  children: [
                    TextSpan(
                      text: secondary,
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: secondaryColor,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _button({
    required String label,
    required Color background,
    Color? borderColor,
    required Color foreground,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onStandings,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: borderColor != null ? Border.all(color: borderColor) : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 16, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _initialAvatar(String username) {
    final letter = username.isEmpty ? '?' : username.characters.first.toUpperCase();
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.18),
        border: Border.all(color: AppTheme.gold, width: 2),
      ),
      child: Text(
        letter,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }

  // ------------------------------------------------------------ variants

  Widget _buildActive(BuildContext context, AppLocalizations l10n) {
    final white70 = Colors.white.withValues(alpha: 0.7);
    final leader = season.champion;
    final end = season.endAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _header(
          l10n.seasonN(season.number),
          Colors.white.withValues(alpha: 0.85),
          _pill(
            background: Colors.white.withValues(alpha: 0.16),
            foreground: Colors.white,
            icon: end != null ? Icons.schedule : null,
            text: end != null
                ? formatSeasonCountdown(l10n, timeLeft ?? season.timeLeft())
                : l10n.seasonInProgress,
          ),
        ),
        const SizedBox(height: 22),
        season.hasReward
            ? _trophy(shadow: true)
            : SizedBox(
                width: 168,
                height: 168,
                child: Center(
                  child: Icon(
                    Icons.flag_outlined,
                    size: 96,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ),
        const SizedBox(height: 8),
        Text(
          season.hasReward ? l10n.seasonPrize : l10n.seasonInProgress,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: Colors.white,
          ),
        ),
        Text(
          season.hasReward
              ? (end != null
                  ? l10n.seasonPrizeFor1stOn(formatSeasonDay(context, end))
                  : l10n.seasonPrizeFor1stShort)
              : (end != null
                  ? formatSeasonDay(context, end)
                  : l10n.seasonEndToBeAnnounced),
          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75)),
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.only(top: 18, bottom: 12),
          color: Colors.white.withValues(alpha: 0.18),
        ),
        if (leader != null)
          _personRow(
            avatar: _initialAvatar(leader.username),
            label: l10n.seasonLeader,
            labelColor: AppTheme.gold,
            main: leader.username,
            secondary: ' · ${leader.elo}',
            mainColor: Colors.white,
            secondaryColor: white70,
          ),
        if (me != null) ...[
          const SizedBox(height: 10),
          _personRow(
            avatar: RankUtils.getRankBadge(me!.rank, size: 34),
            label: l10n.seasonYou,
            labelColor: white70,
            main: '#${me!.position}',
            secondary: ' · ${me!.elo}',
            mainColor: Colors.white,
            secondaryColor: white70,
          ),
        ],
        const Spacer(),
        _button(
          label: l10n.seasonStandings,
          background: Colors.white.withValues(alpha: 0.16),
          foreground: Colors.white,
        ),
      ],
    );
  }

  Widget _buildClosed(BuildContext context, AppLocalizations l10n) {
    final champion = season.champion;
    final start = season.startedAt;
    final end = season.endAt;
    final String period;
    if (end == null) {
      period = '';
    } else if (start == null) {
      period = l10n.seasonFromLaunchTo(formatSeasonDate(context, end));
    } else {
      period = l10n.seasonPeriod(
        formatSeasonDay(context, start),
        formatSeasonDate(context, end),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _header(
          l10n.seasonN(season.number),
          AppTheme.textSecondary,
          _pill(
            background: AppTheme.textSecondary.withValues(alpha: 0.14),
            foreground: AppTheme.textSecondary,
            icon: Icons.lock_outline,
            text: l10n.seasonEnded,
          ),
        ),
        const SizedBox(height: 22),
        season.hasReward
            ? _trophy(shadow: true)
            : const SizedBox(
                width: 168,
                height: 168,
                child: Center(
                  child: Icon(Icons.workspace_premium_outlined, size: 96, color: AppTheme.gold),
                ),
              ),
        const SizedBox(height: 8),
        Text(
          l10n.seasonChampion,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.68,
            color: AppTheme.gold,
          ),
        ),
        Text(
          champion?.username ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: AppTheme.textPrimary,
          ),
        ),
        Text(
          champion != null
              ? '${champion.elo} · ${RankTranslation.translate(l10n, champion.rank)}'
              : '',
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.only(top: 18, bottom: 12),
          color: AppTheme.surfaceLight.withValues(alpha: 0.8),
        ),
        if (me != null)
          _personRow(
            avatar: RankUtils.getRankBadge(me!.rank, size: 34),
            label: l10n.seasonYou,
            labelColor: AppTheme.textSecondary,
            main: '#${me!.position}',
            secondary: ' · ${me!.elo} · ${RankTranslation.translate(l10n, me!.rank)}',
            mainColor: AppTheme.textPrimary,
            secondaryColor: AppTheme.textSecondary,
          )
        else
          Text(
            l10n.seasonNotRanked,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        if (period.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            period,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
        const Spacer(),
        _button(
          label: l10n.seasonFinalStandings,
          background: Colors.transparent,
          borderColor: AppTheme.surfaceLight.withValues(alpha: 0.9),
          foreground: AppTheme.textPrimary,
        ),
      ],
    );
  }

  Widget _buildScheduled(BuildContext context, AppLocalizations l10n) {
    final startsAt = previousEnd == null ? null : seasonStartAfter(previousEnd!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _header(
          l10n.seasonN(season.number),
          AppTheme.textSecondary,
          _pill(
            background: AppTheme.textSecondary.withValues(alpha: 0.14),
            foreground: AppTheme.textSecondary,
            text: l10n.seasonUpcoming,
          ),
        ),
        const SizedBox(height: 22),
        _trophy(opacity: 0.25, grey: true),
        const SizedBox(height: 8),
        Text(
          startsAt != null
              ? formatSeasonDayLong(context, startsAt)
              : l10n.seasonAfterSeason(season.number - 1),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: AppTheme.textSecondary,
          ),
        ),
        Text(
          l10n.seasonPrizeUpForGrabs,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

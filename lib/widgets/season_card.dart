import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/season.dart';
import '../utils/season_format.dart';
import 'trophy_image.dart';

/// The season card at the top of the Rankings tab: which season is being
/// played, what the #1 wins, and how far along it is.
///
/// Three states: an end date → countdown pill + time bar; no end date yet →
/// "in progress · end to be announced", no bar; no season at all → the
/// caller does not render the card (older backend / error).
class SeasonCard extends StatelessWidget {
  final Season season;
  /// Time left, recomputed by the provider every minute. Null = no end set.
  final Duration? timeLeft;
  final VoidCallback? onTap;
  /// Injectable "now" for the time bar (tests).
  final DateTime? now;

  const SeasonCard({
    super.key,
    required this.season,
    this.timeLeft,
    this.onTap,
    this.now,
  });

  static const _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0EA5E9), Color(0xFF0284C7), Color(0xFF1E3A8A)],
    stops: [0.0, 0.55, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasEnd = season.endAt != null;
    final today = now ?? DateTime.now();
    final progress = season.progress(today);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              gradient: _gradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                children: [
                  Positioned(
                    right: -30,
                    top: -40,
                    child: Container(
                      width: 170,
                      height: 170,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(context, l10n, hasEnd),
                        const SizedBox(height: 10),
                        _buildPrize(l10n),
                        if (hasEnd && progress != null) ...[
                          const SizedBox(height: 10),
                          _buildTimeBar(context, l10n, progress, today),
                        ],
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

  Widget _buildHeader(BuildContext context, AppLocalizations l10n, bool hasEnd) {
    final start = season.startedAt;
    final end = season.endAt;
    final String rightText;
    if (hasEnd && end != null) {
      rightText = start != null
          ? formatSeasonRange(context, start, end)
          : formatSeasonDay(context, end);
    } else {
      rightText = l10n.seasonEndToBeAnnounced;
    }
    return Row(
      children: [
        Text(
          (hasEnd
                  ? l10n.seasonN(season.number)
                  : '${l10n.seasonN(season.number)} · ${l10n.seasonInProgress}')
              .toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.68,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        if (hasEnd) ...[
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.schedule, size: 12, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  formatSeasonCountdown(l10n, timeLeft ?? season.timeLeft(now)),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            rightText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrize(AppLocalizations l10n) {
    final title = season.hasReward ? l10n.seasonPrize : l10n.seasonN(season.number);
    final subtitle = season.hasReward ? l10n.seasonPrizeFor1st : l10n.seasonNoReward;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.1,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        if (season.hasReward) ...[
          const SizedBox(width: 12),
          DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: season.hasTrophyImage
                ? TrophyImage(
                    url: season.trophyThumbUrl,
                    size: 64,
                    fallback: _trophyFallback,
                  )
                : _trophyFallback,
          ),
        ],
      ],
    );
  }

  static final Widget _trophyFallback = Icon(
    Icons.emoji_events,
    size: 56,
    color: Colors.white.withValues(alpha: 0.85),
  );

  Widget _buildTimeBar(
    BuildContext context,
    AppLocalizations l10n,
    double progress,
    DateTime today,
  ) {
    final labelStyle = TextStyle(
      fontSize: 10,
      color: Colors.white.withValues(alpha: 0.7),
    );
    return Column(
      children: [
        SizedBox(
          height: 12,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final x = constraints.maxWidth * progress;
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Container(
                    height: 6,
                    width: x,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Positioned(
                    left: (x - 6).clamp(0.0, constraints.maxWidth - 12),
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 3,
                          strokeAlign: BorderSide.strokeAlignOutside,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Text(l10n.seasonBegin, style: labelStyle),
            const Spacer(),
            Text(
              l10n.seasonToday(formatSeasonDay(context, today)),
              style: labelStyle,
            ),
            const Spacer(),
            Text(l10n.seasonEnd, style: labelStyle),
          ],
        ),
      ],
    );
  }
}

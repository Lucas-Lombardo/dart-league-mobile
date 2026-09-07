import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/tournament.dart';
import '../utils/app_theme.dart';
import '../utils/round_labels.dart';
import '../utils/tournament_bracket_logic.dart';

/// "Gagnant demi 2" for an empty slot, or the generic TBD label when the
/// bracket carries no feeder link.
String placeholderForSlot(
  AppLocalizations l10n,
  BracketIndex index,
  TournamentMatch match,
  int slot,
) {
  final feeder = index.feederForSlot(match, slot);
  if (feeder == null) return l10n.tbdLabel;
  return l10n.bracketWinnerOf(
    tinyRoundLabel(l10n, feeder.roundName, feeder.roundNumber),
    feeder.matchNumber,
  );
}

/// Live numbers for a match being played, from the spectate feed. Kept apart
/// from the service type so the tree stays testable.
class BracketLiveInfo {
  final int legs1;
  final int legs2;
  final int spectators;

  const BracketLiveInfo({
    required this.legs1,
    required this.legs2,
    required this.spectators,
  });
}

Color get _hairline => AppTheme.surfaceLight.withValues(alpha: 0.45);

/// Pulsing red dot used for everything live on the tournament screen.
class LiveDot extends StatelessWidget {
  final double size;

  const LiveDot({super.key, this.size = 7});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.secondary,
        boxShadow: [
          BoxShadow(
            color: AppTheme.secondary.withValues(alpha: 0.22),
            spreadRadius: 3,
          ),
        ],
      ),
    );
  }
}

/// The whole bracket as a paper-style tree: one column per round, connectors
/// between feeders and their next match, the signed-in player's winning path
/// in blue and a marker pinned above the match that concerns them now.
/// Scrolls horizontally when the columns exceed the width and lands on the
/// marked match on first layout.
class TournamentBracketTree extends StatefulWidget {
  final BracketIndex index;
  final String? currentUserId;

  /// Match to pin the marker above; null hides it.
  final String? focusMatchId;
  final String? markerLabel;
  final Color markerColor;

  /// Matches the player was invited to and can join right now.
  final Set<String> joinableMatchIds;

  /// Live legs/spectators keyed by tournament match id.
  final Map<String, BracketLiveInfo> liveByMatchId;
  final ValueChanged<TournamentMatch>? onTapMatch;

  const TournamentBracketTree({
    super.key,
    required this.index,
    required this.currentUserId,
    this.focusMatchId,
    this.markerLabel,
    this.markerColor = AppTheme.primary,
    this.joinableMatchIds = const {},
    this.liveByMatchId = const {},
    this.onTapMatch,
  });

  static const double headerHeight = 22;
  static const double horizontalPadding = 10;

  @override
  State<TournamentBracketTree> createState() => _TournamentBracketTreeState();
}

class _TournamentBracketTreeState extends State<TournamentBracketTree> {
  final ScrollController _controller = ScrollController();
  String? _scrolledTo;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _scrollToFocus(BracketLayout layout, double viewportWidth) {
    final id = widget.focusMatchId;
    if (id == null || _scrolledTo == id) return;
    final tile = layout.byMatchId[id];
    if (tile == null) return;
    _scrolledTo = id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final max = _controller.position.maxScrollExtent;
      if (max <= 0) return;
      // Bring the focused column fully into view, right-aligned so the rounds
      // that led there stay visible on the left.
      final target =
          (tile.right +
                  TournamentBracketTree.horizontalPadding * 2 -
                  viewportWidth)
              .clamp(0.0, max);
      _controller.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final index = widget.index;
    final layout = computeBracketLayout(index);
    final won = wonMatchIds(index, widget.currentUserId);
    final activeRound = index.activeRound;

    return LayoutBuilder(
      builder: (context, constraints) {
        _scrollToFocus(layout, constraints.maxWidth);
        final focusTile = widget.focusMatchId == null
            ? null
            : layout.byMatchId[widget.focusMatchId!];

        return SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: TournamentBracketTree.horizontalPadding,
          ),
          child: SizedBox(
            width: layout.width,
            height: TournamentBracketTree.headerHeight + layout.height + 8,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final round in index.rounds)
                  Positioned(
                    left: layout.columnX[round],
                    top: 0,
                    width: layout.columnWidth[round],
                    child: _ColumnHeader(
                      label: shortRoundLabel(
                        l10n,
                        index.byRound[round]!.first.roundName,
                        round,
                      ),
                      done: index.isRoundComplete(round),
                      current: round == activeRound,
                    ),
                  ),
                Positioned(
                  left: 0,
                  top: TournamentBracketTree.headerHeight,
                  width: layout.width,
                  height: layout.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ConnectorPainter(
                            layout: layout,
                            index: index,
                            highlighted: won,
                          ),
                        ),
                      ),
                      for (final tile in layout.tiles)
                        Positioned(
                          left: tile.x,
                          top: tile.y,
                          width: tile.width,
                          child: _BracketTile(
                            tile: tile,
                            index: index,
                            currentUserId: widget.currentUserId,
                            joinable: widget.joinableMatchIds.contains(
                              tile.match.id,
                            ),
                            live: widget.liveByMatchId[tile.match.id],
                            onTap: widget.onTapMatch == null
                                ? null
                                : () => widget.onTapMatch!(tile.match),
                          ),
                        ),
                      if (focusTile != null && widget.markerLabel != null)
                        Positioned(
                          left: focusTile.x,
                          top: focusTile.y - 26,
                          child: _Marker(
                            label: widget.markerLabel!,
                            color: widget.markerColor,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  final String label;
  final bool done;
  final bool current;

  const _ColumnHeader({
    required this.label,
    required this.done,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: current ? AppTheme.primary : AppTheme.textSecondary,
            ),
          ),
        ),
        if (done) ...[
          const SizedBox(width: 4),
          const Icon(Icons.check, size: 11, color: AppTheme.success),
        ],
      ],
    );
  }
}

class _Marker extends StatelessWidget {
  final String label;
  final Color color;

  const _Marker({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.flag_outlined, size: 10, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: CustomPaint(
            size: const Size(10, 6),
            painter: _CaretPainter(color),
          ),
        ),
      ],
    );
  }
}

class _CaretPainter extends CustomPainter {
  final Color color;

  const _CaretPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_CaretPainter old) => old.color != color;
}

class _ConnectorPainter extends CustomPainter {
  final BracketLayout layout;
  final BracketIndex index;
  final Set<String> highlighted;

  const _ConnectorPainter({
    required this.layout,
    required this.index,
    required this.highlighted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()
      ..color = AppTheme.textSecondary.withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final bright = Paint()
      ..color = AppTheme.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    // Dim links first so the highlighted path always paints on top.
    for (final pass in [false, true]) {
      for (final parent in layout.tiles) {
        for (final feeder in index.feedersOf(parent.match)) {
          final child = layout.byMatchId[feeder.id];
          if (child == null) continue;
          final on = highlighted.contains(feeder.id);
          if (on != pass) continue;
          final midX = child.right + layout.gutter / 2;
          final path = Path()
            ..moveTo(child.right, child.centerY)
            ..lineTo(midX, child.centerY)
            ..lineTo(midX, parent.centerY)
            ..lineTo(parent.x, parent.centerY);
          canvas.drawPath(path, on ? bright : dim);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ConnectorPainter old) =>
      old.layout != layout || old.highlighted != highlighted;
}

class _BracketTile extends StatelessWidget {
  final BracketTileGeometry tile;
  final BracketIndex index;
  final String? currentUserId;
  final bool joinable;
  final BracketLiveInfo? live;
  final VoidCallback? onTap;

  const _BracketTile({
    required this.tile,
    required this.index,
    required this.currentUserId,
    required this.joinable,
    required this.live,
    required this.onTap,
  });

  TournamentMatch get match => tile.match;

  bool get _mine =>
      currentUserId != null &&
      (match.player1Id == currentUserId || match.player2Id == currentUserId);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final compact = tile.compact;
    final isLive = match.isInProgress;
    final showScore = match.isCompleted || isLive;
    final padding = compact ? 7.0 : 10.0;

    final Color border;
    if (_mine) {
      border = AppTheme.primary.withValues(alpha: 0.6);
    } else if (isLive) {
      border = AppTheme.secondary.withValues(alpha: 0.5);
    } else {
      border = _hairline;
    }

    Widget row(int slot) {
      final id = slot == 0 ? match.player1Id : match.player2Id;
      final name = slot == 0 ? match.player1Username : match.player2Username;
      final score = slot == 0 ? match.player1Score : match.player2Score;
      final liveScore = live == null
          ? null
          : (slot == 0 ? live!.legs1 : live!.legs2);
      final tbd = id == null;
      // An empty slot on a settled 0-0 match is a bye. A played match can
      // also lose a player id (account deleted → FK set to null) — that one
      // keeps its scores and must still read as a played match.
      final bye =
          tbd &&
          match.isCompleted &&
          match.winnerId != null &&
          match.player1Score == 0 &&
          match.player2Score == 0;
      final me = !tbd && id == currentUserId;
      final winner = match.winnerId != null && match.winnerId == id;
      final loser = match.winnerId != null && !tbd && match.winnerId != id;
      final label = bye
          ? l10n.bracketBye
          : tbd
          ? placeholderForSlot(l10n, index, match, slot)
          : (name ?? l10n.tbdLabel);

      return SizedBox(
        height: compact ? 26 : 34,
        child: Opacity(
          opacity: loser ? 0.5 : 1,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: label,
                      children: [
                        if (me && !compact)
                          TextSpan(
                            text: '  ${l10n.you}',
                            style: const TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 10 : 11.5,
                      fontWeight: winner || me
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontStyle: tbd ? FontStyle.italic : FontStyle.normal,
                      color: tbd
                          ? AppTheme.textSecondary
                          : me
                          ? AppTheme.primary
                          : AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (showScore && !bye) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${liveScore ?? score}',
                    style: TextStyle(
                      fontSize: compact ? 10.5 : 13,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: winner
                          ? AppTheme.success
                          : isLive
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final body = Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(compact ? 8 : 12),
        border: Border.all(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          row(0),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            child: Container(height: 1, color: _hairline),
          ),
          row(1),
          if (!compact) _footer(l10n),
        ],
      ),
    );

    final tappable = onTap != null && (isLive || joinable);
    if (!tappable) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: body,
      ),
    );
  }

  Widget _footer(AppLocalizations l10n) {
    final Widget content;
    if (match.isDisputed) {
      content = _footerLine(
        Icons.gavel,
        l10n.underReviewBadge,
        AppTheme.accent,
      );
    } else if (match.isCompleted && match.winnerId == null) {
      content = _footerLine(
        Icons.close,
        l10n.matchStatusNotPlayed,
        AppTheme.error,
      );
    } else if (match.isCompleted) {
      content = _footerLine(
        Icons.check,
        l10n.matchStatusCompleted,
        AppTheme.success,
      );
    } else if (match.isInProgress) {
      content = Row(
        children: [
          const LiveDot(size: 6),
          const SizedBox(width: 6),
          // Expanded, not Flexible + Spacer: the label must get the whole
          // free width before it ever ellipsizes.
          Expanded(
            child: Text(
              l10n.liveBadge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppTheme.secondary,
              ),
            ),
          ),
          const Icon(Icons.chevron_right, size: 14, color: AppTheme.primary),
        ],
      );
    } else if (joinable) {
      content = _footerLine(
        Icons.notifications_active_outlined,
        l10n.bracketYourTurn,
        AppTheme.accent,
        letterSpacing: 0.2,
      );
    } else if (match.player1Id != null && match.player2Id != null) {
      content = _footerLine(
        Icons.schedule,
        l10n.matchStatusUpcoming,
        AppTheme.textSecondary,
      );
    } else {
      content = _footerLine(
        Icons.schedule,
        l10n.bracketWaiting,
        AppTheme.textSecondary,
      );
    }

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppTheme.background.withValues(alpha: 0.5),
        border: Border(top: BorderSide(color: _hairline)),
      ),
      child: content,
    );
  }

  Widget _footerLine(
    IconData icon,
    String text,
    Color color, {
    double letterSpacing = 0,
  }) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: letterSpacing,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/tournament.dart';
import '../utils/app_theme.dart';
import '../utils/round_labels.dart';
import '../utils/tournament_bracket_logic.dart';
import 'design_system.dart';

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

/// The rose dot that marks everything live on the tournament screens — the
/// only place the secondary colour appears outside a match.
class LiveDot extends StatelessWidget {
  final double size;

  const LiveDot({super.key, this.size = 7});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.secondary,
      ),
    );
  }
}

/// The whole bracket as a paper-style tree: one column per round, connectors
/// between feeders and their next match, the signed-in player's winning path
/// in the primary colour and a marker pinned above the match that concerns
/// them now. Scrolls horizontally when the columns exceed the width and lands
/// on the marked match on first layout.
///
/// Visual system D: surface tiles with a hairline, the primary path, a
/// coloured border only for "mine" and "live", sentence-case labels.
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

/// "QUARTS" / "DEMIS" / "FINALE" — the 10 / 700 spaced group label of a
/// column; the current round reads in the link colour.
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
            style: AppTheme.labelSmall.copyWith(
              fontSize: 10,
              color: current ? AppTheme.primaryLight : AppTheme.textSecondary,
            ),
          ),
        ),
        if (done) ...[
          const SizedBox(width: 4),
          const Icon(Icons.check_rounded, size: 11, color: AppTheme.success),
        ],
      ],
    );
  }
}

/// "Vous êtes ici" / "Éliminé ici" / "Champion" flag pinned above a tile.
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
                dsSentence(label),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.2,
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
      ..color = AppTheme.surfaceLight
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

    // The border is the tile's only state signal: my match, a live match,
    // or the plain hairline.
    final Color border;
    if (_mine) {
      border = AppTheme.primary.withValues(alpha: 0.6);
    } else if (isLive) {
      border = AppTheme.secondary.withValues(alpha: 0.5);
    } else {
      border = AppTheme.border;
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
                            text: '  ${dsSentence(l10n.you)}',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryLight,
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
                          ? AppTheme.primaryLight
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
            child: Container(height: 1, color: AppTheme.border),
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
        Icons.gavel_rounded,
        dsSentence(l10n.underReviewBadge),
        AppTheme.textSecondary,
      );
    } else if (match.isCompleted && match.winnerId == null) {
      content = _footerLine(
        Icons.close_rounded,
        l10n.matchStatusNotPlayed,
        AppTheme.error,
      );
    } else if (match.isCompleted) {
      content = _footerLine(
        Icons.check_rounded,
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
              dsSentence(l10n.liveBadge),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.secondary,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 14,
            color: AppTheme.primaryLight,
          ),
        ],
      );
    } else if (joinable) {
      content = _footerLine(
        Icons.notifications_active_outlined,
        dsSentence(l10n.bracketYourTurn),
        AppTheme.primaryLight,
      );
    } else if (match.player1Id != null && match.player2Id != null) {
      content = _footerLine(
        Icons.schedule_outlined,
        l10n.matchStatusUpcoming,
        AppTheme.textSecondary,
      );
    } else {
      content = _footerLine(
        Icons.schedule_outlined,
        l10n.bracketWaiting,
        AppTheme.textSecondary,
      );
    }

    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: content,
    );
  }

  Widget _footerLine(IconData icon, String text, Color color) {
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
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

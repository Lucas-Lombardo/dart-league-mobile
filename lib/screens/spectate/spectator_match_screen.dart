import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/spectator_provider.dart';
import '../../services/spectate_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../../widgets/game_turn_ui.dart'
    show GameControlButton, LiveBadge, VisitTotal;
import '../../widgets/tv_scoreboard.dart';
import '../../widgets/virtual_dartboard.dart';

/// Read-only live view of a ranked/tournament match: virtual board animated
/// by the per-dart stream, score band, current visit and last-visits feed.
///
/// Laid out like the opponent-turn screen of a real match (system D,
/// 2026-09): a badge row over the panel (glass back button, live badge,
/// viewer count), the r20 panel with the 1.5 px identity border of whoever is
/// throwing, then the score band and the quiet surface rows below.
class SpectatorMatchScreen extends StatefulWidget {
  final String matchId;

  /// Center label of the score band ("CLASSÉ", tournament name…).
  final String title;
  final LiveRankedSeries? seedRanked;
  final LiveTournamentMatch? seedTournament;

  const SpectatorMatchScreen({
    super.key,
    required this.matchId,
    required this.title,
    this.seedRanked,
    this.seedTournament,
  });

  @override
  State<SpectatorMatchScreen> createState() => _SpectatorMatchScreenState();
}

class _SpectatorMatchScreenState extends State<SpectatorMatchScreen> {
  late final SpectatorProvider _provider;

  // The viewer's choice when the cameras are available: the thrower's
  // camera (default) or the virtual board.
  bool _boardOnly = false;

  @override
  void initState() {
    super.initState();
    _provider = SpectatorProvider();
    _provider.startSpectating(
      widget.matchId,
      seedRanked: widget.seedRanked,
      seedTournament: widget.seedTournament,
    );
  }

  @override
  void dispose() {
    _provider.dispose();
    super.dispose();
  }

  /// Player 1 is the blue side of every spectator display, player 2 the rose
  /// one — the same identity convention as an in-match screen.
  bool _throwerIsPlayer1(SpectatorProvider p) =>
      p.currentPlayerId != null && p.currentPlayerId == p.player1?.id;

  Color _throwerColor(SpectatorProvider p) => _throwerIsPlayer1(p)
      ? AppTheme.playerBlueBright
      : AppTheme.opponentPinkBright;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.gameBackground,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _provider,
          builder: (context, _) {
            final p = _provider;
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBadgeRow(p),
                  const SizedBox(height: 10),
                  Expanded(child: _buildBoardPanel(p, l10n)),
                  const SizedBox(height: 10),
                  _buildScoreBand(p, l10n),
                  const SizedBox(height: 10),
                  _buildVisitTicker(p, l10n),
                  const SizedBox(height: 12),
                  _buildLastVisits(p, l10n),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(dsSentence(l10n.spectateLeave)),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Back / live badge / viewer count — the badge row the opponent feed docks
  /// on its video, here above the virtual board.
  Widget _buildBadgeRow(SpectatorProvider p) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          GameControlButton(
            icon: Icons.arrow_back_ios_new_rounded,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const Expanded(child: Center(child: LiveBadge())),
          if (p.callerAvailable) ...[
            Semantics(
              button: true,
              label: p.callerMuted
                  ? AppLocalizations.of(context).spectateUnmuteCaller
                  : AppLocalizations.of(context).spectateMuteCaller,
              child: GameControlButton(
                icon: p.callerMuted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                onTap: p.toggleCallerMuted,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppTheme.gameBackground.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.visibility_outlined,
                  size: 14,
                  color: AppTheme.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  '${p.spectatorCount}',
                  style: AppTheme.labelSmall.copyWith(height: 1),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _throwerName(SpectatorProvider p) => _throwerIsPlayer1(p)
      ? p.player1?.username
      : p.currentPlayerId == p.player2?.id
      ? p.player2?.username
      : null;

  /// The thrower's camera when the series runs on Cloudflare (only the
  /// thrower's, never a thumbnail of the other), else — and whenever the
  /// viewer picks "Board" or that camera is down — the virtual board in the
  /// camera panel's clothes: flat empty-panel background, r20, and the 1.5 px
  /// identity border of the thrower (a quiet hairline while not live).
  Widget _buildBoardPanel(SpectatorProvider p, AppLocalizations l10n) {
    final isLive = p.status == SpectatorStatus.live;
    final borderColor = !isLive
        ? AppTheme.border
        : _throwerIsPlayer1(p)
        ? AppTheme.playerBlue
        : AppTheme.opponentPink;
    final wantsCamera = p.camerasAvailable && !_boardOnly && isLive;
    final camera = wantsCamera && p.hasCameraFor(p.currentPlayerId)
        ? p.cameraViewFor(p.currentPlayerId)
        : null;
    final throwerName = _throwerName(p);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: AppTheme.gamePanelEmpty),
          if (camera != null) ...[
            camera,
            if (throwerName != null)
              Positioned(
                left: 12,
                top: 12,
                child: _glassPill(
                  leading: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _throwerColor(p),
                      shape: BoxShape.circle,
                    ),
                  ),
                  text: l10n.spectateThrowing(throwerName),
                ),
              ),
          ] else
            _buildVirtualBoard(
              p,
              l10n,
              isLive,
              // Keep the board clear of the bottom overlays: the toggle row
              // and, above it, the "camera unavailable" pill.
              bottomReserve: !p.camerasAvailable
                  ? 0
                  : wantsCamera && throwerName != null
                  ? 84
                  : 44,
            ),
          if (wantsCamera && camera == null && throwerName != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 56,
              child: Center(
                child: _glassPill(
                  leading: const Icon(
                    Icons.videocam_off_outlined,
                    size: 14,
                    color: AppTheme.textSecondary,
                  ),
                  text: l10n.spectateCameraUnavailable(throwerName),
                ),
              ),
            ),
          if (p.camerasAvailable)
            Positioned(left: 12, bottom: 12, child: _buildViewToggle(l10n)),
          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: 1.5),
                borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Camera / Board segmented control, docked bottom-left of the panel.
  Widget _buildViewToggle(AppLocalizations l10n) {
    Widget segment(String label, bool selected, VoidCallback onTap) {
      return Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppTheme.textPrimary : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                height: 1,
                color: selected
                    ? AppTheme.gameBackground
                    : AppTheme.textSecondary,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment(
            l10n.spectateCamera,
            !_boardOnly,
            () => setState(() => _boardOnly = false),
          ),
          const SizedBox(width: 2),
          segment(
            l10n.spectateBoard,
            _boardOnly,
            () => setState(() => _boardOnly = true),
          ),
        ],
      ),
    );
  }

  /// Glass pill over the feed: background at 85 %, a hairline, 12 / 700.
  Widget _glassPill({required Widget leading, required String text}) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVirtualBoard(
    SpectatorProvider p,
    AppLocalizations l10n,
    bool isLive, {
    double bottomReserve = 0,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fitted to the panel in BOTH directions: the board used to be
        // sized on the width alone and was cut off by the panel's
        // bottom edge on short phones.
        final height = constraints.maxHeight - 56 - bottomReserve;
        final available = constraints.maxWidth - 40 < height
            ? constraints.maxWidth - 40
            : height;
        final boardSize = available.clamp(120.0, 300.0);
        return Column(
          children: [
            const SizedBox(height: 12),
            Text(
              l10n.spectateVirtualBoard.toUpperCase(),
              style: AppTheme.labelSmall.copyWith(
                color: AppTheme.textTertiary,
                height: 1,
              ),
            ),
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  VirtualDartboard(
                    throws: p.currentRoundThrows,
                    size: boardSize,
                  ),
                  if (!isLive) _buildStatusPill(p, l10n),
                ],
              ),
            ),
            SizedBox(height: 12 + bottomReserve),
          ],
        );
      },
    );
  }

  /// Same glass hint pill as the camera guidance ones: background at 85 %, a
  /// hairline and 12 / 600 text.
  Widget _buildStatusPill(SpectatorProvider p, AppLocalizations l10n) {
    final String message;
    final Widget leading;
    switch (p.status) {
      case SpectatorStatus.connecting:
        message = l10n.spectateConnecting;
        leading = const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.textSecondary,
          ),
        );
        break;
      case SpectatorStatus.waitingNextLeg:
        message = l10n.spectateWaitingNextLeg;
        leading = const Icon(
          Icons.hourglass_empty_rounded,
          size: 15,
          color: AppTheme.textSecondary,
        );
        break;
      case SpectatorStatus.ended:
        final winner = p.winnerId == p.player1?.id
            ? p.player1?.username
            : p.winnerId == p.player2?.id
            ? p.player2?.username
            : null;
        message = winner != null
            ? '${l10n.spectateMatchOver} · $winner'
            : l10n.spectateMatchOver;
        leading = const Icon(
          Icons.emoji_events_outlined,
          size: 15,
          color: AppTheme.textSecondary,
        );
        break;
      case SpectatorStatus.denied:
        message = l10n.spectateUnavailable;
        leading = const Icon(
          Icons.videocam_off_outlined,
          size: 15,
          color: AppTheme.textSecondary,
        );
        break;
      case SpectatorStatus.live:
        return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          leading,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The shared score band: names in their identity colours over white
  /// tabular scores, the series context and both averages in the middle.
  Widget _buildScoreBand(SpectatorProvider p, AppLocalizations l10n) {
    final p1Avg = p.averageOf(true);
    final p2Avg = p.averageOf(false);
    return TvScoreboard(
      myName: p.player1?.username ?? '…',
      opponentName: p.player2?.username ?? '…',
      myScore: p.player1Score,
      opponentScore: p.player2Score,
      isMyTurn: _throwerIsPlayer1(p),
      myAverage: p1Avg > 0 ? p1Avg : null,
      opponentAverage: p2Avg > 0 ? p2Avg : null,
      seriesTitle: '${widget.title} · BO${p.bestOf}',
      myLegs: p.player1LegsWon,
      opponentLegs: p.player2LegsWon,
      caption: dsSentence(l10n.legNumber(p.legNumber)),
    );
  }

  /// "VOLÉE DE X … TOTAL 60" over the three darts of the visit in progress.
  Widget _buildVisitTicker(SpectatorProvider p, AppLocalizations l10n) {
    final throwerIsPlayer1 = _throwerIsPlayer1(p);
    final throwerName = throwerIsPlayer1
        ? p.player1?.username
        : p.currentPlayerId == p.player2?.id
        ? p.player2?.username
        : null;
    final color = _throwerColor(p);
    final throws = p.currentRoundThrows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  throwerName != null ? l10n.spectateVisitOf(throwerName) : '…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.labelSmall,
                ),
              ),
            ),
            VisitTotal(total: p.currentVisitTotal, color: color),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _visitChip(
                  i < throws.length ? throws[i] : null,
                  highlighted: i == throws.length - 1,
                  color: color,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _visitChip(
    String? notation, {
    required bool highlighted,
    required Color color,
  }) {
    final filled = notation != null;
    return Container(
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? AppTheme.surface : AppTheme.gamePanelEmpty,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(
          color: filled && highlighted ? color : AppTheme.border,
          width: filled && highlighted ? 1.5 : 1,
        ),
      ),
      child: filled
          ? Text(
              _displayNotation(notation),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1,
                color: AppTheme.textPrimary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            )
          : Container(
              width: 14,
              height: 2,
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
    );
  }

  /// 'S20' → '20', 'T20' → 'T20', 'S0' → '0'.
  static String _displayNotation(String notation) {
    if (notation.length >= 2 && notation[0] == 'S') {
      return notation.substring(1);
    }
    return notation;
  }

  Widget _buildLastVisits(SpectatorProvider p, AppLocalizations l10n) {
    final visits = p.lastVisits.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.spectateLastVisits.toUpperCase(), style: AppTheme.labelSmall),
        const SizedBox(height: 8),
        if (visits.isEmpty)
          DsCard(
            radius: AppTheme.radiusControl,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text('—', style: AppTheme.caption),
          ),
        for (final visit in visits) ...[
          _visitRow(p, visit),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _visitRow(SpectatorProvider p, SpectatedVisit visit) {
    final isPlayer1 = visit.playerId == p.player1?.id;
    final name = (isPlayer1 ? p.player1?.username : p.player2?.username) ?? '?';
    final color = isPlayer1
        ? AppTheme.playerBlueBright
        : AppTheme.opponentPinkBright;
    return DsCard(
      radius: AppTheme.radiusControl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: Text(
              visit.throws.map(_displayNotation).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${visit.total}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1,
              color: AppTheme.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

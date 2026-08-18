import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/spectator_provider.dart';
import '../../services/spectate_service.dart';
import '../../utils/app_theme.dart';
import '../../widgets/game_turn_ui.dart' show CameraScoreBand, LiveBadge;
import '../../widgets/virtual_dartboard.dart';

/// Read-only live view of a ranked/tournament match: virtual board animated
/// by the per-dart stream, score band, current visit and last-visits feed.
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
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(p),
                  const SizedBox(height: 10),
                  Expanded(child: _buildBoardPanel(context, p, l10n)),
                  const SizedBox(height: 10),
                  _buildVisitTicker(p, l10n),
                  const SizedBox(height: 10),
                  _buildStatsRow(p, l10n),
                  const SizedBox(height: 10),
                  _buildLastVisits(p, l10n),
                  const SizedBox(height: 12),
                  _buildLeaveButton(l10n),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(SpectatorProvider p) {
    return Row(
      children: [
        InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.gamePanel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.surfaceLight, width: 1.4),
            ),
            child: const Icon(Icons.arrow_back_ios_new,
                size: 18, color: AppTheme.textPrimary),
          ),
        ),
        const Expanded(child: Center(child: LiveBadge())),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.gamePanel,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.visibility_outlined,
                  size: 14, color: AppTheme.textSecondary),
              const SizedBox(width: 5),
              Text(
                '${p.spectatorCount}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBoardPanel(
      BuildContext context, SpectatorProvider p, AppLocalizations l10n) {
    final throwerIsPlayer1 =
        p.currentPlayerId != null && p.currentPlayerId == p.player1?.id;
    final borderColor =
        throwerIsPlayer1 ? AppTheme.playerBlue : AppTheme.opponentPink;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: p.status == SpectatorStatus.live
              ? borderColor
              : AppTheme.surfaceLight,
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.2),
              radius: 1.1,
              colors: [Color(0xFF1D2740), AppTheme.gameBackground],
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final boardSize =
                  (constraints.maxWidth - 90).clamp(160.0, 300.0);
              return Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    top: 30,
                    child: VirtualDartboard(
                      throws: p.currentRoundThrows,
                      size: boardSize,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    child: Text(
                      l10n.spectateVirtualBoard,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                        color: AppTheme.textPrimary.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  if (p.status != SpectatorStatus.live) _buildStatusOverlay(p, l10n),
                  Positioned(
                    left: 10,
                    right: 10,
                    bottom: 10,
                    child: CameraScoreBand(
                      myName: p.player1?.username ?? '…',
                      opponentName: p.player2?.username ?? '…',
                      myScore: p.player1Score,
                      opponentScore: p.player2Score,
                      seriesTitle: widget.title,
                      myLegs: p.player1LegsWon,
                      opponentLegs: p.player2LegsWon,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStatusOverlay(SpectatorProvider p, AppLocalizations l10n) {
    final String message;
    final Widget? leading;
    switch (p.status) {
      case SpectatorStatus.connecting:
        message = l10n.spectateConnecting;
        leading = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppTheme.accent),
        );
        break;
      case SpectatorStatus.waitingNextLeg:
        message = l10n.spectateWaitingNextLeg;
        leading = null;
        break;
      case SpectatorStatus.ended:
        final winner = p.winnerId == p.player1?.id
            ? p.player1?.username
            : p.winnerId == p.player2?.id
                ? p.player2?.username
                : null;
        message = winner != null
            ? '${l10n.spectateMatchOver} · 🏆 $winner'
            : l10n.spectateMatchOver;
        leading = null;
        break;
      case SpectatorStatus.denied:
        message = l10n.spectateUnavailable;
        leading = null;
        break;
      case SpectatorStatus.live:
        return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: AppTheme.accent.withValues(alpha: 0.6), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 8)],
          Text(
            message,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisitTicker(SpectatorProvider p, AppLocalizations l10n) {
    final throwerIsPlayer1 =
        p.currentPlayerId != null && p.currentPlayerId == p.player1?.id;
    final throwerName = throwerIsPlayer1
        ? p.player1?.username
        : p.currentPlayerId == p.player2?.id
            ? p.player2?.username
            : null;
    final throwerColor =
        throwerIsPlayer1 ? AppTheme.playerBlue : AppTheme.opponentPink;
    final throws = p.currentRoundThrows;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.gamePanelEmpty,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppTheme.surfaceLight.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              throwerName != null
                  ? l10n.spectateVisitOf(throwerName.toUpperCase())
                  : '…',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          for (var i = 0; i < 3; i++) ...[
            _visitChip(
              i < throws.length ? throws[i] : null,
              highlighted: i == throws.length - 1,
              color: throwerColor,
            ),
            const SizedBox(width: 8),
          ],
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${p.currentVisitTotal}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: throwerColor,
                ),
              ),
              const Text(
                'TOTAL',
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _visitChip(String? notation, {required bool highlighted, required Color color}) {
    final filled = notation != null;
    return Container(
      width: 38,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled
            ? AppTheme.gamePanel.withValues(alpha: 0.9)
            : AppTheme.gamePanelEmpty,
        borderRadius: BorderRadius.circular(8),
        border: filled && highlighted
            ? Border.all(color: color, width: 1.5)
            : Border.all(
                color: AppTheme.surfaceLight.withValues(alpha: 0.5),
                width: 1.5,
              ),
      ),
      child: filled
          ? Text(
              _displayNotation(notation),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary,
              ),
            )
          : Container(
              width: 14,
              height: 3,
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

  Widget _buildStatsRow(SpectatorProvider p, AppLocalizations l10n) {
    final avgLabel = l10n.trainingAverage.toUpperCase();
    String avg(bool isPlayer1) {
      final value = p.averageOf(isPlayer1);
      return value <= 0 ? '–' : value.toStringAsFixed(1);
    }

    Widget tile(String label, String value, Color valueColor) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.gamePanel,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        tile(
          '$avgLabel ${(p.player1?.username ?? '').toUpperCase()}',
          avg(true),
          AppTheme.playerBlue,
        ),
        const SizedBox(width: 10),
        tile(
          l10n.legNumber(p.legNumber).toUpperCase(),
          'BO${p.bestOf}',
          AppTheme.textPrimary,
        ),
        const SizedBox(width: 10),
        tile(
          '$avgLabel ${(p.player2?.username ?? '').toUpperCase()}',
          avg(false),
          AppTheme.opponentPink,
        ),
      ],
    );
  }

  Widget _buildLastVisits(SpectatorProvider p, AppLocalizations l10n) {
    final visits = p.lastVisits.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.spectateLastVisits,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 7),
        if (visits.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: AppTheme.gamePanelEmpty,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              '—',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
        for (final visit in visits) ...[
          _visitRow(p, visit),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _visitRow(SpectatorProvider p, SpectatedVisit visit) {
    final isPlayer1 = visit.playerId == p.player1?.id;
    final name = (isPlayer1 ? p.player1?.username : p.player2?.username) ?? '?';
    final color = isPlayer1 ? AppTheme.playerBlue : AppTheme.opponentPink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.gamePanelEmpty,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              name.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: Text(
              visit.throws.map(_displayNotation).join(' · '),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary.withValues(alpha: 0.85),
              ),
            ),
          ),
          Text(
            '${visit.total}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveButton(AppLocalizations l10n) {
    return InkWell(
      onTap: () => Navigator.of(context).maybePop(),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.accent.withValues(alpha: 0.9),
            width: 1.5,
          ),
        ),
        child: Text(
          l10n.spectateLeave,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: AppTheme.accent,
          ),
        ),
      ),
    );
  }
}

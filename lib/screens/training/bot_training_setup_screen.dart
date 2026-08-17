import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/bot_match_config.dart';
import '../../models/bot_rank.dart';
import '../../models/cricket.dart';
import '../../models/training.dart';
import '../../providers/placement_provider.dart';
import '../../services/training_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/storage_service.dart';
import '../placement/placement_camera_setup_screen.dart';
import '../placement/cricket_bot_game_screen.dart';

/// Colors of the rank chips — same hexes the old rank picker sheet used.
const Map<BotRank, Color> kBotRankColors = {
  BotRank.bronze: Color(0xFFCD7F32),
  BotRank.silver: Color(0xFFC0C0C0),
  BotRank.gold: Color(0xFFFFD700),
  BotRank.platinum: Color(0xFF9CB6C6),
  BotRank.diamond: Color(0xFF63D6F2),
  BotRank.pro: Color(0xFF7C3AED),
  BotRank.master: AppTheme.error,
};

String botRankLabel(AppLocalizations l10n, BotRank rank) {
  switch (rank) {
    case BotRank.bronze:
      return l10n.rankBronze;
    case BotRank.silver:
      return l10n.rankSilver;
    case BotRank.gold:
      return l10n.rankGold;
    case BotRank.platinum:
      return l10n.rankPlatinum;
    case BotRank.diamond:
      return l10n.rankDiamond;
    case BotRank.pro:
      return l10n.rankPro;
    case BotRank.master:
      return l10n.rankMaster;
  }
}

/// The bot match configurator: game mode, format (best of) and bot rank on a
/// single screen, with the last used config restored on open. Replaces the
/// old rank + starting-score sheet chain.
class BotTrainingSetupScreen extends StatefulWidget {
  const BotTrainingSetupScreen({super.key});

  @override
  State<BotTrainingSetupScreen> createState() => _BotTrainingSetupScreenState();
}

class _BotTrainingSetupScreenState extends State<BotTrainingSetupScreen> {
  static const _formats = [3, 5, 7, 11];

  BotMatchConfig _config = const BotMatchConfig();
  List<BotModeStats>? _modeStats;

  @override
  void initState() {
    super.initState();
    _restoreConfig();
    _loadStats();
  }

  Future<void> _restoreConfig() async {
    try {
      final raw = await StorageService.getBotMatchConfig();
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final config = BotMatchConfig.fromJson(decoded);
      if (mounted) setState(() => _config = config);
    } catch (_) {
      // A stale/corrupt saved config just falls back to the defaults.
    }
  }

  Future<void> _loadStats() async {
    try {
      final stats = await TrainingService.getStats();
      final bot = stats.where((s) => s.type == TrainingType.botTraining);
      if (mounted && bot.isNotEmpty) {
        setState(() => _modeStats = bot.first.modes);
      }
    } catch (_) {
      // Stats are decoration here — the screen works without them.
    }
  }

  void _update(BotMatchConfig config) {
    HapticService.lightImpact();
    setState(() => _config = config);
  }

  Future<void> _play() async {
    HapticService.mediumImpact();
    try {
      await StorageService.saveBotMatchConfig(jsonEncode(_config.toJson()));
    } catch (_) {}
    if (!mounted) return;
    context.read<PlacementProvider>().startBotTrainingMatch(_config);
    final isCricket = _config.isCricket;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlacementCameraSetupScreen(
          gameScreenBuilder: isCricket
              ? () => const CricketBotGameScreen()
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.botSetupTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                children: [
                  _sectionHeader(l10n.botSetupModeSection),
                  const SizedBox(height: 12),
                  _modeCards(l10n),
                  if (_config.isCricket) ...[
                    const SizedBox(height: 10),
                    _cricketVariantSegment(l10n),
                  ],
                  _modeStatsLine(l10n),
                  const SizedBox(height: 22),
                  _sectionHeader(l10n.botSetupFormatSection),
                  const SizedBox(height: 12),
                  _formatSegment(),
                  const SizedBox(height: 8),
                  Text(
                    '${l10n.firstToNLegs(_config.legsToWin)} · '
                    '${l10n.starterAlternates}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _sectionHeader(l10n.botSetupOpponentSection),
                  const SizedBox(height: 12),
                  _rankChips(l10n),
                  const SizedBox(height: 8),
                  Text(
                    l10n.trainingBotAvg(_config.rank.targetAverage),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            _launchBar(l10n),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.6,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            color: AppTheme.surfaceLight.withValues(alpha: 0.65),
          ),
        ),
      ],
    );
  }

  Widget _modeCards(AppLocalizations l10n) {
    Widget card({
      required String label,
      required String hint,
      required Color color,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.15)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? color
                      : AppTheme.surfaceLight.withValues(alpha: 0.8),
                  width: selected ? 1.8 : 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? color : Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hint,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        card(
          label: '501',
          hint: l10n.trainingBotGameTypeHint501,
          color: AppTheme.primary,
          selected: _config.gameMode == BotGameMode.x501,
          onTap: () => _update(_config.copyWith(gameMode: BotGameMode.x501)),
        ),
        const SizedBox(width: 10),
        card(
          label: '301',
          hint: l10n.trainingBotGameTypeHint301,
          color: AppTheme.accent,
          selected: _config.gameMode == BotGameMode.x301,
          onTap: () => _update(_config.copyWith(gameMode: BotGameMode.x301)),
        ),
        const SizedBox(width: 10),
        card(
          label: l10n.cricketLabel,
          hint: l10n.cricketSetupHint,
          color: AppTheme.success,
          selected: _config.isCricket,
          onTap: () => _update(_config.copyWith(gameMode: BotGameMode.cricket)),
        ),
      ],
    );
  }

  Widget _cricketVariantSegment(AppLocalizations l10n) {
    Widget option(CricketScoreMode mode, String label) {
      final selected = _config.cricketScoreMode == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => _update(_config.copyWith(cricketScoreMode: mode)),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.success.withValues(alpha: 0.22)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? Colors.white : AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.success.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              option(CricketScoreMode.score, l10n.cricketScoreLabel),
              const SizedBox(width: 6),
              option(CricketScoreMode.noScore, l10n.cricketNoScoreLabel),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _config.cricketScoreMode == CricketScoreMode.score
              ? l10n.cricketScoreHint
              : l10n.cricketNoScoreHint,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
        ),
      ],
    );
  }

  /// "N matchs · X % de victoires · moy. Y / Y MPR" for the selected mode —
  /// hidden until the stats arrive or when the mode was never played.
  Widget _modeStatsLine(AppLocalizations l10n) {
    final stats = _modeStats;
    if (stats == null) return const SizedBox.shrink();
    BotModeStats? forMode;
    for (final m in stats) {
      if (m.mode == _config.modeWire) forMode = m;
    }
    if (forMode == null || forMode.sessions == 0) {
      return const SizedBox.shrink();
    }
    final avg = forMode.averageScore;
    final avgText = avg == null
        ? null
        : (_config.isCricket
              ? l10n.mprShort(avg.toStringAsFixed(1))
              : l10n.avgShort(avg.toStringAsFixed(1)));
    final winPct = ((forMode.winRate ?? 0) * 100).round();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        l10n.botModeStatsSummary(forMode.sessions, winPct, avgText ?? '—'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _formatSegment() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          for (final f in _formats) ...[
            if (f != _formats.first) const SizedBox(width: 6),
            Expanded(
              child: GestureDetector(
                onTap: () => _update(_config.copyWith(bestOf: f)),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: _config.bestOf == f
                        ? AppTheme.primary.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: _config.bestOf == f
                        ? Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.5),
                          )
                        : null,
                  ),
                  child: Text(
                    'BO$f',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _config.bestOf == f
                          ? AppTheme.primary
                          : AppTheme.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _rankChips(AppLocalizations l10n) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final rank in BotRank.values)
          GestureDetector(
            onTap: () => _update(_config.copyWith(rank: rank)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: _config.rank == rank
                    ? kBotRankColors[rank]!.withValues(alpha: 0.15)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(
                  color: _config.rank == rank
                      ? kBotRankColors[rank]!
                      : AppTheme.surfaceLight.withValues(alpha: 0.8),
                  width: _config.rank == rank ? 1.6 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: kBotRankColors[rank],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    botRankLabel(l10n, rank),
                    style: TextStyle(
                      color: _config.rank == rank
                          ? Colors.white
                          : AppTheme.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _launchBar(AppLocalizations l10n) {
    final modeLabel = _config.isCricket
        ? '${l10n.cricketLabel} · ${_config.cricketScoreMode == CricketScoreMode.noScore ? l10n.cricketNoScoreLabel : l10n.cricketScoreLabel}'
        : (_config.gameMode == BotGameMode.x301 ? '301' : '501');
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          top: BorderSide(
            color: AppTheme.surfaceLight.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$modeLabel · BO${_config.bestOf} · '
            '${botRankLabel(l10n, _config.rank)}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _play,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                l10n.play.toUpperCase(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

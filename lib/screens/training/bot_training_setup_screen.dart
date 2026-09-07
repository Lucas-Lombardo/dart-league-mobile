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
import '../../widgets/cricket_variant_segment.dart';
import '../../widgets/design_system.dart';
import '../placement/placement_camera_setup_screen.dart';
import '../placement/cricket_bot_game_screen.dart';
import 'training_select_screen.dart';

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

  /// Every selectable here (cards, segments, chips) fires its own light
  /// haptic on tap, so the state update stays silent.
  void _update(BotMatchConfig config) {
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

  void _showRules(AppLocalizations l10n) {
    showTrainingRulesSheet(
      context,
      title: l10n.trainingBotTraining,
      body: l10n.trainingRulesBotTraining,
      icon: Icons.smart_toy_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.botSetupTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: DsIconButton(
              icon: Icons.info_outline_rounded,
              tooltip: l10n.trainingRules,
              onTap: () => _showRules(l10n),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                children: [
                  _groupLabel(l10n.botSetupModeSection),
                  const SizedBox(height: 10),
                  _modeCards(l10n),
                  if (_config.isCricket) ...[
                    const SizedBox(height: 10),
                    CricketVariantSegment(
                      value: _config.cricketScoreMode,
                      onChanged: (mode) {
                        HapticService.lightImpact();
                        _update(_config.copyWith(cricketScoreMode: mode));
                      },
                      scoreHint: l10n.cricketScoreHint,
                    ),
                  ],
                  _modeStatsLine(l10n),
                  const SizedBox(height: 28),
                  _groupLabel(l10n.botSetupFormatSection),
                  const SizedBox(height: 10),
                  _formatSegment(),
                  const SizedBox(height: 8),
                  Text(
                    '${l10n.firstToNLegs(_config.legsToWin)} · '
                    '${l10n.starterAlternates}',
                    textAlign: TextAlign.center,
                    style: AppTheme.caption,
                  ),
                  const SizedBox(height: 28),
                  _groupLabel(l10n.botSetupOpponentSection),
                  const SizedBox(height: 10),
                  _rankChips(l10n),
                  const SizedBox(height: 8),
                  Text(
                    l10n.trainingBotAvg(_config.rank.targetAverage),
                    textAlign: TextAlign.center,
                    style: AppTheme.caption,
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

  /// 11 / 700 spaced group label ("MODE DE JEU").
  Widget _groupLabel(String title) {
    return Text(title.toUpperCase(), style: AppTheme.labelSmall);
  }

  Widget _modeCards(AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: _OptionCard(
            label: '501',
            hint: l10n.trainingBotGameTypeHint501,
            selected: _config.gameMode == BotGameMode.x501,
            onTap: () => _update(_config.copyWith(gameMode: BotGameMode.x501)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _OptionCard(
            label: '301',
            hint: l10n.trainingBotGameTypeHint301,
            selected: _config.gameMode == BotGameMode.x301,
            onTap: () => _update(_config.copyWith(gameMode: BotGameMode.x301)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _OptionCard(
            label: l10n.cricketLabel,
            hint: l10n.cricketSetupHint,
            selected: _config.isCricket,
            onTap: () =>
                _update(_config.copyWith(gameMode: BotGameMode.cricket)),
          ),
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
        style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _formatSegment() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusControl),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          for (final f in _formats) ...[
            if (f != _formats.first) const SizedBox(width: 4),
            Expanded(
              child: _Segment(
                label: 'BO$f',
                selected: _config.bestOf == f,
                onTap: () => _update(_config.copyWith(bestOf: f)),
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
          _Chip(
            label: botRankLabel(l10n, rank),
            selected: _config.rank == rank,
            onTap: () => _update(_config.copyWith(rank: rank)),
          ),
      ],
    );
  }

  Widget _launchBar(AppLocalizations l10n) {
    final modeLabel = _config.isCricket
        ? '${l10n.cricketLabel} · ${_config.cricketScoreMode == CricketScoreMode.noScore ? l10n.cricketNoScoreLabel : l10n.cricketScoreLabel}'
        : (_config.gameMode == BotGameMode.x301 ? '301' : '501');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$modeLabel · BO${_config.bestOf} · '
            '${botRankLabel(l10n, _config.rank)}',
            style: AppTheme.caption.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _play,
              child: Text(l10n.play),
            ),
          ),
        ],
      ),
    );
  }
}

/// Active-state vocabulary shared by the three selectables below: primary at
/// 14 % with a primaryLight hairline and primaryLight text.
const Color _kActiveFill = Color(0x240EA5E9);

/// Game-mode card: big label over a two-line hint.
class _OptionCard extends StatelessWidget {
  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  const _OptionCard({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return DsCard(
      radius: AppTheme.radiusRow,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      color: selected ? _kActiveFill : null,
      side: selected ? const BorderSide(color: AppTheme.primaryLight) : null,
      onTap: onTap,
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: selected ? AppTheme.primaryLight : AppTheme.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            hint,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.caption.copyWith(fontSize: 11, height: 1.2),
          ),
        ],
      ),
    );
  }
}

/// One cell of the best-of segmented control.
class _Segment extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Segment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _kActiveFill : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: selected
            ? const BorderSide(color: AppTheme.primaryLight)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticService.lightImpact();
          onTap();
        },
        child: Container(
          height: 40,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppTheme.primaryLight : AppTheme.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// 34 px rank chip.
class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _kActiveFill : AppTheme.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppTheme.primaryLight : AppTheme.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticService.lightImpact();
          onTap();
        },
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppTheme.primaryLight : AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

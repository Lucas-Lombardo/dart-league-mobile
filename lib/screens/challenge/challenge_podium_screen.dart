import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import '../progression/locker_screen.dart';
import 'challenge_api.dart';
import 'challenge_models.dart';
import 'challenge_session_screen.dart';
import 'challenge_widgets.dart';
import 'logic/challenge_strategy.dart';

/// "N°1 du jour" wins needed for the Crown avatar (achievement « N°1 du
/// jour », silver tier — docs/progression/data/succes.json). Display only:
/// the item itself is given by the achievements (Agent 3).
const int kCrownAvatarWins = 5;

/// Yesterday's final result of my board (mockup ecrans/DefiPodium): the
/// n°1 with the checked session, my place, my rewards when I won.
class ChallengePodiumScreen extends StatefulWidget {
  final String? date;
  const ChallengePodiumScreen({super.key, this.date});

  @override
  State<ChallengePodiumScreen> createState() => _ChallengePodiumScreenState();
}

class _ChallengePodiumScreenState extends State<ChallengePodiumScreen> {
  ChallengePodium? _podium;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final p = await ChallengeApi.podium(date: widget.date);
      if (mounted) setState(() => _podium = p);
    } catch (e) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = _podium;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  ChallengeHeaderButton(
                    icon: Icons.close_rounded,
                    semanticLabel: MaterialLocalizations.of(context).closeButtonLabel,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(l10n.challengeYesterdayResult, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ChallengeColors.muted)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: p == null
                  ? Center(
                      child: _failed
                          ? TextButton(onPressed: _load, child: Text(l10n.challengeRetry))
                          : const CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5),
                    )
                  : _buildBody(context, l10n, p),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AppLocalizations l10n, ChallengePodium p) {
    final crown = p.crown;
    final me = p.me;
    final f = p.format;
    final board = challengeBoardName(l10n, p.board.rank);
    final mine = me?.crowned ?? false;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        if (!p.available)
          Text(l10n.challengePodiumEmpty, style: AppTheme.bodyMedium, textAlign: TextAlign.center)
        else ...[
          Center(child: _Medal(date: challengeDayLabel(context, p.date, short: true).toUpperCase())),
          const SizedBox(height: 14),
          Text(
            l10n.challengePodiumFirst(board),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 32, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -0.6),
          ),
          const SizedBox(height: 6),
          Text(
            crown == null
                ? (p.closed ? l10n.challengeNoFirst : l10n.challengePodiumNotClosed)
                : '${crown.username ?? ''} · ${f?.short.resolve(context) ?? ''} · ${challengeScoreText(f, crown.score ?? 0, unfinished: l10n.challengeUnfinished)} ${challengeUnit(context, f)}'.trim(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: ChallengeColors.soft),
          ),
          const SizedBox(height: 18),
          if (mine && me != null) ...[
            Row(
              children: [
                Expanded(child: _Stat(value: me.crownPaid ? '+${me.eloBonus}' : '+${p.eloBonus}', label: l10n.challengeEloLabel, accent: true)),
                const SizedBox(width: 8),
                Expanded(child: _Stat(value: '× ${me.badgeCount}', label: l10n.challengeBadgeLabel)),
                const SizedBox(width: 8),
                Expanded(child: _Stat(value: '+${me.xp}', label: 'XP', accent: true)),
              ],
            ),
            const SizedBox(height: 18),
          ],
          if (crown != null) ...[
            _CheckCard(crown: crown),
            const SizedBox(height: 18),
          ],
          if (mine && me != null && me.badgeCount < kCrownAvatarWins) ...[
            _CrownProgress(wins: me.badgeCount),
            const SizedBox(height: 18),
          ],
          if (!mine && me != null && me.position != null) ...[
            DsCard(
              child: Text(
                l10n.challengePodiumYourPlace(challengeOrdinal(context, me.position!), me.total ?? 0, me.xp),
                style: AppTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 18),
          ],
          for (final row in p.top) ...[
            ChallengeRowTile(row: row, format: f),
            const SizedBox(height: 6),
          ],
          const SizedBox(height: 16),
          if (mine && (me?.crownPaid ?? false))
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ChallengeColors.accent,
                  foregroundColor: AppTheme.background,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 16, fontWeight: FontWeight.w800),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LockerScreen(initialTab: ItemType.badge)),
                ),
                child: Text(l10n.challengePinBadge),
              ),
            ),
          if (crown != null && (crown.verified || mine)) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: ChallengeColors.text,
                  side: const BorderSide(color: ChallengeColors.slate700),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 15, fontWeight: FontWeight.w700),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ChallengeSessionScreen(crownId: crown.crownId)),
                ),
                child: Text(mine ? l10n.challengeWatchMySession : l10n.challengeWatchSession),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// The dated "N°1" medal: a gold ring (gold = the crown) around a dark disc.
class _Medal extends StatelessWidget {
  final String date;
  const _Medal({required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 132,
      padding: const EdgeInsets.all(4),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFDE68A), Color(0xFFB8860B), Color(0xFFFACC15)],
          stops: [0, 0.45, 1],
        ),
      ),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(center: Alignment(-0.3, -0.4), colors: [Color(0xFF2A3550), Color(0xFF131B2E)], stops: [0, 0.7]),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.workspace_premium_outlined, size: 22, color: ChallengeColors.crown),
            const Text('N°1', style: TextStyle(fontSize: 30, height: 1, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(date, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: ChallengeColors.soft)),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final bool accent;
  const _Stat({required this.value, required this.label, this.accent = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: accent ? ChallengeColors.accentLight : ChallengeColors.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 12, color: ChallengeColors.muted)),
          ],
        ),
      );
}

class _CheckCard extends StatelessWidget {
  final ChallengePodiumCrown crown;
  const _CheckCard({required this.crown});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ok = crown.verified;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ok ? ChallengeColors.successWash : AppTheme.background,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(ok ? Icons.verified_outlined : Icons.hourglass_top_rounded, size: 20, color: ok ? ChallengeColors.success : ChallengeColors.accentLight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ok ? l10n.challengeSessionVerified : l10n.challengeSessionPending, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  ok ? l10n.challengeSessionVerifiedBody(crown.aiDarts, crown.correctedDarts) : l10n.challengeSessionPendingBody,
                  style: const TextStyle(fontSize: 12, height: 1.35, color: ChallengeColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CrownProgress extends StatelessWidget {
  final int wins;
  const _CrownProgress({required this.wins});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(l10n.challengeCrownAvatar, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
            Text(l10n.challengeWinsOf(wins, kCrownAvatarWins), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ChallengeColors.muted)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: (wins / kCrownAvatarWins).clamp(0, 1).toDouble(),
            minHeight: 8,
            backgroundColor: ChallengeColors.slate700,
            color: ChallengeColors.accent,
          ),
        ),
      ],
    );
  }
}

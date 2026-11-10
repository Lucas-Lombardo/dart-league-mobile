import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../utils/app_theme.dart';
import '../progression/xp_summary_panel.dart';
import 'challenge_models.dart';
import 'challenge_proof_uploader.dart';
import 'challenge_story.dart';
import 'challenge_widgets.dart';
import 'logic/challenge_strategy.dart';

/// The result of an attempt (mockup ecrans/DefiResultat): the server's
/// score, the place in the board and overall, the streak, who the player
/// passed, the video status (top 3), the XP and the share card.
class ChallengeResultScreen extends StatelessWidget {
  final ChallengeResult result;

  /// Set right after a play: the XP block lists what was earned since then.
  final DateTime? xpSince;

  const ChallengeResultScreen({super.key, required this.result, this.xpSince});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final r = result;
    final f = r.format;
    final s = r.standing;
    final scoreText = challengeScoreText(f, r.score, finished: r.finished, unfinished: l10n.challengeUnfinished);
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
                    child: Text(
                      l10n.challengeResultTitle(challengeDayLabel(context, r.date, short: true)),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ChallengeColors.muted),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
                children: [
                  Column(
                    children: [
                      Text(f.name.resolve(context), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ChallengeColors.accentLight)),
                      const SizedBox(height: 6),
                      Text(
                        scoreText,
                        style: const TextStyle(fontSize: 64, height: 1, fontWeight: FontWeight.w800, letterSpacing: -2, fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                      const SizedBox(height: 6),
                      Text(challengeUnit(context, f), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      if (r.bestVisit != null) ...[
                        const SizedBox(height: 6),
                        Text(l10n.challengeBestVisit(r.bestVisit!), style: const TextStyle(fontSize: 13, color: ChallengeColors.muted)),
                      ],
                      if (!r.ranked) ...[
                        const SizedBox(height: 8),
                        ChallengeChip(label: l10n.challengePracticeResult),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (r.ranked && s != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _Tile(
                            big: '${challengeOrdinal(context, s.position)} / ${s.total}',
                            small: l10n.challengePlaceSub(
                              challengeBoardName(l10n, s.board),
                              challengeOrdinal(context, s.allPosition),
                              s.allTotal,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Tile(
                            icon: Icons.local_fire_department_outlined,
                            big: l10n.challengeStreakDays(r.streak),
                            small: l10n.challengeStreakPlus,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _PassedLine(result: r),
                    const SizedBox(height: 14),
                  ],
                  if (r.ranked && r.proofRequired) ...[
                    _ProofCard(attemptId: r.attemptId, serverStatus: r.proofStatus),
                    const SizedBox(height: 14),
                  ],
                  if (r.ranked && xpSince != null) ...[
                    XpSummaryPanel(since: xpSince!, expectRefId: r.date),
                    if (s != null && s.top10) ...[
                      const SizedBox(height: 6),
                      Text(l10n.challengeTop10Pending, style: AppTheme.caption, textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 14),
                  ],
                  if (r.ranked)
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ChallengeColors.accent,
                          foregroundColor: AppTheme.background,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          textStyle: const TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: Text(l10n.challengeShare),
                        onPressed: () => ChallengeStorySheet.show(context, r),
                      ),
                    ),
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
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.challengePractice),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(l10n.challengePracticeNote, textAlign: TextAlign.center, style: AppTheme.caption),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String big;
  final String small;
  final IconData? icon;
  const _Tile({required this.big, required this.small, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 20, color: ChallengeColors.accent), const SizedBox(width: 6)],
              Flexible(
                child: Text(
                  big,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(small, maxLines: 2, style: const TextStyle(fontSize: 13, color: ChallengeColors.muted)),
        ],
      ),
    );
  }
}

/// "You pass Steph_D16 (571) and Bruno_T19 (540). Kev_D20 stays No. 1 with
/// 612: 14 h left for the others."
class _PassedLine extends StatelessWidget {
  final ChallengeResult result;
  const _PassedLine({required this.result});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final f = result.format;
    final left = challengeTimeLeft(l10n, result.endsAt);
    final spans = <InlineSpan>[];
    const bold = TextStyle(fontWeight: FontWeight.w800);
    if (result.passed.isNotEmpty) {
      final parts = l10n.challengePassedPrefix;
      spans.add(TextSpan(text: '$parts '));
      for (var i = 0; i < result.passed.length; i++) {
        final p = result.passed[i];
        if (i > 0) spans.add(TextSpan(text: ' ${l10n.challengeAnd} '));
        spans.add(TextSpan(text: p.username, style: bold));
        spans.add(TextSpan(text: ' (${challengeScoreText(f, p.score, unfinished: l10n.challengeUnfinished)})'));
      }
      spans.add(const TextSpan(text: '. '));
    }
    if (!result.closed) {
      final leader = result.leader;
      spans.add(TextSpan(
        text: leader == null
            ? l10n.challengeYouLead(left)
            : l10n.challengeLeaderStays(leader.username, challengeScoreText(f, leader.score, unfinished: l10n.challengeUnfinished), left),
      ));
    }
    if (spans.isEmpty) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(style: const TextStyle(fontSize: 14, height: 1.45, color: ChallengeColors.softer), children: spans),
    );
  }
}

/// "Your session is sent" (top 3 of the board: the video is the proof).
class _ProofCard extends StatelessWidget {
  final String attemptId;
  final String serverStatus;
  const _ProofCard({required this.attemptId, required this.serverStatus});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder<Map<String, ChallengeProofState>>(
      valueListenable: ChallengeProofUploader.states,
      builder: (context, states, _) {
        final local = states[attemptId];
        final sent = serverStatus == 'delivered' || local == ChallengeProofState.sent;
        final failed = !sent && local == ChallengeProofState.failed;
        final sending = !sent && !failed;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.videocam_outlined, size: 20, color: ChallengeColors.accentLight),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sent ? l10n.challengeProofSent : l10n.challengeProofSending,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      failed ? l10n.challengeProofFailed : l10n.challengeProofWhy,
                      style: const TextStyle(fontSize: 12, height: 1.35, color: ChallengeColors.muted),
                    ),
                  ],
                ),
              ),
              if (sent)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(color: ChallengeColors.successWash, borderRadius: BorderRadius.circular(999)),
                  child: Text(l10n.challengeProofReceived, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: ChallengeColors.success)),
                )
              else if (failed)
                TextButton(onPressed: () => ChallengeProofUploader.upload(attemptId), child: Text(l10n.challengeRetry))
              else if (sending)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: ChallengeColors.accent)),
            ],
          ),
        );
      },
    );
  }
}

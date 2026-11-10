import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/progression_provider.dart';
import '../../services/progression_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/progression/progression_widgets.dart';
import 'challenge_models.dart';
import 'challenge_widgets.dart';
import 'logic/challenge_strategy.dart';

/// The 9:16 story card of a result (mockup ecrans/DefiStory, 360 × 640):
/// free advertising — "Beat me. Download Dart Rivals".
class ChallengeStoryCard extends StatelessWidget {
  final ChallengeResult result;
  final String username;
  final String rank;
  final PublicCosmetics? cosmetics;

  const ChallengeStoryCard({
    super.key,
    required this.result,
    required this.username,
    required this.rank,
    this.cosmetics,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final r = result;
    final s = r.standing;
    final title = TitleText.nameOf(context, cosmetics?.title);
    final line = [
      ?title,
      challengeBoardName(l10n, rank),
      if (cosmetics != null) l10n.xpLevelShort(cosmetics!.level),
    ].join(' · ');
    return Container(
      width: 360,
      height: 640,
      padding: const EdgeInsets.fromLTRB(30, 36, 30, 30),
      color: ChallengeColors.story,
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: AppTheme.fontFamily, color: ChallengeColors.text),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Image.asset('assets/logo/logo-without-letters.png', width: 28, height: 28, fit: BoxFit.contain),
                const SizedBox(width: 10),
                const Text('Dart Rivals', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.challengeStoryHeader(challengeDayLabel(context, r.date, short: true)),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ChallengeColors.muted),
                  ),
                ),
              ],
            ),
            Expanded(
              // Long format names: the block shrinks, it never overflows.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.format.name.resolve(context), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: ChallengeColors.accentLight)),
                  const SizedBox(height: 6),
                  Text(
                    challengeScoreText(r.format, r.score, unfinished: l10n.challengeUnfinished),
                    style: const TextStyle(fontSize: 116, height: 0.9, fontWeight: FontWeight.w800, letterSpacing: -5, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                  const SizedBox(height: 6),
                  Text(challengeUnit(context, r.format), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (s != null && s.open) ...[
                        ChallengeChip(label: l10n.challengeStoryTop(s.rankPct), accent: true, fontSize: 14),
                        const SizedBox(width: 8),
                      ],
                      if (s != null) ...[
                        _DarkChip(l10n.challengeStoryPlace(challengeOrdinal(context, s.position), challengeBoardName(l10n, s.board))),
                        const SizedBox(width: 8),
                      ],
                      if (r.streak > 0) _DarkChip(l10n.challengeStoryStreak(r.streak)),
                    ],
                  ),
                ],
              ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFA9B4C4), width: 2),
              ),
              child: Row(
                children: [
                  FramedAvatar(rank: rank, cosmetics: cosmetics, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(username, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 2),
                        Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ChallengeColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // Both ends whole, pushed apart; a line too long for the card
            // shrinks as one (never « Fais mieux que … »).
            LayoutBuilder(
              builder: (context, constraints) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(l10n.challengeStoryLine, maxLines: 1, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                      Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Text(
                          l10n.challengeStoryCta,
                          maxLines: 1,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ChallengeColors.muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkChip extends StatelessWidget {
  final String label;
  const _DarkChip(this.label);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(999)),
        child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: ChallengeColors.softer)),
      );
}

/// Preview of the card, then the share sheet (a 1080 × 1920 PNG).
class ChallengeStorySheet extends StatefulWidget {
  final ChallengeResult result;
  const ChallengeStorySheet({super.key, required this.result});

  static Future<void> show(BuildContext context, ChallengeResult result) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppTheme.background,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => ChallengeStorySheet(result: result),
      );

  @override
  State<ChallengeStorySheet> createState() => _ChallengeStorySheetState();
}

class _ChallengeStorySheetState extends State<ChallengeStorySheet> {
  final _key = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final f = widget.result.format;
    final text = l10n.challengeShareText(
      f.name.resolve(context),
      '${challengeScoreText(f, widget.result.score, unfinished: l10n.challengeUnfinished)} ${challengeUnit(context, f)}'.trim(),
    );
    setState(() => _sharing = true);
    HapticService.lightImpact();
    try {
      final boundary = _key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('story card not rendered');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('png encoding failed');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/challenge_${widget.result.date}_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: text));
      // Discovery quest q088 "Share your challenge card".
      await ProgressionService.reportClientAction('challenge_shared');
    } catch (e) {
      debugPrint('[ChallengeStory] share failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(l10n.challengeShareFailed)));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    User? user;
    try {
      user = context.watch<AuthProvider>().currentUser;
    } on ProviderNotFoundException {
      user = null;
    }
    final cosmetics = maybeWatchProgression(context)?.summary?.cosmetics;
    final size = MediaQuery.of(context).size;
    final previewHeight = (size.height * 0.62).clamp(320.0, 640.0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: previewHeight,
              child: FittedBox(
                child: RepaintBoundary(
                  key: _key,
                  child: ChallengeStoryCard(
                    result: widget.result,
                    username: user?.username ?? '',
                    rank: user?.rank ?? widget.result.standing?.board ?? 'bronze',
                    cosmetics: cosmetics,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
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
                onPressed: _sharing ? null : _share,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

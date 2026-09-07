import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../providers/matchmaking_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../services/socket_service.dart';
import '../settings/subscription_screen.dart';
import '../training/training_select_screen.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/orientation_utils.dart';
import '../../widgets/design_system.dart';
import '../../widgets/queue_activity_chart.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/referral_provider.dart';
import '../settings/redeem_referral_screen.dart';

class MatchmakingScreen extends StatefulWidget {
  const MatchmakingScreen({super.key});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _rotationController;
  MatchmakingProvider? _matchmakingProvider;
  String? _userId;

  /// True when another screen (a training launched via "Train while you wait")
  /// is on top of this one. While that's the case we must NOT leave the queue or
  /// pop on lifecycle/back events — the player is still queued, just elsewhere.
  bool get _isCurrent => ModalRoute.of(context)?.isCurrent ?? true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keep the screen awake while in queue — without this the phone goes
    // to sleep if the user doesn't touch the screen and they miss the match.
    WakelockPlus.enable();
    OrientationUtils.allowAll();

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _userId ??= context.read<AuthProvider>().currentUser?.id;
    _matchmakingProvider ??= context.read<MatchmakingProvider>();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only react while this screen is on top. If a "Train while you wait"
    // screen is above us, leaving the queue / popping here would wrongly cancel
    // the search and pop the training screen.
    if (state == AppLifecycleState.paused && _isCurrent) {
      final userId = _userId;
      if (userId != null) {
        _matchmakingProvider?.leaveQueue(userId);
      }
      if (mounted) Navigator.of(context).pop();
    }
  }

  /// Opens the training menu without leaving the queue. Match-found navigation
  /// is owned globally by [MatchmakingNavigationGate], so when an opponent is
  /// found the player is pulled out of the training and into the match
  /// automatically — regardless of which training screen they're on.
  void _openTrainingWhileWaiting() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const TrainingSelectScreen()));
  }

  /// Back chevron and "Cancel search" share this: leave the queue, then pop.
  Future<void> _cancelSearch() async {
    final matchmaking = context.read<MatchmakingProvider>();
    final user = context.read<AuthProvider>().currentUser;
    if (mounted && user?.id != null) {
      await matchmaking.leaveQueue(user!.id);
    }
    if (mounted && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rotationController.dispose();
    // Releasing the wakelock here is safe: BaseGameScreenState re-asserts the
    // wakelock on a short periodic timer for the whole match, so this late
    // disable() (it runs ~300ms after the match-found navigation, once the
    // GameScreen push transition completes) is recovered within one tick and
    // can't leave the match able to sleep.
    WakelockPlus.disable();
    OrientationUtils.portraitOnly();
    super.dispose();
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(1, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// Free tier, daily ranked match already used: the crown (the one place
  /// gold is allowed), the upgrade button and — when still eligible — the
  /// referral code path.
  Widget _buildDailyLimitCard(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DsCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.accent.withValues(alpha: 0.14),
            ),
            child: const Icon(
              Icons.workspace_premium_outlined,
              size: 26,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.dailyLimitReachedShort,
            style: AppTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            '${l10n.goPremiumUnlimited}.',
            style: AppTheme.caption.copyWith(height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                HapticService.mediumImpact();
                final user = context.read<AuthProvider>().currentUser;
                if (user?.id != null) {
                  await context.read<MatchmakingProvider>().leaveQueue(
                    user!.id,
                  );
                }
                if (!context.mounted) return;
                Navigator.of(context)
                    .pushReplacement(
                      MaterialPageRoute(
                        builder: (_) => const SubscriptionScreen(),
                      ),
                    )
                    .then((_) {
                      if (context.mounted) {
                        context.read<SubscriptionProvider>().refresh();
                      }
                    });
              },
              child: Text(l10n.upgradeToPremium),
            ),
          ),
          // The moment premium is actually missed: offer the referral code to
          // anyone still eligible. Hidden entirely otherwise — no dead row.
          if (context.watch<ReferralProvider>().canRedeem) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  HapticService.lightImpact();
                  final user = context.read<AuthProvider>().currentUser;
                  if (user?.id != null) {
                    await context.read<MatchmakingProvider>().leaveQueue(
                      user!.id,
                    );
                  }
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RedeemReferralScreen(),
                    ),
                  );
                  if (!context.mounted) return;
                  await context.read<SubscriptionProvider>().refresh();
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.card_giftcard_outlined, size: 18),
                label: Text(l10n.referralHaveCodeTitle),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Hero: the search ring with the shield on the left, group label + timer
  /// + ELO/range summary on the right. Compact so it sits above the fold
  /// alongside the peak-hours chart.
  Widget _buildHeroCard({
    required String time,
    required int elo,
    required int range,
  }) {
    final l10n = AppLocalizations.of(context);
    return DsCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          _buildSearchRing(),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.searchingForOpponentUpper,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.labelSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  time,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.7,
                    height: 1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    style: AppTheme.caption,
                    children: [
                      TextSpan(
                        text: '$elo',
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: ' ${l10n.eloLabel} · ± $range · '
                            '${l10n.eloRangeExpandingHint}',
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 88 px ring: a faint primary track, a rotating primary arc (the "sweep"),
  /// a hairline inner ring and the brand shield at the centre. No glow, no
  /// pulse — the motion alone says "searching".
  Widget _buildSearchRing() {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _rotationController,
            builder: (context, _) => CustomPaint(
              size: const Size.square(88),
              painter: _SearchRingPainter(_rotationController.value),
            ),
          ),
          Image.asset(
            'assets/logo/logo-without-letters.png',
            width: 40,
            height: 40,
          ),
        ],
      ),
    );
  }

  /// "Train while you wait": a quiet row — the queue keeps running under the
  /// training, and the match-found gate pulls the player back.
  Widget _buildTrainRow(AppLocalizations l10n) {
    return SizedBox(
      height: 64,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
        onTap: _openTrainingWhileWaiting,
        child: Row(
          children: [
            const Icon(
              Icons.fitness_center_rounded,
              size: 20,
              color: Color(0xFFE2E8F0),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dsSentence(l10n.trainWhileWaiting),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.rowTitle,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    l10n.trainWhileWaitingSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: AppTheme.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBox(String message) {
    return DsCard(
      color: AppTheme.error.withValues(alpha: 0.10),
      side: BorderSide(color: AppTheme.error.withValues(alpha: 0.4)),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppTheme.error,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTheme.caption.copyWith(color: AppTheme.error),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final matchmaking = context.watch<MatchmakingProvider>();
    final user = context.watch<AuthProvider>().currentUser;
    final dailyLimitReached =
        matchmaking.errorMessage?.contains('DAILY_MATCH_LIMIT_REACHED') ??
        false;
    final connected = SocketService.isConnected;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop && mounted && user?.id != null) {
          await matchmaking.leaveQueue(user!.id);
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: DsScreenHeader(
                  title: l10n.findingMatch,
                  showBack: true,
                  onBack: _cancelSearch,
                  actions: [
                    DsPill(
                      label: connected ? l10n.connected : l10n.disconnected,
                      color: connected ? AppTheme.success : AppTheme.error,
                      dot: true,
                    ),
                  ],
                ),
              ),
              if (dailyLimitReached)
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildDailyLimitCard(context),
                    ),
                  ),
                )
              else ...[
                // The middle section scrolls only when it doesn't fit, so the
                // cancel button below stays reachable without scrolling on
                // every screen size. The trailing Spacer absorbs any spare
                // height on tall screens.
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, viewport) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: viewport.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                              const SizedBox(height: 14),
                              _buildHeroCard(
                                time: _formatTime(matchmaking.searchTime),
                                elo: user?.elo ?? 0,
                                range: matchmaking.eloRange,
                              ),
                              const SizedBox(height: 14),
                              const QueueActivityChart(),
                              const SizedBox(height: 14),
                              _buildTrainRow(l10n),
                              const Spacer(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _cancelSearch,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.error,
                          ),
                          child: Text(dsSentence(l10n.cancelSearch)),
                        ),
                      ),
                      if (matchmaking.errorMessage != null) ...[
                        const SizedBox(height: 14),
                        _buildErrorBox(matchmaking.errorMessage!),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The search ring: 2 px track at primary 25 %, a half-turn primary arc
/// rotated by [progress] (0..1 = one revolution), and a 1 px hairline ring
/// 14 px inside.
class _SearchRingPainter extends CustomPainter {
  final double progress;

  const _SearchRingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = Rect.fromCircle(center: center, radius: size.width / 2 - 1);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppTheme.primary.withValues(alpha: 0.25);
    canvas.drawOval(outer, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = AppTheme.primary;
    final start = -math.pi / 2 + progress * 2 * math.pi;
    canvas.drawArc(outer, start, math.pi, false, arc);

    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.08);
    canvas.drawCircle(center, size.width / 2 - 14, inner);
  }

  @override
  bool shouldRepaint(covariant _SearchRingPainter old) =>
      old.progress != progress;
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/user.dart';
import '../../providers/friends_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_match_launcher.dart';
import '../../widgets/design_system.dart';
import '../../widgets/premium_badge.dart';
import '../../widgets/rank_badge.dart';

/// Friend picker for the "play against a friend" path opened from the home
/// play-mode selector. Tapping a friend runs the shared invite flow
/// ([FriendlyMatchLauncher]) — premium-gated, camera gate, then waiting room.
class FriendSelectScreen extends StatefulWidget {
  const FriendSelectScreen({super.key});

  @override
  State<FriendSelectScreen> createState() => _FriendSelectScreenState();
}

class _FriendSelectScreenState extends State<FriendSelectScreen> {
  Timer? _onlineTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<FriendsProvider>();
      provider.loadFriends();
      provider.refreshOnlineFriends();
    });
    // Keep online indicators fresh while picking a friend to invite.
    _onlineTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) context.read<FriendsProvider>().refreshOnlineFriends();
    });
  }

  @override
  void dispose() {
    _onlineTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final provider = context.watch<FriendsProvider>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l10n.selectFriendTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.selectFriendSubtitle,
                  style: AppTheme.bodyMedium,
                ),
              ),
            ),
            Expanded(child: _buildBody(provider, l10n)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(FriendsProvider provider, AppLocalizations l10n) {
    if (provider.isLoading && provider.friends.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }

    if (provider.error != null && provider.friends.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppTheme.error,
                size: 40,
              ),
              const SizedBox(height: 14),
              Text(
                provider.error!.replaceAll('Exception: ', ''),
                style: AppTheme.caption.copyWith(height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: () => provider.loadFriends(),
                child: Text(dsSentence(l10n.retry)),
              ),
            ],
          ),
        ),
      );
    }

    if (provider.friends.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.people_outline_rounded,
                size: 40,
                color: AppTheme.textTertiary,
              ),
              const SizedBox(height: 14),
              Text(
                l10n.noFriendsYet,
                style: AppTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.addFriendsHint,
                style: AppTheme.caption.copyWith(height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.loadFriends(),
      color: AppTheme.primary,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: provider.friends.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final friend = provider.friends[index];
          return _FriendInviteTile(
            friend: friend,
            isOnline: provider.isOnline(friend.id),
            onTap: () => FriendlyMatchLauncher.invite(context, friend),
          );
        },
      ),
    );
  }
}

/// 64 px row: rank badge (with the online dot), name + premium badge, the
/// ELO / record caption, chevron. The whole row invites.
class _FriendInviteTile extends StatelessWidget {
  final User friend;
  final bool isOnline;
  final VoidCallback onTap;

  const _FriendInviteTile({
    required this.friend,
    required this.isOnline,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      height: 64,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        onTap: onTap,
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                RankBadge(rank: friend.rank, size: 36, showLabel: false),
                if (isOnline)
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Semantics(
                      label: l10n.online,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppTheme.surface, width: 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          friend.username,
                          style: AppTheme.sectionTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      PremiumBadge(isPremium: friend.isPremiumActive, size: 14),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${friend.elo} ${l10n.eloLabel} · '
                    '${friend.wins}W - ${friend.losses}L',
                    style: AppTheme.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: AppTheme.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

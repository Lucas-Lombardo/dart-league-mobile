import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/user.dart';
import '../../providers/friends_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_match_launcher.dart';
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.selectFriendSubtitle,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 14,
                  ),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 64),
            const SizedBox(height: 16),
            Text(
              provider.error!.replaceAll('Exception: ', ''),
              style: const TextStyle(color: AppTheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => provider.loadFriends(),
              child: Text(l10n.retry),
            ),
          ],
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
              Icon(Icons.people_outline,
                  size: 64,
                  color: AppTheme.textSecondary.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(
                l10n.noFriendsYet,
                style: AppTheme.titleLarge.copyWith(
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.addFriendsHint,
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textSecondary),
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
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: provider.friends.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
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
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            RankBadge(rank: friend.rank, size: 40, showLabel: false),
            if (isOnline)
              Positioned(
                right: -1,
                bottom: -1,
                child: Semantics(
                  label: l10n.online,
                  child: Container(
                    width: 13,
                    height: 13,
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.surface, width: 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                friend.username,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            PremiumBadge(isPremium: friend.isPremiumActive, size: 14),
          ],
        ),
        subtitle: Text(
          'ELO: ${friend.elo} • ${friend.wins}W - ${friend.losses}L',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        trailing: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.sports_esports,
              color: AppTheme.primary, size: 20),
        ),
      ),
    );
  }
}

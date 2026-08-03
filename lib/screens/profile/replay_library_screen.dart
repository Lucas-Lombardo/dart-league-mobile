import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/replay_upload_service.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import 'replay_player_screen.dart';

/// « Mes replays » — the user's cloud library (GET /replays/mine): every
/// uploaded clip with a fresh presigned url, playable and shareable from
/// the player. Free accounts see the 5-clip quota banner once it bites.
class ReplayLibraryScreen extends StatefulWidget {
  const ReplayLibraryScreen({super.key});

  @override
  State<ReplayLibraryScreen> createState() => _ReplayLibraryScreenState();
}

class _ReplayLibraryScreenState extends State<ReplayLibraryScreen> {
  List<Map<String, dynamic>>? _clips;
  int _total = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiService.get('/replays/mine?limit=50');
      if (!mounted) return;
      setState(() {
        _clips = List<Map<String, dynamic>>.from(data['clips'] as List);
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _failed = false;
      });
    } catch (e) {
      debugPrint('[ReplayLibrary] load failed: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _delete(String id) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(l10n.replayDeleteTitle,
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.replayDelete,
                style: const TextStyle(color: AppTheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.delete('/replays/$id');
      _load();
    } catch (e) {
      debugPrint('[ReplayLibrary] delete failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = context.watch<AuthProvider>();
    final premium = auth.currentUser?.isPremiumActive ?? false;
    final quotaBites =
        !premium && (_total >= 5 || ReplayUploadService.quotaReached);

    return Scaffold(
      appBar: AppBar(title: Text('🎬 ${l10n.myReplays}')),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.primary,
        child: _clips == null
            ? Center(
                child: _failed
                    ? IconButton(
                        icon: const Icon(Icons.refresh,
                            color: AppTheme.textSecondary, size: 32),
                        onPressed: _load,
                      )
                    : const CircularProgressIndicator(color: AppTheme.primary),
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (quotaBites) _quotaBanner(l10n),
                  if (_clips!.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Column(children: [
                        const Icon(Icons.videocam_off,
                            size: 44, color: AppTheme.textSecondary),
                        const SizedBox(height: 12),
                        Text(
                          l10n.replaysEmpty,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 14),
                        ),
                      ]),
                    )
                  else
                    for (final clip in _clips!) _clipRow(clip, l10n),
                ],
              ),
      ),
    );
  }

  Widget _quotaBanner(AppLocalizations l10n) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.workspace_premium, color: AppTheme.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.replayQuotaBanner,
              style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      );

  Future<void> _rename(Map<String, dynamic> clip) async {
    final l10n = AppLocalizations.of(context);
    final controller =
        TextEditingController(text: clip['name'] as String? ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(l10n.replayRename,
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: l10n.replayNameHint,
            hintStyle: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (name == null) return;
    try {
      await ApiService.patch('/replays/${clip['id']}', {'name': name});
      _load();
    } catch (e) {
      debugPrint('[ReplayLibrary] rename failed: $e');
    }
  }

  Widget _clipRow(Map<String, dynamic> clip, AppLocalizations l10n) {
    final hot = clip['type'] == 'highlight';
    final turnTotal = (clip['turnTotal'] as num?)?.toInt();
    final created = DateTime.tryParse(clip['createdAt'] as String? ?? '');
    final accent = hot ? AppTheme.accent : AppTheme.playerBlue;
    final name = clip['name'] as String?;
    final title = name != null && name.isNotEmpty
        ? name
        : turnTotal != null && turnTotal > 0
            ? (turnTotal == 180 ? '180 🔥' : l10n.ptsLabel(turnTotal))
            : l10n.myReplays;
    final date = created == null
        ? ''
        : '${created.day.toString().padLeft(2, '0')}/'
            '${created.month.toString().padLeft(2, '0')} · '
            '${created.hour.toString().padLeft(2, '0')}:'
            '${created.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: ListTile(
        onTap: () {
          HapticService.lightImpact();
          AppNavigator.toScreen(
            context,
            ReplayPlayerScreen(
              source: clip['url'] as String,
              isLocal: false,
            ),
          );
        },
        leading: Icon(
          hot ? Icons.local_fire_department : Icons.videocam,
          color: accent,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: hot ? AppTheme.accent : Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          date,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert,
              color: AppTheme.textSecondary, size: 20),
          color: AppTheme.surface,
          onSelected: (action) {
            if (action == 'rename') _rename(clip);
            if (action == 'delete') _delete(clip['id'] as String);
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'rename',
              child: Text(l10n.replayRename,
                  style: const TextStyle(color: Colors.white)),
            ),
            PopupMenuItem(
              value: 'delete',
              child: Text(l10n.replayDelete,
                  style: const TextStyle(color: AppTheme.error)),
            ),
          ],
        ),
      ),
    );
  }
}

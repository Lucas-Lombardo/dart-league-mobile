import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/app_localizations.dart';
import '../../services/progression_service.dart';
import '../../utils/app_theme.dart';
import 'challenge_api.dart';
import 'challenge_models.dart';
import 'challenge_widgets.dart';

/// Where a visit sits in the filmed session: clip index + offset.
class ChallengeSeek {
  final int clip;
  final Duration offset;
  const ChallengeSeek(this.clip, this.offset);
}

/// Maps a visit's wall clock (confirm time, phone clock) into the clips,
/// a few seconds before the confirm so the throws are on screen. Pure.
ChallengeSeek? challengeSeekFor(List<ChallengeClip> clips, int? t, {Duration lead = const Duration(seconds: 12)}) {
  if (t == null || clips.isEmpty) return null;
  final target = t - lead.inMilliseconds;
  for (var i = 0; i < clips.length; i++) {
    final c = clips[i];
    final start = c.startWallMs;
    if (start == null) continue;
    final end = start + (c.durationMs ?? 0);
    if (t >= start && (c.durationMs == null || t <= end + 2000)) {
      final ms = (target - start).clamp(0, c.durationMs ?? (target - start).abs());
      return ChallengeSeek(i, Duration(milliseconds: ms));
    }
  }
  return null;
}

String _mmss(int ms) {
  final s = (ms / 1000).floor().clamp(0, 99 * 60);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// The public session of a n°1 (mockup ecrans/DefiVideo): the video, the
/// visits as sent (corrected ones flagged), and "Report this session".
class ChallengeSessionScreen extends StatefulWidget {
  final String crownId;
  const ChallengeSessionScreen({super.key, required this.crownId});

  @override
  State<ChallengeSessionScreen> createState() => _ChallengeSessionScreenState();
}

class _ChallengeSessionScreenState extends State<ChallengeSessionScreen> {
  ChallengeSession? _session;
  bool _failed = false;
  VideoPlayerController? _video;
  int _clip = 0;
  int? _selectedVisit;
  bool _reported = false;

  @override
  void initState() {
    super.initState();
    // Quests q044 / q089 "Watch the No. 1's session".
    ProgressionService.reportClientAction('challenge_session_viewed');
    _load();
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final s = await ChallengeApi.session(widget.crownId);
      if (!mounted) return;
      setState(() {
        _session = s;
        _reported = s.reported;
      });
      if (s.clips.isNotEmpty) await _openClip(0);
    } catch (e) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _openClip(int index, {Duration at = Duration.zero, bool play = false}) async {
    final s = _session;
    if (s == null || index >= s.clips.length) return;
    final old = _video;
    final controller = VideoPlayerController.networkUrl(Uri.parse(s.clips[index].url));
    setState(() {
      _video = controller;
      _clip = index;
    });
    await old?.dispose();
    try {
      await controller.initialize();
      if (!mounted || _video != controller) return;
      controller.addListener(_onTick);
      if (at > Duration.zero) await controller.seekTo(at);
      if (play) await controller.play();
      setState(() {});
    } catch (e) {
      debugPrint('[ChallengeSession] clip failed: $e');
    }
  }

  void _onTick() {
    final c = _video;
    final s = _session;
    if (c == null || s == null || !mounted) return;
    final v = c.value;
    if (v.isInitialized && !v.isPlaying && v.position >= v.duration && _clip + 1 < s.clips.length) {
      c.removeListener(_onTick);
      _openClip(_clip + 1, play: true);
      return;
    }
    setState(() {});
  }

  Future<void> _seekToVisit(int i) async {
    final s = _session;
    if (s == null) return;
    setState(() => _selectedVisit = i);
    final seek = challengeSeekFor(s.clips, s.visits[i].t);
    if (seek == null) return;
    if (seek.clip != _clip) {
      await _openClip(seek.clip, at: seek.offset, play: true);
    } else {
      await _video?.seekTo(seek.offset);
      await _video?.play();
    }
  }

  Future<void> _report() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final reasons = {
      'wrong_score': l10n.challengeReportReasonScore,
      'not_visible': l10n.challengeReportReasonHidden,
      'edited': l10n.challengeReportReasonEdited,
      'other': l10n.challengeReportReasonOther,
    };
    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.challengeReport, style: AppTheme.titleLarge),
              const SizedBox(height: 8),
              for (final e in reasons.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value, style: AppTheme.bodyMedium),
                  onTap: () => Navigator.of(ctx).pop(e.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (reason == null) return;
    try {
      await ChallengeApi.report(widget.crownId, reason);
      if (!mounted) return;
      setState(() => _reported = true);
      messenger.showSnackBar(SnackBar(content: Text(l10n.challengeReported)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.challengeReportFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = _session;
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
                    icon: Icons.arrow_back_ios_new_rounded,
                    semanticLabel: MaterialLocalizations.of(context).backButtonTooltip,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 12),
                  if (s != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.username, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                          Text(
                            l10n.challengeSessionSubtitle(
                              challengeBoardName(l10n, s.board),
                              s.format?.short.resolve(context) ?? '',
                              challengeDayLabel(context, s.date, short: true),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: ChallengeColors.muted),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: s == null
                  ? Center(
                      child: _failed
                          ? TextButton(onPressed: _load, child: Text(l10n.challengeRetry))
                          : const CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5),
                    )
                  : _buildBody(l10n, s),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, ChallengeSession s) {
    final t0 = s.clips.isNotEmpty ? s.clips.first.startWallMs : s.visits.firstWhere((v) => v.t != null, orElse: () => const ChallengeSessionVisit()).t;
    final corrected = s.visits.fold<int>(0, (n, v) => n + v.darts.where((d) => d.fixed).length);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
      children: [
        _buildPlayer(l10n, s),
        const SizedBox(height: 14),
        for (var i = 0; i < s.visits.length; i++) ...[
          _VisitTile(
            visit: s.visits[i],
            time: s.visits[i].t != null && t0 != null ? _mmss(s.visits[i].t! - t0) : '',
            selected: _selectedVisit == i,
            onTap: () => _seekToVisit(i),
          ),
          const SizedBox(height: 6),
        ],
        if (corrected > 0) ...[
          const SizedBox(height: 8),
          Text(l10n.challengeCorrectedVisits(s.username, corrected), style: const TextStyle(fontSize: 13, height: 1.45, color: ChallengeColors.soft)),
        ],
        const SizedBox(height: 16),
        if (s.reportable)
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: ChallengeColors.text,
                side: const BorderSide(color: ChallengeColors.slate700),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.flag_outlined, size: 18),
              label: Text(_reported ? l10n.challengeReported : l10n.challengeReport),
              onPressed: _reported ? null : _report,
            ),
          ),
      ],
    );
  }

  Widget _buildPlayer(AppLocalizations l10n, ChallengeSession s) {
    final c = _video;
    final ready = c != null && c.value.isInitialized;
    final visit = _selectedVisit != null ? s.visits[_selectedVisit!] : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 330,
        color: const Color(0xFF0B0E12),
        child: s.clips.isEmpty
            ? Center(child: Text(l10n.challengeSessionNoVideo, style: AppTheme.bodyMedium))
            : Stack(
                fit: StackFit.expand,
                children: [
                  if (ready)
                    FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(width: c.value.size.width, height: c.value.size.height, child: VideoPlayer(c)),
                    )
                  else
                    const Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5)),
                  if (visit != null && visit.value != null)
                    Positioned(
                      top: 12,
                      left: 12,
                      child: _Overlay(l10n.challengeVisitOverlay(_selectedVisit! + 1, visit.value!)),
                    ),
                  Positioned(top: 12, right: 12, child: _Overlay(l10n.challengePlayerCamera)),
                  if (ready)
                    Center(
                      child: Semantics(
                        button: true,
                        label: c.value.isPlaying ? l10n.challengePause : l10n.challengePlay,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => c.value.isPlaying ? c.pause() : c.play(),
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xBF0F172A),
                              border: Border.all(color: const Color(0x33FFFFFF)),
                            ),
                            child: Icon(c.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: ChallengeColors.text, size: 30),
                          ),
                        ),
                      ),
                    ),
                  if (ready)
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 10,
                      child: Column(
                        children: [
                          VideoProgressIndicator(
                            c,
                            allowScrubbing: true,
                            colors: const VideoProgressColors(playedColor: ChallengeColors.accent, backgroundColor: Color(0x2EFFFFFF)),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_mmss(c.value.position.inMilliseconds), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ChallengeColors.soft)),
                              Text(
                                s.clips.length > 1 ? '${_clip + 1}/${s.clips.length} · ${_mmss(c.value.duration.inMilliseconds)}' : _mmss(c.value.duration.inMilliseconds),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ChallengeColors.soft),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  final String text;
  const _Overlay(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xCC0F172A),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: ChallengeColors.softer)),
      );
}

class _VisitTile extends StatelessWidget {
  final ChallengeSessionVisit visit;
  final String time;
  final bool selected;
  final VoidCallback onTap;
  const _VisitTile({required this.visit, required this.time, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: selected ? Border.all(color: ChallengeColors.accent, width: 1.5) : null,
        ),
        child: Row(
          children: [
            SizedBox(width: 40, child: Text(time, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ChallengeColors.muted))),
            Expanded(
              child: Text(
                visit.darts.map((d) => d.notation).join(' · '),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.2),
              ),
            ),
            if (visit.corrected)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0x29F97316), borderRadius: BorderRadius.circular(999)),
                child: Text(l10n.challengeSessionCorrected, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFFFDBA74))),
              ),
            SizedBox(
              width: 44,
              child: Text(
                visit.value == null ? '' : '${visit.value}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

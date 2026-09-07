import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/turn_report_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';

/// Step 1 of 2 at the end of a match: the visits flagged during play, waiting
/// for a reason. Step 2 is the existing result screen (accept / refuse) — the
/// two never mix, because they answer different questions: this one is about
/// behaviour, the next one about the score.
///
/// Shown only to a player who actually flagged something. A match with no flag
/// goes straight to the result screen, exactly as before.
///
/// Each row opens the report dialog the app already has — same reasons, same
/// comment field — titled by the visit it concerns. Nothing new to learn, and
/// the dialog stays the single place where a reason is chosen.
///
/// System D: a 24 / 800 sentence-case title with the "1 / 2" step, one
/// caption, 64 px card rows ("Sa volée à 140" + a status pill + chevron, or a
/// close button once the reason is set), then ONE primary button and a quiet
/// "Passer".
class TurnReportsView extends StatefulWidget {
  /// Opens the reason/comment dialog for one report and resolves once closed.
  final Future<void> Function(PendingTurnReport report) onEdit;

  /// Sends what has a reason, drops the rest, and moves to the result screen.
  final VoidCallback onContinue;

  const TurnReportsView({
    super.key,
    required this.onEdit,
    required this.onContinue,
  });

  @override
  State<TurnReportsView> createState() => _TurnReportsViewState();
}

class _TurnReportsViewState extends State<TurnReportsView> {
  Future<void> _edit(PendingTurnReport report) async {
    await widget.onEdit(report);
    if (mounted) setState(() {});
  }

  void _remove(PendingTurnReport report) {
    HapticService.lightImpact();
    setState(() {
      report.reason = null;
      report.comment = null;
      TurnReportService.pending.remove(report);
    });
    if (TurnReportService.pending.isEmpty) widget.onContinue();
  }

  String _label(AppLocalizations l10n, PendingTurnReport report) {
    if (report.isWinningVolley) {
      return report.legNumber != null
          ? l10n.turnReportWinningLabel(report.legNumber!)
          : l10n.turnReportWinningNoLeg;
    }
    final turn = report.turnIndex ?? 0;
    return report.legNumber != null
        ? l10n.turnReportLegTurn(report.legNumber!, turn)
        : l10n.turnReportTurnOnly(turn);
  }

  void _continue() {
    HapticService.mediumImpact();
    widget.onContinue();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reports = TurnReportService.pending;
    final ready = reports.where((r) => r.isComplete).length;
    final blank = reports.length - ready;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      dsSentence(l10n.turnReportsTitle),
                      style: AppTheme.displayMedium,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '1 / 2',
                      style: AppTheme.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(l10n.turnReportsIntro(reports.length), style: AppTheme.bodyMedium),
              const SizedBox(height: 20),
              Expanded(
                child: ListView.separated(
                  itemCount: reports.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _row(l10n, reports[index]),
                ),
              ),
              if (blank > 0) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.turnReportDropWarning(blank),
                  textAlign: TextAlign.center,
                  style: AppTheme.caption,
                ),
              ],
              const SizedBox(height: 14),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: ready > 0 ? _continue : null,
                  child: Text(dsSentence(l10n.turnReportSubmit(ready))),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _continue,
                style: TextButton.styleFrom(foregroundColor: AppTheme.textSecondary),
                child: Text(dsSentence(l10n.turnReportSkip)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(AppLocalizations l10n, PendingTurnReport report) {
    final done = report.isComplete;
    return SizedBox(
      height: 64,
      child: DsCard(
        radius: AppTheme.radiusRow,
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
        onTap: () => _edit(report),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.volleyScore != null
                        ? l10n.turnReportVisitScore(report.volleyScore!)
                        : dsSentence(l10n.turnReportDialogTitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.rowTitle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    done ? report.reason! : _label(l10n, report),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            DsPill(
              label: dsSentence(done ? l10n.turnReportReady : l10n.turnReportTodo),
              color: done ? AppTheme.success : AppTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            if (done)
              DsIconButton(
                icon: Icons.close_rounded,
                size: 32,
                tooltip: dsSentence(l10n.turnReportRemove),
                onTap: () => _remove(report),
              )
            else
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

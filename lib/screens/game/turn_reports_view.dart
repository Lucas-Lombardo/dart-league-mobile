import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/turn_report_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reports = TurnReportService.pending;
    final ready = reports.where((r) => r.isComplete).length;
    final blank = reports.length - ready;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.surfaceGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag, color: AppTheme.opponentPink, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.turnReportsTitle,
                        style: const TextStyle(
                          color: AppTheme.opponentPink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    Text(
                      '1 / 2',
                      style: TextStyle(
                        color: AppTheme.textSecondary.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.turnReportsIntro(reports.length),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: ListView.separated(
                    itemCount: reports.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _row(l10n, reports[index]),
                  ),
                ),
                if (blank > 0) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.turnReportDropWarning(blank),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: () {
                      HapticService.mediumImpact();
                      widget.onContinue();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          ready > 0 ? AppTheme.opponentPink : AppTheme.surface,
                      foregroundColor: ready > 0
                          ? Colors.white
                          : AppTheme.textSecondary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      ready > 0
                          ? l10n.turnReportSubmit(ready)
                          : l10n.turnReportSkip,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(AppLocalizations l10n, PendingTurnReport report) {
    final done = report.isComplete;
    return InkWell(
      onTap: () => _edit(report),
      borderRadius: BorderRadius.circular(14),
      // Two boxes, on purpose: a Border whose sides have DIFFERENT colours is
      // illegal with a borderRadius. It threw on EVERY paint of the row — the
      // exception is caught per render object, so in debug the row painted its
      // background and then nothing else (device test 2026-08-13), and in
      // release the corners came out square. The rounded outline lives on the
      // outer box, the accent bar on the inner one, whose own decoration has no
      // radius; the clip rounds it back.
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.surfaceLight.withValues(alpha: 0.4),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: AppTheme.gamePanelEmpty,
              border: Border(
                left: BorderSide(
                  color: report.isWinningVolley
                      ? AppTheme.accent
                      : AppTheme.opponentPink,
                  width: 2.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _label(l10n, report),
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        report.volleyScore != null
                            ? l10n.turnReportVisitScore(report.volleyScore!)
                            : l10n.turnReportDialogTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        done
                            ? '✓ ${report.reason}'
                            : '◷ ${l10n.turnReportTodo}',
                        style: TextStyle(
                          color: done ? AppTheme.success : AppTheme.accent,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                if (done)
                  IconButton(
                    onPressed: () => _remove(report),
                    icon: const Icon(Icons.close, size: 18),
                    color: AppTheme.textSecondary,
                    tooltip: l10n.turnReportRemove,
                  )
                else
                  const Icon(Icons.chevron_right,
                      color: AppTheme.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

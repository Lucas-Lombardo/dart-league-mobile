import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/referee_match.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../utils/orientation_utils.dart';
import '../../widgets/design_system.dart';
import '../../widgets/game_turn_ui.dart';
import 'local_match_widgets.dart';
import 'referee_match_widgets.dart';

/// A shared-phone match. The synchronous model owns all official scoring;
/// this screen owns only the input selection and confirmation dialogs.
class RefereeMatchScreen extends StatefulWidget {
  final RefereeMatch match;
  const RefereeMatchScreen({super.key, required this.match});

  @override
  State<RefereeMatchScreen> createState() => _RefereeMatchScreenState();
}

class _RefereeMatchScreenState extends State<RefereeMatchScreen> {
  RefereeMatch get match => widget.match;
  int _multiplier = 1;
  bool _busy = false;
  bool _allowPop = false;
  final _editorScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    OrientationUtils.allowAll();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    _editorScroll.dispose();
    WakelockPlus.disable();
    OrientationUtils.portraitOnly();
    super.dispose();
  }

  void _change(VoidCallback action) {
    if (_busy) return;
    HapticService.lightImpact();
    setState(action);
  }

  void _resetInputView() {
    _multiplier = 1;
    if (_editorScroll.hasClients) _editorScroll.jumpTo(0);
  }

  Future<void> _leave() async {
    if (_busy) return;
    _busy = true;
    final leave =
        match.winner != null || await showLeaveLocalMatchDialog(context);
    if (!mounted) return;
    _busy = false;
    if (leave) {
      setState(() => _allowPop = true);
      // Let PopScope receive canPop before handling the route pop.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _switchMode(RefereeInputMode mode) async {
    if (_busy || mode == match.inputMode) return;
    if (mode == RefereeInputMode.total) {
      _change(match.useTotal);
    } else if (match.useDarts()) {
      setState(() {});
    } else {
      _busy = true;
      final l10n = AppLocalizations.of(context);
      final discard = await showGameDialog<bool>(
        context,
        accent: AppTheme.primary,
        icon: Icons.calculate_outlined,
        title: l10n.refereeHelpTab,
        content: Text(
          l10n.refereeSwitchWarning(int.tryParse(match.totalInput) ?? 0),
          style: AppTheme.bodyMedium,
        ),
        actionsBuilder: (ctx) => [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(dsSentence(l10n.cancel)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.refereeRecalculate),
          ),
        ],
      );
      if (!mounted) return;
      _busy = false;
      if (discard != true) return;
      setState(() => match.useDarts(discardTotal: true));
    }
    _resetInputView();
  }

  void _dart(RefereeDart dart) {
    _change(() {
      if (match.enterDart(dart)) {
        // Most following darts are singles. Each double/triple is explicit.
        _multiplier = 1;
      } else {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).refereeDartsFull),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  Future<void> _validate({bool forceBust = false}) async {
    if (_busy ||
        !match.canEnter ||
        (!forceBust && !match.preview.canValidate)) {
      return;
    }
    _busy = true;
    final l10n = AppLocalizations.of(context);
    final draft = match.preview;
    var bust = forceBust || draft.kind == RefereeVisitKind.bust;
    int? checkoutDarts;
    if (bust) {
      final confirmed = await showGameDialog<bool>(
        context,
        accent: AppTheme.error,
        icon: Icons.undo_rounded,
        title: dsSentence(l10n.bust),
        content: Text(
          l10n.refereeBustExplanation(
            match.config.nameOf(match.activePlayer),
            match.scores[match.activePlayer],
          ),
          style: AppTheme.bodyMedium,
        ),
        actionsBuilder: (ctx) => [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(dsSentence(l10n.cancel)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.refereeValidateVisit),
          ),
        ],
      );
      if (!mounted) return;
      if (confirmed != true) {
        setState(() => _busy = false);
        return;
      }
    } else if (draft.kind == RefereeVisitKind.finish) {
      final result = await showGameDialog<int>(
        context,
        accent: localPlayerColor(match.activePlayer),
        icon: Icons.check_circle_outline,
        title: match.config.doubleOut
            ? l10n.refereeFinishDoubleTitle
            : l10n.refereeFinishTitle,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              draft.finishDartCounts.length == 1
                  ? l10n.refereeFinishKnown
                  : l10n.refereeFinishQuestion,
              style: AppTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final count in draft.finishDartCounts)
                  ElevatedButton(
                    key: ValueKey('referee-checkout-$count'),
                    onPressed: () => Navigator.pop(context, count),
                    child: Text(l10n.refereeDartCount(count)),
                  ),
              ],
            ),
          ],
        ),
        actionsBuilder: (ctx) => [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(dsSentence(l10n.cancel)),
          ),
          if (match.config.doubleOut)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 0),
              child: Text(l10n.refereeNoDouble),
            ),
        ],
      );
      if (!mounted) return;
      if (result == null) {
        setState(() => _busy = false);
        return;
      }
      bust = result == 0;
      checkoutDarts = bust ? null : result;
    }
    if (!mounted) return;
    HapticService.mediumImpact();
    setState(() {
      match.validateVisit(bust: bust, checkoutDarts: checkoutDarts);
      _busy = false;
      _resetInputView();
    });
  }

  void _undo() {
    _change(() {
      match.undo();
      _resetInputView();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).refereeUndoDone),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _history() {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .7,
        child: Column(
          children: [
            Text(dsSentence(l10n.history), style: AppTheme.titleLarge),
            const SizedBox(height: 8),
            Expanded(
              child: match.history.isEmpty
                  ? Center(child: Text(l10n.refereeHistoryEmpty))
                  : ListView.builder(
                      itemCount: match.history.length,
                      itemBuilder: (ctx, index) {
                        final visit = match.history.reversed.elementAt(index);
                        return ListTile(
                          leading: Text(
                            visit.bust ? '0' : '${visit.points}',
                            style: AppTheme.titleLarge.copyWith(
                              color: localPlayerColor(visit.player),
                            ),
                          ),
                          title: Text(match.config.nameOf(visit.player)),
                          subtitle: Text(
                            'Leg ${visit.leg} · ${l10n.refereeHistoryScore(visit.before, visit.points, visit.after)}'
                            '${visit.darts == null ? '' : '\n${visit.darts!.map((d) => d.notation).join(' · ')}'}',
                          ),
                          trailing: visit.bust
                              ? Text(dsSentence(l10n.bust))
                              : visit.checkout
                              ? const Icon(
                                  Icons.flag_outlined,
                                  color: AppTheme.success,
                                )
                              : null,
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton.icon(
                  onPressed: match.canUndo
                      ? () {
                          Navigator.pop(ctx);
                          _undo();
                        }
                      : null,
                  icon: const Icon(Icons.undo_rounded),
                  label: Text(l10n.refereeUndo),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs(AppLocalizations l10n) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        for (final mode in RefereeInputMode.values) ...[
          if (mode == RefereeInputMode.darts) const SizedBox(width: 6),
          Expanded(
            child: RefereeKey(
              key: ValueKey('referee-tab-${mode.name}'),
              height: 40,
              label: mode == RefereeInputMode.total
                  ? l10n.refereeTotalTab
                  : l10n.refereeHelpTab,
              selected: match.inputMode == mode,
              onTap: () => _switchMode(mode),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _editor(AppLocalizations l10n) => SingleChildScrollView(
    controller: _editorScroll,
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      children: [
        if (match.preview.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              match.preview.error == RefereeInputError.impossibleTotal
                  ? l10n.refereeImpossibleTotal
                  : l10n.refereeDartsAfterEnd,
              style: const TextStyle(color: AppTheme.error),
              textAlign: TextAlign.center,
            ),
          ),
        if (match.inputMode == RefereeInputMode.total)
          RefereeTotalPad(
            match: match,
            onDigit: (n) => _change(() => match.enterDigit(n)),
            onPreset: (n) => _change(() => match.setTotal(n)),
            onClear: () => _change(match.clearDraft),
            onBackspace: () => _change(match.backspace),
          )
        else
          RefereeDartPad(
            match: match,
            multiplier: _multiplier,
            onMultiplier: (m) => _change(() => _multiplier = m),
            onDart: _dart,
            onSelect: (i) => _change(() {
              match.selectDart(i);
              _multiplier = i < match.draftDarts.length
                  ? match.draftDarts[i].multiplier
                  : 1;
            }),
            onRemove: (i) => _change(() {
              match.removeDart(i);
              _multiplier = 1;
            }),
          ),
      ],
    ),
  );

  Widget _actions(AppLocalizations l10n) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(height: 6),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          key: const ValueKey('referee-validate'),
          style: ElevatedButton.styleFrom(
            backgroundColor: localPlayerColor(match.activePlayer),
            foregroundColor: AppTheme.background,
            minimumSize: const Size(0, 50),
          ),
          onPressed: !_busy && match.preview.canValidate
              ? () => _validate()
              : null,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              Text(l10n.refereeValidateVisit),
              if (match.preview.canValidate)
                Text(
                  match.preview.kind == RefereeVisitKind.bust
                      ? dsSentence(l10n.bust)
                      : l10n.refereeDartPoints(match.preview.points),
                ),
            ],
          ),
        ),
      ),
      Row(
        children: [
          Expanded(
            child: TextButton(
              key: const ValueKey('referee-undo'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: match.canUndo && !_busy ? _undo : null,
              child: Text(l10n.refereeUndoShort),
            ),
          ),
          Expanded(
            child: TextButton(
              key: const ValueKey('referee-force-bust'),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _busy ? null : () => _validate(forceBust: true),
              child: Text(dsSentence(l10n.bust)),
            ),
          ),
          if (match.inputMode == RefereeInputMode.darts)
            IconButton(
              key: const ValueKey('referee-clear-darts'),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              tooltip: l10n.refereeClearDarts,
              onPressed: match.draftDarts.isEmpty || _busy
                  ? null
                  : () => _change(() {
                      match.clearDraft();
                      _multiplier = 1;
                    }),
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
    ],
  );

  Widget _legEnd(AppLocalizations l10n) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(
            Icons.flag_outlined,
            size: 56,
            color: localPlayerColor(match.legWinner!),
          ),
          const SizedBox(height: 16),
          Text(dsSentence(l10n.legWon), style: AppTheme.titleLarge),
          Text(
            match.config.nameOf(match.legWinner!),
            style: AppTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          RefereeScoreboard(match: match),
          const SizedBox(height: 24),
          ElevatedButton(
            key: const ValueKey('referee-next-leg'),
            onPressed: () => _change(() {
              match.startNextLeg();
              _resetInputView();
            }),
            child: Text(dsSentence(l10n.nextLeg)),
          ),
          TextButton(onPressed: _undo, child: Text(l10n.refereeUndo)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.refereeMode),
              Text(
                '501 · ${match.config.doubleOut ? l10n.doubleOutLabel : l10n.refereeStraightOut}',
                style: AppTheme.caption,
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _leave,
          ),
          actions: [
            IconButton(
              key: const ValueKey('referee-history'),
              tooltip: dsSentence(l10n.history),
              onPressed: _history,
              icon: const Icon(Icons.history_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: match.winner != null
              ? LocalMatchEndView(
                  config: match.config,
                  winner: match.winner!,
                  legsWon: match.legs,
                  stats: [
                    RefereeScoreboard(match: match),
                    TextButton(
                      key: const ValueKey('referee-undo-win'),
                      onPressed: _undo,
                      child: Text(l10n.refereeUndo),
                    ),
                  ],
                  onRematch: () => _change(() {
                    match.restart();
                    _resetInputView();
                  }),
                  onBack: _leave,
                  backLabel: l10n.refereeBackToSetup,
                )
              : match.legWinner != null
              ? _legEnd(l10n)
              : LayoutBuilder(
                  builder: (context, box) {
                    final landscape = box.maxWidth > box.maxHeight * 1.25;
                    final compact = box.maxHeight < 620;
                    final header = Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 2),
                        RefereeScoreboard(match: match, compact: true),
                        RefereeRemaining(match: match, compact: compact),
                        _tabs(l10n),
                      ],
                    );
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: landscape
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: SingleChildScrollView(child: header),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  flex: 5,
                                  child: Column(
                                    children: [
                                      Expanded(child: _editor(l10n)),
                                      _actions(l10n),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: [
                                header,
                                Expanded(child: _editor(l10n)),
                                _actions(l10n),
                              ],
                            ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

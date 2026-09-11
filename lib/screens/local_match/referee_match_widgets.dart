import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/referee_match.dart';
import '../../utils/app_theme.dart';
import '../../widgets/design_system.dart';
import 'local_match_widgets.dart';

class RefereeScoreboard extends StatelessWidget {
  final RefereeMatch match;
  final bool compact;
  const RefereeScoreboard({
    super.key,
    required this.match,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final number = NumberFormat(
      '0.0',
      Localizations.localeOf(context).toString(),
    );
    return Row(
      children: [
        for (var player = 0; player < 2; player++) ...[
          if (player == 1) const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(compact ? 6 : 12),
              decoration: BoxDecoration(
                color: match.activePlayer == player
                    ? localPlayerColor(player).withValues(alpha: .06)
                    : AppTheme.gamePanelEmpty,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: match.activePlayer == player
                      ? localPlayerColor(player).withValues(alpha: .65)
                      : AppTheme.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.circle,
                        size: 7,
                        color: localPlayerColor(player),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          match.config.nameOf(player),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          '${match.scores[player]}',
                          key: ValueKey('referee-score-$player'),
                          style: AppTheme.displayLarge.copyWith(
                            fontSize: compact ? 30 : 38,
                            color: localPlayerColor(player),
                          ),
                        ),
                      ),
                      Text(
                        '${match.legs[player]} ${l10n.legsUnit(match.legs[player])}',
                        style: AppTheme.caption,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Tooltip(
                    message: l10n.refereeAverageHint,
                    child: Text(
                      '${dsSentence(l10n.avgLabel)} ${match.averageOf(player) == null ? '—' : number.format(match.averageOf(player))}',
                      key: ValueKey('referee-average-$player'),
                      style: AppTheme.caption,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class RefereeRemaining extends StatelessWidget {
  final RefereeMatch match;
  final bool compact;
  const RefereeRemaining({
    super.key,
    required this.match,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = match.preview;
    final isBust = draft.kind == RefereeVisitKind.bust;
    return Column(
      children: [
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.turnOf(match.config.nameOf(match.activePlayer)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: localPlayerColor(match.activePlayer),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              l10n.refereeLegStatus(match.legNumber, match.config.legsToWin),
              style: AppTheme.caption.copyWith(fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(l10n.refereeAnnounceRemaining, style: AppTheme.caption),
        Semantics(
          liveRegion: true,
          child: Text(
            isBust ? dsSentence(l10n.bust) : '${draft.remaining}',
            key: const ValueKey('referee-remaining'),
            style: AppTheme.displayLarge.copyWith(
              fontSize: compact ? 46 : 52,
              color: isBust
                  ? AppTheme.error
                  : localPlayerColor(match.activePlayer),
            ),
          ),
        ),
        Text(
          l10n.refereeCalculation(
            match.scores[match.activePlayer],
            draft.points,
          ),
          textAlign: TextAlign.center,
          style: AppTheme.caption,
        ),
        const SizedBox(height: 2),
      ],
    );
  }
}

class RefereeTotalPad extends StatelessWidget {
  final RefereeMatch match;
  final ValueChanged<int> onDigit;
  final ValueChanged<int> onPreset;
  final VoidCallback onClear;
  final VoidCallback onBackspace;
  const RefereeTotalPad({
    super.key,
    required this.match,
    required this.onDigit,
    required this.onPreset,
    required this.onClear,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
          decoration: BoxDecoration(
            color: AppTheme.gamePanelEmpty,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            children: [
              Text(
                l10n.refereeTotalHint,
                style: AppTheme.caption,
                textAlign: TextAlign.center,
              ),
              Text(
                match.totalInput.isEmpty ? '—' : match.totalInput,
                key: const ValueKey('referee-total-input'),
                style: AppTheme.displayLarge.copyWith(fontSize: 34),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final points in [26, 45, 60, 100]) ...[
              if (points != 26) const SizedBox(width: 6),
              Expanded(
                child: RefereeKey(
                  label: '$points',
                  height: 40,
                  onTap: () => onPreset(points),
                  key: ValueKey('referee-preset-$points'),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < 4; row++) ...[
          if (row > 0) const SizedBox(height: 6),
          Row(
            children: [
              for (var column = 0; column < 3; column++) ...[
                if (column > 0) const SizedBox(width: 6),
                Expanded(
                  child: row == 3 && column != 1
                      ? RefereeKey(
                          label: column == 0 ? 'C' : '⌫',
                          height: 48,
                          semanticLabel: column == 0
                              ? l10n.refereeClear
                              : l10n.refereeBackspace,
                          onTap: column == 0 ? onClear : onBackspace,
                          key: ValueKey(
                            column == 0 ? 'referee-clear' : 'referee-backspace',
                          ),
                        )
                      : RefereeKey(
                          label: '${row == 3 ? 0 : row * 3 + column + 1}',
                          height: 48,
                          large: true,
                          onTap: () =>
                              onDigit(row == 3 ? 0 : row * 3 + column + 1),
                          key: ValueKey(
                            'referee-digit-${row == 3 ? 0 : row * 3 + column + 1}',
                          ),
                        ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class RefereeDartPad extends StatelessWidget {
  final RefereeMatch match;
  final int multiplier;
  final ValueChanged<int> onMultiplier;
  final ValueChanged<RefereeDart> onDart;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRemove;
  const RefereeDartPad({
    super.key,
    required this.match,
    required this.multiplier,
    required this.onMultiplier,
    required this.onDart,
    required this.onSelect,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final darts = match.draftDarts;
    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _DartSlot(
                  index: i,
                  dart: i < darts.length ? darts[i] : null,
                  selected:
                      match.editingDart == i ||
                      (match.editingDart == null && darts.length == i),
                  color: localPlayerColor(match.activePlayer),
                  onSelect: () => onSelect(i),
                  onRemove: () => onRemove(i),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var m = 1; m <= 3; m++) ...[
              if (m > 1) const SizedBox(width: 6),
              Expanded(
                child: RefereeKey(
                  key: ValueKey('referee-multiplier-$m'),
                  height: 38,
                  label: dsSentence(
                    [l10n.singleUpper, l10n.doubleUpper, l10n.tripleUpper][m -
                        1],
                  ),
                  selected: multiplier == m,
                  onTap: () => onMultiplier(m),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < 4; row++) ...[
          if (row > 0) const SizedBox(height: 6),
          Row(
            children: [
              for (var col = 0; col < 5; col++) ...[
                if (col > 0) const SizedBox(width: 6),
                Expanded(
                  child: RefereeKey(
                    label: '${20 - row * 5 - col}',
                    large: true,
                    key: ValueKey('referee-dart-${20 - row * 5 - col}'),
                    height: 40,
                    onTap: () =>
                        onDart(RefereeDart(20 - row * 5 - col, multiplier)),
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: RefereeKey(
                label: l10n.refereeMiss,
                height: 40,
                key: const ValueKey('referee-miss'),
                onTap: () => onDart(RefereeDart(0)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: RefereeKey(
                label: dsSentence(l10n.bull25),
                height: 40,
                key: const ValueKey('referee-bull-25'),
                onTap: () => onDart(RefereeDart(25)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: RefereeKey(
                label: dsSentence(l10n.bull50),
                height: 40,
                key: const ValueKey('referee-bull-50'),
                onTap: () => onDart(RefereeDart(25, 2)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DartSlot extends StatelessWidget {
  final int index;
  final RefereeDart? dart;
  final bool selected;
  final Color color;
  final VoidCallback onSelect;
  final VoidCallback onRemove;
  const _DartSlot({
    required this.index,
    required this.dart,
    required this.selected,
    required this.color,
    required this.onSelect,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Stack(
      children: [
        Material(
          color: dart == null
              ? AppTheme.gamePanelEmpty
              : color.withValues(alpha: .08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: selected ? color : AppTheme.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onSelect,
            key: ValueKey('referee-slot-$index'),
            child: Semantics(
              label: l10n.refereeCorrectDart(index + 1),
              selected: selected,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 24, 4, 6),
                  child: Column(
                    children: [
                      Text(
                        l10n.dartNumber(index + 1),
                        style: AppTheme.caption.copyWith(fontSize: 11),
                      ),
                      Text(
                        dart?.notation ?? '—',
                        style: AppTheme.displayLarge.copyWith(
                          fontSize: 28,
                          color: dart == null ? AppTheme.textTertiary : color,
                        ),
                      ),
                      Text(
                        dart == null
                            ? l10n.refereeWaitingDart
                            : l10n.refereeDartPoints(dart!.points),
                        style: AppTheme.caption.copyWith(fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (dart != null)
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              key: ValueKey('referee-remove-$index'),
              tooltip: l10n.refereeDeleteDart(index + 1),
              onPressed: onRemove,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: const EdgeInsets.all(6),
              iconSize: 17,
              icon: const Icon(
                Icons.close_rounded,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

class RefereeKey extends StatelessWidget {
  final String label;
  final String? semanticLabel;
  final double height;
  final bool selected;
  final bool large;
  final VoidCallback onTap;
  const RefereeKey({
    super.key,
    required this.label,
    required this.onTap,
    this.height = 44,
    this.selected = false,
    this.large = false,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: semanticLabel,
    child: Material(
      color: selected
          ? AppTheme.primary.withValues(alpha: .15)
          : AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? AppTheme.primary : AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: large ? 23 : 13,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppTheme.primaryLight
                      : AppTheme.textPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

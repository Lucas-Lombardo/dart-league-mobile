import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/cricket.dart';
import '../../models/local_match_config.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/cricket_variant_segment.dart';
import '../../widgets/design_system.dart';
import 'local_match_camera_setup_screen.dart';

/// Pre-match configuration for a local 1v1 (hot-seat) game: player names,
/// game mode (X01 with starting score + double-out, or cricket with its
/// score / no-score variant) and match length. Nothing is persisted.
class LocalMatchSetupScreen extends StatefulWidget {
  const LocalMatchSetupScreen({super.key});

  @override
  State<LocalMatchSetupScreen> createState() => _LocalMatchSetupScreenState();
}

class _LocalMatchSetupScreenState extends State<LocalMatchSetupScreen> {
  final _player1 = TextEditingController();
  final _player2 = TextEditingController();
  LocalGameMode _gameMode = LocalGameMode.x01;
  CricketScoreMode _cricketScoreMode = CricketScoreMode.score;
  int _startingScore = 501;
  int _bestOf = 3;
  bool _doubleOut = true;

  @override
  void dispose() {
    _player1.dispose();
    _player2.dispose();
    super.dispose();
  }

  int get _legsToWin => (_bestOf ~/ 2) + 1;
  bool get _isCricket => _gameMode == LocalGameMode.cricket;

  void _start() {
    final l10n = AppLocalizations.of(context);
    HapticService.mediumImpact();
    final p1 = _player1.text.trim();
    final p2 = _player2.text.trim();
    final config = LocalMatchConfig(
      gameMode: _gameMode,
      cricketScoreMode: _cricketScoreMode,
      startingScore: _startingScore,
      bestOf: _bestOf,
      doubleOut: _doubleOut,
      player1Name: p1.isEmpty ? l10n.player1DefaultName : p1,
      player2Name: p2.isEmpty ? l10n.player2DefaultName : p2,
    );
    AppNavigator.toScreen<void>(
      context,
      LocalMatchCameraSetupScreen(config: config),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: Text(l10n.localMatchSetupTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                children: [
                  _SectionLabel(l10n.playersLabel),
                  const SizedBox(height: 10),
                  _VersusCard(
                    player1: _player1,
                    player2: _player2,
                    hint1: l10n.player1DefaultName,
                    hint2: l10n.player2DefaultName,
                  ),
                  const SizedBox(height: 28),
                  _SectionLabel(l10n.botSetupModeSection),
                  const SizedBox(height: 10),
                  _OptionRow<LocalGameMode>(
                    value: _gameMode,
                    options: [
                      _Opt(LocalGameMode.x01, 'X01', '301 · 501 · 701'),
                      _Opt(LocalGameMode.cricket, l10n.cricketLabel,
                          '15–20 · Bull'),
                    ],
                    onChanged: (v) {
                      HapticService.lightImpact();
                      setState(() => _gameMode = v);
                    },
                  ),
                  if (_isCricket) ...[
                    const SizedBox(height: 10),
                    CricketVariantSegment(
                      value: _cricketScoreMode,
                      onChanged: (v) {
                        HapticService.lightImpact();
                        setState(() => _cricketScoreMode = v);
                      },
                      scoreHint: l10n.localCricketScoreHint,
                    ),
                  ] else ...[
                    const SizedBox(height: 28),
                    _SectionLabel(l10n.startingScoreLabel),
                    const SizedBox(height: 10),
                    _OptionRow<int>(
                      value: _startingScore,
                      options: [
                        _Opt(301, '301', l10n.pointsLabel),
                        _Opt(501, '501', l10n.pointsLabel),
                        _Opt(701, '701', l10n.pointsLabel),
                      ],
                      onChanged: (v) {
                        HapticService.lightImpact();
                        setState(() => _startingScore = v);
                      },
                    ),
                  ],
                  const SizedBox(height: 28),
                  _SectionLabel(l10n.matchLengthLabel),
                  const SizedBox(height: 10),
                  _OptionRow<int>(
                    value: _bestOf,
                    options: [
                      _Opt(1, '1', l10n.legsUnit(1)),
                      _Opt(3, '3', l10n.legsUnit(3)),
                      _Opt(5, '5', l10n.legsUnit(5)),
                    ],
                    onChanged: (v) {
                      HapticService.lightImpact();
                      setState(() => _bestOf = v);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.flag_outlined,
                          color: AppTheme.textSecondary, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n.firstToNLegs(_legsToWin),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.caption,
                        ),
                      ),
                    ],
                  ),
                  if (!_isCricket) ...[
                    const SizedBox(height: 28),
                    _SectionLabel(l10n.rulesLabel),
                    const SizedBox(height: 10),
                    DsCard(
                      radius: AppTheme.radiusRow,
                      padding: EdgeInsets.zero,
                      child: SwitchListTile(
                        value: _doubleOut,
                        onChanged: (v) {
                          HapticService.lightImpact();
                          setState(() => _doubleOut = v);
                        },
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        secondary: const Icon(Icons.adjust_rounded,
                            color: AppTheme.textSecondary, size: 20),
                        title: Text(l10n.doubleOutLabel,
                            style: AppTheme.rowTitle),
                        subtitle: Text(l10n.doubleOutHint,
                            style: AppTheme.caption),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // The one filled block of the screen.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _start,
                  child: Text(dsSentence(l10n.startMatchButton)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Versus players card ──────────────────────────────────────────────────────

/// One card, two themed name fields and a quiet "vs" rule between them —
/// no gradient, no badge disc.
class _VersusCard extends StatelessWidget {
  final TextEditingController player1;
  final TextEditingController player2;
  final String hint1;
  final String hint2;

  const _VersusCard({
    required this.player1,
    required this.player2,
    required this.hint1,
    required this.hint2,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DsCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _PlayerField(
            controller: player1,
            hint: hint1,
            number: 1,
            color: AppTheme.primaryLight,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const Expanded(child: Divider(color: AppTheme.border, height: 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    l10n.vs,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ),
                const Expanded(child: Divider(color: AppTheme.border, height: 1)),
              ],
            ),
          ),
          _PlayerField(
            controller: player2,
            hint: hint2,
            number: 2,
            color: AppTheme.opponentPinkBright,
          ),
        ],
      ),
    );
  }
}

class _PlayerField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int number;
  final Color color;

  const _PlayerField({
    required this.controller,
    required this.hint,
    required this.number,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: AppTheme.rowTitle,
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      maxLength: 20,
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textTertiary),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 10),
          child: Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: AppTheme.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusControl),
          borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
        ),
      ),
    );
  }
}

// ── Option chips (mode / score / length) ─────────────────────────────────────

class _Opt<T> {
  final T value;
  final String label;
  final String caption;
  const _Opt(this.value, this.label, this.caption);
}

class _OptionRow<T> extends StatelessWidget {
  final T value;
  final List<_Opt<T>> options;
  final ValueChanged<T> onChanged;

  const _OptionRow({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < options.length; i++) ...[
          Expanded(
            child: _OptionCard(
              label: options[i].label,
              caption: options[i].caption,
              selected: options[i].value == value,
              onTap: () => onChanged(options[i].value),
            ),
          ),
          if (i != options.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

/// A value chip: flat surface when idle, primary at 14 % with a primaryLight
/// hairline and label when active. No shadow, no glow.
class _OptionCard extends StatelessWidget {
  final String label;
  final String caption;
  final bool selected;
  final VoidCallback onTap;

  const _OptionCard({
    required this.label,
    required this.caption,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusRow),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.14)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusRow),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryLight.withValues(alpha: 0.55)
                  : AppTheme.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppTheme.primaryLight : AppTheme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected
                      ? AppTheme.primaryLight.withValues(alpha: 0.8)
                      : AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 11 / 700 spaced group label of the system.
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(), style: AppTheme.labelSmall);
  }
}

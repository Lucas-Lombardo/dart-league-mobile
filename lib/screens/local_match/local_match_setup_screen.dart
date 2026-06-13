import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/local_match_config.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import 'local_match_camera_setup_screen.dart';

/// Pre-match configuration for a local 1v1 (hot-seat) game: player names,
/// starting score, match length and the double-out rule. Nothing is persisted.
class LocalMatchSetupScreen extends StatefulWidget {
  const LocalMatchSetupScreen({super.key});

  @override
  State<LocalMatchSetupScreen> createState() => _LocalMatchSetupScreenState();
}

class _LocalMatchSetupScreenState extends State<LocalMatchSetupScreen> {
  final _player1 = TextEditingController();
  final _player2 = TextEditingController();
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

  void _start() {
    final l10n = AppLocalizations.of(context);
    HapticService.mediumImpact();
    final p1 = _player1.text.trim();
    final p2 = _player2.text.trim();
    final config = LocalMatchConfig(
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
                      const Icon(Icons.emoji_events_outlined,
                          color: AppTheme.accent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        l10n.firstToNLegs(_legsToWin),
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  _SectionLabel(l10n.rulesLabel),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
                    ),
                    child: SwitchListTile(
                      value: _doubleOut,
                      onChanged: (v) {
                        HapticService.lightImpact();
                        setState(() => _doubleOut = v);
                      },
                      activeThumbColor: AppTheme.primary,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      secondary: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.adjust,
                            color: AppTheme.primary, size: 22),
                      ),
                      title: Text(l10n.doubleOutLabel,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                      subtitle: Text(l10n.doubleOutHint,
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              decoration: BoxDecoration(
                color: AppTheme.background,
                border: Border(
                  top: BorderSide(
                      color: AppTheme.surfaceLight.withValues(alpha: 0.3)),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(l10n.startMatchButton),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1),
                  ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.surface,
            AppTheme.surfaceLight.withValues(alpha: 0.4),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          _PlayerField(
            controller: player1,
            hint: hint1,
            number: 1,
            color: AppTheme.primary,
          ),
          // VS badge bridging the two fields.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(child: _divider()),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Text(
                    'VS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Expanded(child: _divider()),
              ],
            ),
          ),
          _PlayerField(
            controller: player2,
            hint: hint2,
            number: 2,
            color: AppTheme.secondary,
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        height: 1,
        color: AppTheme.surfaceLight.withValues(alpha: 0.5),
      );
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
      style: const TextStyle(
          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
      textCapitalization: TextCapitalization.words,
      textInputAction: TextInputAction.next,
      maxLength: 20,
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: const TextStyle(color: AppTheme.textSecondary),
        isDense: true,
        prefixIcon: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ),
        ),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: AppTheme.background.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide:
              BorderSide(color: AppTheme.surfaceLight.withValues(alpha: 0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: 2),
        ),
      ),
    );
  }
}

// ── Option cards (score / length) ────────────────────────────────────────────

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
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.16)
                : AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? AppTheme.primary
                  : AppTheme.surfaceLight.withValues(alpha: 0.5),
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppTheme.primary.withValues(alpha: 0.25),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppTheme.primary : Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                caption,
                style: TextStyle(
                  color: selected
                      ? AppTheme.primary.withValues(alpha: 0.8)
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }
}

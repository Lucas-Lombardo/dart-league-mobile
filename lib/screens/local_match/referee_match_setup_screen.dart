import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/local_match_config.dart';
import '../../models/referee_match.dart';
import '../../utils/app_navigator.dart';
import '../../utils/app_theme.dart';
import '../../utils/haptic_service.dart';
import '../../widgets/design_system.dart';
import 'local_match_widgets.dart';
import 'referee_match_screen.dart';

class RefereeMatchSetupScreen extends StatefulWidget {
  const RefereeMatchSetupScreen({super.key});

  @override
  State<RefereeMatchSetupScreen> createState() =>
      _RefereeMatchSetupScreenState();
}

class _RefereeMatchSetupScreenState extends State<RefereeMatchSetupScreen> {
  final _names = [TextEditingController(), TextEditingController()];
  int _target = 2;
  int _firstPlayer = 0;
  bool _doubleOut = true;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    for (final controller in _names) {
      controller.addListener(_refresh);
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    for (final controller in _names) {
      controller.dispose();
    }
    super.dispose();
  }

  String _name(int i, AppLocalizations l10n) => _names[i].text.trim().isNotEmpty
      ? _names[i].text.trim()
      : i == 0
      ? l10n.player1DefaultName
      : l10n.player2DefaultName;

  Future<void> _start() async {
    if (_opening) return;
    final l10n = AppLocalizations.of(context);
    FocusScope.of(context).unfocus();
    setState(() => _opening = true);
    HapticService.mediumImpact();
    final config = LocalMatchConfig(
      player1Name: _name(0, l10n),
      player2Name: _name(1, l10n),
      startingScore: 501,
      bestOf: _target * 2 - 1,
      doubleOut: _doubleOut,
    );
    await AppNavigator.toScreen<void>(
      context,
      RefereeMatchScreen(
        match: RefereeMatch(config: config, firstPlayer: _firstPlayer),
      ),
    );
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.refereeMode),
            Text(l10n.refereePrepare, style: AppTheme.caption),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  DsCard(
                    radius: 14,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Text('501', style: AppTheme.displayLarge),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            l10n.refereeSetupHint,
                            style: AppTheme.caption.copyWith(height: 1.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.calculate_outlined,
                          color: AppTheme.primaryLight,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _Label(l10n.playersLabel),
                  Row(
                    children: [
                      for (var i = 0; i < 2; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            key: ValueKey('referee-name-$i'),
                            controller: _names[i],
                            maxLength: 24,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: i == 0
                                ? TextInputAction.next
                                : TextInputAction.done,
                            style: AppTheme.rowTitle,
                            decoration: InputDecoration(
                              counterText: '',
                              labelText: i == 0
                                  ? l10n.player1DefaultName
                                  : l10n.player2DefaultName,
                              prefixIcon: Icon(
                                Icons.circle,
                                size: 8,
                                color: localPlayerColor(i),
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 30,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 24),
                  _Label(l10n.refereeLegsToWin),
                  Row(
                    children: [
                      for (var n = 1; n <= 3; n++) ...[
                        if (n > 1) const SizedBox(width: 8),
                        Expanded(
                          child: _Choice(
                            key: ValueKey('referee-target-$n'),
                            selected: _target == n,
                            onTap: () => setState(() => _target = n),
                            child: Column(
                              children: [
                                Text(
                                  '$n',
                                  style: AppTheme.titleLarge.copyWith(
                                    fontSize: 22,
                                    color: _target == n
                                        ? AppTheme.primaryLight
                                        : AppTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  [
                                    l10n.refereeFormatQuick,
                                    l10n.refereeFormatClassic,
                                    l10n.refereeFormatLong,
                                  ][n - 1],
                                  style: AppTheme.caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _target == 1
                        ? l10n.refereeOneLegHint
                        : l10n.refereeFormatHint(_target, _target * 2 - 1),
                    style: AppTheme.caption,
                  ),
                  const SizedBox(height: 24),
                  DsCard(
                    radius: 14,
                    padding: EdgeInsets.zero,
                    child: SwitchListTile(
                      key: const ValueKey('referee-double-out'),
                      value: _doubleOut,
                      onChanged: (value) => setState(() => _doubleOut = value),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      title: Text(
                        l10n.doubleOutLabel,
                        style: AppTheme.rowTitle,
                      ),
                      subtitle: Text(
                        _doubleOut
                            ? l10n.doubleOutHint
                            : l10n.refereeStraightOutHint,
                        style: AppTheme.caption,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _Label(l10n.refereeFirstPlayer),
                  Row(
                    children: [
                      for (var i = 0; i < 2; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _Choice(
                            key: ValueKey('referee-first-$i'),
                            selected: _firstPlayer == i,
                            color: localPlayerColor(i),
                            onTap: () => setState(() => _firstPlayer = i),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 7,
                                  color: localPlayerColor(i),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    _name(i, l10n),
                                    style: AppTheme.caption.copyWith(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_firstPlayer == i)
                                  Icon(
                                    Icons.check,
                                    size: 15,
                                    color: localPlayerColor(i),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.refereeFirstPlayerHint,
                    style: AppTheme.caption.copyWith(height: 1.6),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Column(
                children: [
                  Text(
                    '501 · ${_doubleOut ? l10n.doubleOutLabel : l10n.refereeStraightOut} · ${l10n.firstToNLegs(_target)}',
                    style: AppTheme.caption,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      key: const ValueKey('referee-start'),
                      onPressed: _opening ? null : _start,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(dsSentence(l10n.startMatchButton)),
                          ),
                          const Icon(Icons.arrow_forward, size: 20),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.refereeStartHint,
                    style: AppTheme.caption,
                    textAlign: TextAlign.center,
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

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: AppTheme.sectionTitle),
  );
}

class _Choice extends StatelessWidget {
  final Widget child;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _Choice({
    super.key,
    required this.child,
    required this.selected,
    required this.onTap,
    this.color = AppTheme.primaryLight,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    child: Material(
      color: selected ? color.withValues(alpha: .09) : AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? color : AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: child,
        ),
      ),
    ),
  );
}

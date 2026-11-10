import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/progression.dart';
import '../../utils/app_theme.dart';
import '../../widgets/progression/metal.dart';
import '../../widgets/progression/monogram_avatar.dart';
import 'locker_unlock.dart' show LockerSheetButton, lockerSheetBottomPadding;

/// « Les lettres de ton avatar » (CasObtenir, replaces « Texte du
/// monogramme »): opened from the pencil of the equipped monogram avatar.
/// Three choices with a live preview on the medal: « Tes initiales » (the
/// server's automatic initials), « Ton double » (D1–D20, T19, T20, BULL) and
/// « Au choix » (1 to 3 letters or digits) — exactly what
/// PUT /progression/equipment accepts.
class LockerLettersResult {
  /// Null = automatic initials.
  final MonogramChoice? choice;
  const LockerLettersResult(this.choice);
}

/// The doubles offered, most played first (all accepted by the server).
const lockerDoubles = [
  'D20',
  'D16',
  'D18',
  'D12',
  'D10',
  'D8',
  'D4',
  'D2',
  'D1',
  'D3',
  'D5',
  'D6',
  'D7',
  'D9',
  'D11',
  'D13',
  'D14',
  'D15',
  'D17',
  'D19',
  'T20',
  'T19',
  'BULL',
];

const _accents = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
};

/// The server's automatic initials (backend `monogramFromUsername`): the
/// first letter of the first two words, words split on separators and
/// camelCase, trailing digits dropped. 'Kev_D20' → 'KD', 'Dodo180' → 'DO'.
/// Accents are folded with a small table (the server uses NFKD).
String lockerAutoInitials(String username) {
  final raw = username.split('').map((c) {
    final lower = c.toLowerCase();
    final folded = _accents[lower];
    if (folded == null) return c;
    return c == lower ? folded : folded.toUpperCase();
  }).join();
  final words = raw
      .split(RegExp(r'[^A-Za-z0-9]+'))
      .expand((w) => w.split(RegExp(r'(?<=[a-z])(?=[A-Z])')))
      .map((w) => w.replaceAll(RegExp(r'[0-9]+$'), ''))
      .where((w) => RegExp(r'[A-Za-z]').hasMatch(w))
      .toList();
  if (words.length >= 2) return (words[0][0] + words[1][0]).toUpperCase();
  final single = (words.isNotEmpty ? words[0] : raw).replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  final letters = single.length > 2 ? single.substring(0, 2) : single;
  return letters.isEmpty ? '?' : letters.toUpperCase();
}

class LockerLettersSheet extends StatefulWidget {
  /// The equipped monogram avatar (drawn with the chosen letters).
  final ItemDef item;

  /// The letters shown today (cosmetics.monogram).
  final String current;
  final MonogramChoice? choice;
  final String username;

  const LockerLettersSheet({super.key, required this.item, required this.current, required this.choice, required this.username});

  static Future<LockerLettersResult?> show(
    BuildContext context, {
    required ItemDef item,
    required String current,
    required MonogramChoice? choice,
    required String username,
  }) => showModalBottomSheet<LockerLettersResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.surface,
    barrierColor: const Color(0x9E020617),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
    builder: (_) => LockerLettersSheet(item: item, current: current, choice: choice, username: username),
  );

  @override
  State<LockerLettersSheet> createState() => _LockerLettersSheetState();
}

class _LockerLettersSheetState extends State<LockerLettersSheet> {
  /// 'auto' | 'double' | 'initials' (the server's kinds, plus auto = null).
  late String _kind = switch (widget.choice?.kind) {
    'double' => 'double',
    'initials' => 'initials',
    _ => 'auto',
  };
  late final TextEditingController _initials = TextEditingController(text: widget.choice?.kind == 'initials' ? widget.choice!.value : '');
  late String _double = widget.choice?.kind == 'double' && lockerDoubles.contains(widget.choice!.value) ? widget.choice!.value : 'D16';

  /// Automatic initials: the server's own text while they are in use.
  late final String _auto = widget.choice == null && widget.current.isNotEmpty
      ? widget.current
      : lockerAutoInitials(widget.username.isEmpty ? widget.current : widget.username);

  @override
  void dispose() {
    _initials.dispose();
    super.dispose();
  }

  String get _typed => _initials.text.trim().toUpperCase();
  bool get _typedValid => RegExp(r'^[A-Z0-9]{1,3}$').hasMatch(_typed);
  bool get _valid => _kind != 'initials' || _typedValid;

  String get _preview => switch (_kind) {
    'double' => _double,
    'initials' => _typedValid ? _typed : _auto,
    _ => _auto,
  };

  void _save() {
    Navigator.of(context).pop(
      LockerLettersResult(switch (_kind) {
        'double' => MonogramChoice(kind: 'double', value: _double),
        'initials' => MonogramChoice(kind: 'initials', value: _typed),
        _ => null,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 10, 20, lockerSheetBottomPadding(context)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFF475569), borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                MonogramAvatar.fromItem(widget.item, text: _preview, size: 64, content: watchProgressionContent(context)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.lockerSLettersTitle,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(l10n.lockerSLettersSub, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _LetterChoice(
                    key: const Key('letters-auto'),
                    value: _auto,
                    label: l10n.lockerSLettersAuto,
                    selected: _kind == 'auto',
                    onTap: () => setState(() => _kind = 'auto'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _LetterChoice(
                    key: const Key('letters-double'),
                    value: _double,
                    label: l10n.lockerSLettersDouble,
                    selected: _kind == 'double',
                    onTap: () => setState(() => _kind = 'double'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _LetterChoice(
                    key: const Key('letters-custom'),
                    value: _typedValid ? _typed : 'Aa',
                    label: l10n.lockerSLettersCustom,
                    selected: _kind == 'initials',
                    onTap: () => setState(() => _kind = 'initials'),
                  ),
                ),
              ],
            ),
            if (_kind == 'double') ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in lockerDoubles)
                    ChoiceChip(
                      label: Text(d),
                      selected: _double == d,
                      showCheckmark: false,
                      // Blue accent like the choice above (the theme's
                      // secondary is the opponent's rose).
                      selectedColor: const Color(0x2438BDF8),
                      side: _double == d ? const BorderSide(color: AppTheme.primaryLight, width: 1.5) : null,
                      onSelected: (_) => setState(() => _double = d),
                    ),
                ],
              ),
            ],
            if (_kind == 'initials') ...[
              const SizedBox(height: 14),
              TextField(
                controller: _initials,
                maxLength: 3,
                autofocus: _initials.text.isEmpty,
                textCapitalization: TextCapitalization.characters,
                decoration: AppTheme.inputDecoration(label: l10n.lockerMonogramHint, prefixIcon: Icons.text_fields_rounded),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 16),
            Opacity(
              opacity: _valid ? 1 : 0.4,
              child: LockerSheetButton(label: l10n.lockerSave, onTap: _valid ? _save : null),
            ),
          ],
        ),
      ),
    );
  }
}

class _LetterChoice extends StatelessWidget {
  final String value;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LetterChoice({super.key, required this.value, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? const Color(0x2438BDF8) : AppTheme.background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? AppTheme.primaryLight : Colors.transparent, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 52,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 16, height: 1.2, fontWeight: FontWeight.w800, color: AppTheme.textPrimary),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: selected ? AppTheme.playerBlueBright : AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

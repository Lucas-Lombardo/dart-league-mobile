import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../models/progression.dart';
import '../../providers/progression_provider.dart';

/// Metal palettes: [top, middle, bottom] of the item gradients. The server's
/// content (metals.json) wins; this table is the offline fallback and mirrors
/// docs/progression/svg/reference_svg.py.
class MetalPalette {
  static const Map<String, List<Color>> fallback = {
    'acier': [Color(0xFFE2E8F0), Color(0xFF7B8798), Color(0xFFCBD5E1)],
    'cuivre': [Color(0xFFE8A27A), Color(0xFF8C4A26), Color(0xFFD98C5F)],
    'laiton': [Color(0xFFE6CC7A), Color(0xFF9A7A2C), Color(0xFFDDBE63)],
    'or': [Color(0xFFFDE68A), Color(0xFFB8860B), Color(0xFFFACC15)],
    'tungstene': [Color(0xFFB4BAC4), Color(0xFF4A515D), Color(0xFF9AA2AE)],
    'platine': [Color(0xFFF1F5F9), Color(0xFFA3ACB9), Color(0xFFE5E7EB)],
    'bronze': [Color(0xFFE9B48A), Color(0xFF9A5B2E), Color(0xFFD08A4F)],
    'argent': [Color(0xFFF1F5F9), Color(0xFF8A94A6), Color(0xFFCBD5E1)],
    'damas': [Color(0xFF9CA3AF), Color(0xFF374151), Color(0xFF6B7280)],
    'titane': [Color(0xFFA5B4CB), Color(0xFF4B5A78), Color(0xFF8C9BB8)],
    'or-blanc': [Color(0xFFF8FAFC), Color(0xFFC7C2B5), Color(0xFFEDE9E0)],
    'legende': [Color(0xFFFDE68A), Color(0xFF7A5A12), Color(0xFFFACC15)],
    'obsidienne': [Color(0xFF5B6170), Color(0xFF0B0D12), Color(0xFF3B3F4A)],
    'tournoi': [Color(0xFF7DD3FC), Color(0xFF0369A1), Color(0xFF38BDF8)],
  };

  static List<Color> of(ProgressionContent? content, String? key) =>
      content?.metals[key] ?? fallback[key] ?? fallback['acier']!;

  /// Badge ring metal for a tier.
  static String forTier(String? tier) => switch (tier) {
        'gold' => 'or',
        'silver' => 'argent',
        'bronze' => 'bronze',
        _ => 'tungstene',
      };

  static Color shade(Color c, double f) => Color.fromARGB(
        (c.a * 255).round(),
        ((c.r * 255) * f).round().clamp(0, 255),
        ((c.g * 255) * f).round().clamp(0, 255),
        ((c.b * 255) * f).round().clamp(0, 255),
      );

  static LinearGradient gradient(
    List<Color> colors, {
    double factor = 1,
    Alignment begin = Alignment.topLeft,
    Alignment end = Alignment.bottomRight,
  }) =>
      LinearGradient(
        begin: begin,
        end: end,
        colors: colors.map((c) => factor == 1 ? c : shade(c, factor)).toList(),
        stops: const [0, 0.48, 1],
      );
}

/// The content catalog when a ProgressionProvider is in the tree, else null
/// (widget tests and screens built before the provider existed keep working).
ProgressionContent? watchProgressionContent(BuildContext context) {
  try {
    return context.select<ProgressionProvider, ProgressionContent?>((p) => p.content);
  } on ProviderNotFoundException {
    return null;
  }
}

ProgressionContent? readProgressionContent(BuildContext context) {
  try {
    return Provider.of<ProgressionProvider>(context, listen: false).content;
  } on ProviderNotFoundException {
    return null;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/widgets/progression/metal.dart';
import 'package:mobile/widgets/progression/progression_widgets.dart';

Map<String, dynamic> _badge(String id, {bool asset = true}) => {
      'id': id,
      'type': 'badge',
      'name': {'fr': id, 'en': id},
      'source': {'kind': 'achievement', 'label': {'fr': 's', 'en': 'a'}},
      'render': {'kind': 'badge', 'glyph': '180'},
      if (asset) 'asset': {'url': '/progression/items/$id.svg?v=1', 'format': 'svg', 'hash': 'h$id'},
    };

Widget _app(Widget child, {Locale locale = const Locale('fr')}) {
  final p = ProgressionProvider()
    ..debugSeed(
      content: ProgressionContent.fromJson({
        'version': 'v1',
        'items': [_badge('badge.machine-a-180'), _badge('badge.daily-first'), _badge('badge.plain', asset: false)],
      }),
    );
  return ChangeNotifierProvider<ProgressionProvider>.value(
    value: p,
    child: MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// The ring discs: a circle filled with a metal gradient.
List<LinearGradient> _rings(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .map((d) => d.decoration)
    .whereType<BoxDecoration>()
    .where((d) => d.shape == BoxShape.circle && d.gradient is LinearGradient)
    .map((d) => d.gradient as LinearGradient)
    .toList();

void main() {
  testWidgets('draws the tier ring under the face asset', (tester) async {
    await tester.pumpWidget(_app(
      const BadgeMedal(badge: PublicBadge(id: 'b1', badgeId: 'badge.machine-a-180', tier: 'silver'), size: 60),
    ));
    await tester.pump();
    expect(find.byType(ProgressionAssetView), findsOneWidget);
    final gold = MetalPalette.gradient(MetalPalette.of(null, 'argent'));
    expect(_rings(tester).any((g) => g.colors.first == gold.colors.first && g.colors.last == gold.colors.last), isTrue);
    // The ring is UNDER the asset (first child of the stack).
    final stack = tester.widget<Stack>(find.descendant(of: find.byType(BadgeMedal), matching: find.byType(Stack)).first);
    expect(stack.children.first, isA<DecoratedBox>());
  });

  testWidgets('a badge without tier gets the tungsten ring; a locked one is grey and dimmed', (tester) async {
    await tester.pumpWidget(_app(const Row(children: [
      BadgeMedal(badge: PublicBadge(id: 'b1', badgeId: 'badge.machine-a-180'), size: 40),
      BadgeMedal(badge: PublicBadge(id: 'b2', badgeId: 'badge.machine-a-180', tier: 'gold'), size: 40, locked: true),
    ])));
    await tester.pump();
    final tungsten = MetalPalette.of(null, 'tungstene');
    expect(_rings(tester).any((g) => g.colors.first == tungsten.first), isTrue);
    final dimmed = tester.widgetList<Opacity>(find.byType(Opacity)).map((o) => o.opacity);
    expect(dimmed, contains(0.4));
    // Locked never shows the earned tier's metal.
    final gold = MetalPalette.of(null, 'or');
    expect(_rings(tester).any((g) => g.colors.first == gold.first), isFalse);
  });

  testWidgets('writes the date of a dated badge in the band left free (y 76–92)', (tester) async {
    await tester.pumpWidget(_app(
      const BadgeMedal(
        badge: PublicBadge(id: 'd1', badgeId: 'badge.daily-first', tier: 'gold', date: '2026-11-08'),
        size: 120,
      ),
    ));
    await tester.pump();
    expect(find.text('8 NOV'), findsOneWidget);
    final medal = tester.getTopLeft(find.byType(BadgeMedal));
    final band = tester.getRect(find.byKey(const ValueKey('badge-date')).first);
    expect(band.top - medal.dy, greaterThanOrEqualTo(76));
    expect(band.bottom - medal.dy, lessThanOrEqualTo(92.5));
    expect(BadgeMedal.dateLabel('2026-02-01', const Locale('en')), '1 FEB');
    expect(BadgeMedal.dateLabel(null, const Locale('fr')), isNull);
  });

  testWidgets('without an asset, the drawn medal stays (ring + glyph), no date', (tester) async {
    await tester.pumpWidget(_app(
      const BadgeMedal(badge: PublicBadge(id: 'p', badgeId: 'badge.plain', tier: 'bronze'), size: 48),
    ));
    await tester.pump();
    expect(find.byType(ProgressionAssetView), findsNothing);
    expect(find.text('180'), findsOneWidget);
    expect(find.byKey(const ValueKey('badge-date')), findsNothing);
  });
}

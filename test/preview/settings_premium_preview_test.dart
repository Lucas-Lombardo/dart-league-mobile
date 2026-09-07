// Renders the Settings and Premium screens (system D) to PNG with fake
// providers so they can be reviewed without a device. Not a test of
// behaviour — skipped unless run explicitly:
//
//   flutter test test/preview/settings_premium_preview_test.dart \
//     --dart-define=PREVIEW=true \
//     --dart-define=PREVIEW_OUT=/abs/dir
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/locale_provider.dart';
import 'package:mobile/providers/referral_provider.dart';
import 'package:mobile/providers/subscription_provider.dart';
import 'package:mobile/screens/settings/settings_screen.dart';
import 'package:mobile/screens/settings/subscription_screen.dart';
import 'package:mobile/services/referral_service.dart';
import 'package:mobile/utils/app_theme.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outDir = String.fromEnvironment('PREVIEW_OUT');

Future<void> _loadFonts() async {
  final fonts = Directory('${Directory.current.path}/assets/fonts');
  if (fonts.existsSync()) {
    final loader = FontLoader(AppTheme.fontFamily);
    final files = fonts
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ttf'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final bytes = await f.readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.path;
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons');
    final bytes = await icons.readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }
}

/// flutter_secure_storage has no test implementation; answer every call with
/// null so LocaleProvider / ApiService can start without a plugin.
void _mockSecureStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => null,
  );
}

class _FakeAuth extends AuthProvider {
  @override
  User? get currentUser => User(
        id: 'u-me',
        username: 'Vati99',
        email: 'vati99@gmail.com',
        elo: 1601,
        rank: 'platinum',
        isPremium: true,
      );
}

class _FakeSubscription extends SubscriptionProvider {
  final bool premium;
  _FakeSubscription({required this.premium});

  @override
  bool get isPremiumActive => premium;
  @override
  bool get hasPaidSubscription => premium;
  @override
  DateTime? get premiumExpiresAt =>
      premium ? DateTime(2026, 9, 12) : null;
  @override
  bool get isLoading => false;
  @override
  int? get matchesRemainingToday => premium ? null : 1;
  @override
  Future<void> refresh() async {}
}

class _FakeReferral extends ReferralProvider {
  @override
  ReferralOverview? get overview => ReferralOverview(
        code: 'VATI-2K4X',
        canCreateCode: true,
        isEmailVerified: true,
        rewardMonthlyCents: 500,
        rewardYearlyCents: 1000,
        refereeTrialDays: 7,
        earnedCents: 0,
        pendingCents: 0,
        referees: const [],
        redeem: const ReferralEligibility(eligible: true),
        referredByUsername: null,
      );
  @override
  bool get canRedeem => true;
  @override
  bool get isLoading => false;
  @override
  Future<void> loadOverview() async {}
}

class _FakeLocale extends LocaleProvider {
  @override
  Locale get locale => const Locale('fr');
}

Widget _app(Widget home, GlobalKey key, {required bool premium}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => _FakeAuth()),
      ChangeNotifierProvider<SubscriptionProvider>(
          create: (_) => _FakeSubscription(premium: premium)),
      ChangeNotifierProvider<ReferralProvider>(create: (_) => _FakeReferral()),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => _FakeLocale()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,
      locale: const Locale('fr'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepaintBoundary(key: key, child: home),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
  await tester.pump();
}

Future<void> _snap(WidgetTester tester, GlobalKey key, String name) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('wrote ${file.path}');
  });
}

void main() {
  testWidgets('settings preview', (tester) async {
    _mockSecureStorage();
    await tester.runAsync(_loadFonts);
    final key = GlobalKey();
    // Taller than a phone so every group is visible in one capture.
    await tester.binding.setSurfaceSize(const Size(393, 1500));
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(_app(const SettingsScreen(), key, premium: true));
    await _settle(tester);
    await _snap(tester, key, 'settings');
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);

  testWidgets('premium preview', (tester) async {
    _mockSecureStorage();
    await tester.runAsync(_loadFonts);
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(393, 852));
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(
        _app(const SubscriptionScreen(), key, premium: false));
    await _settle(tester);
    await _snap(tester, key, 'premium');
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);
}

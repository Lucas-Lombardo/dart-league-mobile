// Renders the login screen (system D: flat background, shield + wordmark,
// labelled fields, primary button, sign-up footer) to PNG so it can be
// reviewed without a device. Not a test of behaviour — skipped unless run
// explicitly:
//
//   flutter test test/preview/login_preview_test.dart \
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
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/screens/auth/forgot_password_screen.dart';
import 'package:mobile/screens/auth/login_screen.dart';
import 'package:mobile/screens/auth/register_screen.dart';
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

void main() {
  testWidgets('login preview', (tester) async {
    await tester.runAsync(_loadFonts);
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(393, 852));
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
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
          home: RepaintBoundary(key: key, child: const LoginScreen()),
        ),
      ),
    );
    // Type in the email so the filled state renders, then focus the password
    // field so the primary focus ring shows (as on the mockup).
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).first, 'vati99@gmail.com');
    await tester.enterText(find.byType(TextFormField).last, 'secretpass');
    await tester.runAsync(() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pump();

    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir/login.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('wrote ${file.path}');
    });
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);

  testWidgets('register preview', (tester) async {
    await tester.runAsync(_loadFonts);
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(393, 852));
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
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
          home: RepaintBoundary(key: key, child: const RegisterScreen()),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pump();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir/register.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('wrote ${file.path}');
    });
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);

  testWidgets('forgot password preview', (tester) async {
    await tester.runAsync(_loadFonts);
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(393, 852));
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>(
        create: (_) => AuthProvider(),
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
          home: RepaintBoundary(key: key, child: const ForgotPasswordScreen()),
        ),
      ),
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pump();
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outDir/forgot.png');
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('wrote ${file.path}');
    });
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);
}

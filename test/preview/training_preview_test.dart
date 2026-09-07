// Renders the training hub, a category list and the end-of-training screen
// (system D) to PNG so they can be reviewed without a device. Not a test of
// behaviour — skipped unless run explicitly:
//
//   flutter test test/preview/training_preview_test.dart \
//     --dart-define=PREVIEW=true \
//     --dart-define=PREVIEW_OUT=/abs/dir
//
// Manrope is loaded from assets/fonts (the bundled family), Material Icons
// from the Flutter SDK cache.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/training.dart';
import 'package:mobile/screens/training/training_end_screen.dart';
import 'package:mobile/screens/training/training_select_screen.dart';
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

Future<void> _shot(WidgetTester tester, Widget screen, String name) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(const Size(393, 852));
  tester.view.devicePixelRatio = 3;
  await tester.pumpWidget(
    MaterialApp(
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
      home: RepaintBoundary(key: key, child: screen),
    ),
  );
  // Localizations resolve asynchronously.
  await tester.runAsync(() async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
  await tester.pump();

  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('wrote ${file.path}');
  });
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('training previews', (tester) async {
    await tester.runAsync(_loadFonts);

    await _shot(
      tester,
      TrainingEndScreen(
        type: TrainingType.importantDoubles,
        score: 38,
        maxScore: 60,
        dartsThrown: 60,
        completed: true,
        scoreLabel: 'Réussite',
        subtitle: 'D16 : 22 · D20 : 16',
        onPlayAgain: () {},
      ),
      'training_end',
    );

    await _shot(
      tester,
      TrainingEndScreen(
        type: TrainingType.bobs27,
        score: 91,
        dartsThrown: 33,
        completed: false,
        scoreLabel: 'Score',
        submitError: 'Connexion perdue',
        onPlayAgain: () {},
        onRetrySubmit: () {},
      ),
      'training_end_error',
    );

    await _shot(tester, const TrainingSelectScreen(), 'training_hub');

    await _shot(
      tester,
      const TrainingCategoryScreen(category: TrainingCategory.doubles),
      'training_category',
    );
  }, skip: !_enabled);
}

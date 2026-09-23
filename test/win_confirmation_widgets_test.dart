import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/win_confirmation.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/widgets/win_confirmation_widgets.dart';

class _GameChanges extends ChangeNotifier {
  void changed() => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader(AppTheme.fontFamily)
      ..addFont(rootBundle.load('assets/fonts/Manrope-Regular.ttf'));
    await loader.load();
  });
  for (final size in [
    const Size(393, 852),
    const Size(320, 568),
    const Size(852, 393),
  ]) {
    testWidgets(
      'header mic, confirmation and correction remain accessible at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        final game = _GameChanges();
        var pending = true, muted = true;
        var confirms = 0, edits = 0;
        late BuildContext page;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.themeData,
            locale: const Locale('fr'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Builder(
              builder: (context) {
                page = context;
                return const Scaffold(body: Text('Match'));
              },
            ),
          ),
        );
        await tester.pump();
        void open() {
          showDialog<void>(
            context: page,
            barrierDismissible: false,
            builder: (_) => WinConfirmationDialog(
              game: game,
              pending: () => pending,
              confirmation: () => WinConfirmation(
                playerId: 'winner',
                closesCall: true,
                deadline: DateTime.now().add(const Duration(seconds: 30)),
              ),
              muted: () => muted,
              toggleMic: () async {
                muted = !muted;
              },
              title: 'Checkout !',
              content: const Text(
                'Vous avez touché D20 pour finir ! Est-ce correct ?',
              ),
              replay: const SizedBox(
                height: 32,
                child: Text('Sauvegarder la volée'),
              ),
              confirm: () => confirms++,
              edit: () => edits++,
            ),
          );
        }

        open();
        await tester.pumpAndSettle();
        expect(find.byType(WinConfirmationDialog), findsOneWidget);
        expect(tester.getSize(find.byType(Dialog)).width, greaterThan(0));
        expect(find.textContaining('Coupure de l’appel dans'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.mic_off_rounded));
        await tester.pump();
        expect(muted, isFalse);
        expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
        expect(find.byType(WinConfirmationDialog), findsOneWidget);
        expect(confirms, 0);
        await tester.tap(find.byType(OutlinedButton));
        await tester.pumpAndSettle();
        expect(edits, 1);
        expect(find.byType(WinConfirmationDialog), findsNothing);
        open();
        await tester.pumpAndSettle();
        await tester.tap(find.byType(ElevatedButton));
        await tester.pumpAndSettle();
        expect(confirms, 1);
        open();
        await tester.pumpAndSettle();
        pending = false;
        game.changed();
        await tester.pumpAndSettle();
        expect(find.byType(WinConfirmationDialog), findsNothing);
        expect(
          confirms,
          1,
        ); // Automatic server result never sends a second confirm.
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        game.dispose();
      },
    );
  }
}

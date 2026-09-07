// Renders the chat inbox, a thread and the splash (system D) to PNG so they
// can be reviewed without a device. Not a test of behaviour — skipped unless
// run explicitly:
//
//   flutter test test/preview/chat_splash_preview_test.dart \
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
import 'package:mobile/models/chat_message.dart';
import 'package:mobile/screens/chat/chat_thread_screen.dart';
import 'package:mobile/screens/chat/received_messages_screen.dart';
import 'package:mobile/screens/splash_screen.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/widgets/design_system.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outDir = String.fromEnvironment('PREVIEW_OUT');

const me = 'u-me';

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

ChatConversation _conv({
  required String id,
  required String name,
  required String last,
  required DateTime at,
  int unread = 0,
  bool support = false,
}) {
  return ChatConversation(
    conversationId: id,
    isSupport: support,
    username: name,
    lastContent: last,
    lastSenderId: id,
    lastAt: at,
    unreadCount: unread,
  );
}

class _InboxPreview extends StatelessWidget {
  const _InboxPreview();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final unread = [
      _conv(id: 'u-dodo', name: 'DODO180', last: 'GG pour le match, on remet ça ce soir ?', at: now.subtract(const Duration(minutes: 12)), unread: 2),
      _conv(id: kSupportConversationId, name: 'Équipe', last: 'Merci pour ton retour, le correctif arrive dans la 1.9.', at: now.subtract(const Duration(hours: 3)), unread: 1, support: true),
    ];
    final earlier = [
      _conv(id: 'u-tom', name: 'Tomtom_180', last: 'Trop fort le 121 checkout', at: now.subtract(const Duration(days: 1, hours: 2))),
      _conv(id: 'u-kev', name: 'Kev_Darts', last: 'Dispo samedi pour le tournoi ?', at: now.subtract(const Duration(days: 4))),
      _conv(id: 'u-marion', name: 'Marion_B', last: 'Ok', at: now.subtract(const Duration(days: 9))),
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: DsScreenHeader(title: l10n.receivedMessagesTitle, showBack: true),
            ),
            Expanded(
              child: ConversationList(
                unread: unread,
                earlier: earlier,
                isOnline: (c) => c.conversationId == 'u-dodo',
                isPremium: (c) => c.conversationId == 'u-dodo',
                onOpen: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadPreview extends StatelessWidget {
  const _ThreadPreview();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    ChatMessage msg(String id, String from, String text, Duration ago) => ChatMessage(
          id: id,
          senderId: from,
          content: text,
          createdAt: now.subtract(ago),
        );
    final messages = [
      msg('1', 'u-dodo', 'Salut ! Dispo pour un ranked ce soir ?', const Duration(days: 1, hours: 5)),
      msg('2', me, 'Oui vers 21h, je finis un entraînement avant.', const Duration(days: 1, hours: 4, minutes: 50)),
      msg('3', 'u-dodo', 'Parfait. Prépare-toi, j\'ai bossé mes doubles toute la semaine.', const Duration(hours: 2)),
      msg('4', me, 'On verra ça sur la cible', const Duration(hours: 1, minutes: 58)),
      msg('5', 'u-dodo', 'GG pour le match, on remet ça ce soir ?', const Duration(minutes: 12)),
    ];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () {},
        ),
        title: const ChatThreadTitle(isSupport: false, username: 'DODO180', online: true),
        actions: [
          IconButton(icon: const Icon(Icons.sports_esports_outlined, size: 22), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_horiz_rounded, size: 22), onPressed: () {}),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ChatMessagesView(messages: messages, myId: me, emptyText: ''),
          ),
          ChatComposer(
            controller: TextEditingController(text: 'À 21h alors'),
            sending: false,
            onSend: () {},
          ),
        ],
      ),
    );
  }
}

Widget _app(GlobalKey key, Widget home) {
  return MaterialApp(
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
  );
}

Future<void> _shoot(WidgetTester tester, GlobalKey key, Widget home, String name) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  tester.view.devicePixelRatio = 3;
  await tester.pumpWidget(_app(key, home));
  // Localizations and asset images (shield) resolve asynchronously.
  await tester.runAsync(() async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
  await tester.pump(const Duration(seconds: 1));

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
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
  testWidgets('chat inbox preview', (tester) async {
    await tester.runAsync(_loadFonts);
    await _shoot(tester, GlobalKey(), const _InboxPreview(), 'chat_inbox');
  }, skip: !_enabled);

  testWidgets('chat thread preview', (tester) async {
    await tester.runAsync(_loadFonts);
    await _shoot(tester, GlobalKey(), const _ThreadPreview(), 'chat_thread');
  }, skip: !_enabled);

  testWidgets('splash preview', (tester) async {
    await tester.runAsync(_loadFonts);
    await _shoot(
      tester,
      GlobalKey(),
      const Scaffold(backgroundColor: AppTheme.background, body: SplashBody()),
      'splash',
    );
  }, skip: !_enabled);
}

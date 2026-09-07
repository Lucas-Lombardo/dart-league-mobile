// Renders the Amis tab (system D: header + segments, pinned team row, online /
// offline groups, friend rows with message + Défier) to PNG so the screen can
// be reviewed without a device. Providers are faked by subclassing (no
// network). Not a test of behaviour — skipped unless run explicitly:
//
//   flutter test test/preview/friends_preview_test.dart \
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
import 'package:mobile/models/chat_message.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/providers/chat_provider.dart';
import 'package:mobile/providers/friends_provider.dart';
import 'package:mobile/screens/home/friends_screen.dart';
import 'package:mobile/services/friends_service.dart';
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

User _user(String id, String name, String rank, int elo, int w, int l, {bool premium = false}) {
  return User(
    id: id,
    username: name,
    email: '$id@x.io',
    elo: elo,
    rank: rank,
    wins: w,
    losses: l,
    isPremium: premium,
  );
}

final _friends = [
  _user('u1', 'DODO180', 'gold', 1240, 12, 8, premium: true),
  _user('u2', 'Tomtom_180', 'platinum', 1588, 31, 22, premium: true),
  _user('u3', 'Kev_Darts', 'silver', 1012, 7, 9),
  _user('u4', 'Marion_B', 'bronze', 890, 4, 11),
  _user('u5', 'Alex_501', 'diamond', 2040, 58, 20),
];

class _FakeFriends extends FriendsProvider {
  @override
  List<User> get friends => _friends;
  @override
  List<FriendRequest> get pendingRequests => [
        FriendRequest(id: 'r1', user: _user('u6', 'Nico_Bull', 'gold', 1180, 9, 4), createdAt: DateTime.now()),
      ];
  @override
  List<FriendRequest> get sentRequests => [
        FriendRequest(id: 'r2', user: _user('u7', 'Sarah_T20', 'silver', 990, 3, 6, premium: true), createdAt: DateTime.now()),
      ];
  @override
  int get pendingRequestsCount => 2;
  @override
  bool get isLoading => false;
  @override
  String? get error => null;
  @override
  bool isOnline(String userId) => userId == 'u1';
  @override
  Future<void> loadAll() async {}
  @override
  Future<void> loadFriends() async {}
  @override
  Future<void> refreshOnlineFriends() async {}
}

class _FakeChat extends ChatProvider {
  @override
  int get unreadSupport => 1;
  @override
  int unreadFrom(String counterpartId) =>
      counterpartId == kSupportConversationId ? 1 : (counterpartId == 'u2' ? 3 : 0);
}

Future<void> _shoot(WidgetTester tester, GlobalKey key, String name) async {
  // Localizations and asset images (badges, shield) resolve asynchronously.
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
    final file = File('$_outDir/$name.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint('wrote ${file.path}');
  });
}

void main() {
  testWidgets('friends preview', (tester) async {
    await tester.runAsync(_loadFonts);
    final key = GlobalKey();
    await tester.binding.setSurfaceSize(const Size(393, 852));
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<FriendsProvider>(create: (_) => _FakeFriends()),
          ChangeNotifierProvider<ChatProvider>(create: (_) => _FakeChat()),
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
          home: RepaintBoundary(
            key: key,
            child: const Scaffold(body: SafeArea(bottom: false, child: FriendsScreen())),
          ),
        ),
      ),
    );
    await _shoot(tester, key, 'friends');

    // Requests tab.
    await tester.tap(find.textContaining('Demandes'));
    await tester.pumpAndSettle();
    await _shoot(tester, key, 'friends_requests');

    // Search view (typed query is not sent: results are seeded manually
    // through the empty-state path only, so we only check the header + field).
    await tester.tap(find.byIcon(Icons.search_rounded).first);
    await tester.pumpAndSettle();
    await _shoot(tester, key, 'friends_search');

    expect(tester.takeException(), isNull);
  }, skip: !_enabled);
}

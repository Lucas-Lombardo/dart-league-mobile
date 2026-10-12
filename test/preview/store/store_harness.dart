// Shared plumbing for the store listing screenshots (App Store + Play
// Store): device profiles at the exact pixel sizes the stores accept, a
// simulated status bar / home indicator so the renders read like device
// captures, and a PNG writer without alpha channel (App Store Connect
// rejects transparency). Scenes come from the sibling preview tests.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/utils/app_theme.dart';

enum StorePlatform { ios, android }

class StoreProfile {
  final StorePlatform platform;

  /// Folder name under the platform, e.g. `iphone_6_9`.
  final String name;
  final Size logical;
  final double dpr;
  final double topInset;
  final double bottomInset;
  final bool tablet;

  const StoreProfile({
    required this.platform,
    required this.name,
    required this.logical,
    required this.dpr,
    required this.topInset,
    required this.bottomInset,
    this.tablet = false,
  });

  bool get ios => platform == StorePlatform.ios;
}

/// One profile per store slot that matters. Apple scales the 6.9" set down
/// to the smaller iPhones itself; the iPad 13" slot is mandatory because the
/// app targets iPad. Play wants 9:16 at ≥ 1080 px to be eligible for
/// featuring, tablets are optional but shown on tablet listings.
const storeProfiles = [
  // 1320 × 2868 — iPhone 16/17 Pro Max.
  StoreProfile(platform: StorePlatform.ios, name: 'iphone_6_9', logical: Size(440, 956), dpr: 3, topInset: 59, bottomInset: 34),
  // 2064 × 2752 — iPad Pro 13".
  StoreProfile(platform: StorePlatform.ios, name: 'ipad_13', logical: Size(1032, 1376), dpr: 2, topInset: 24, bottomInset: 20, tablet: true),
  // 1080 × 1920 — 9:16 phone.
  StoreProfile(platform: StorePlatform.android, name: 'phone', logical: Size(432, 768), dpr: 2.5, topInset: 24, bottomInset: 16),
  // 1600 × 2560 — 10" tablet.
  StoreProfile(platform: StorePlatform.android, name: 'tablet_10', logical: Size(800, 1280), dpr: 2, topInset: 24, bottomInset: 16, tablet: true),
  // 1200 × 1920 — 7" tablet.
  StoreProfile(platform: StorePlatform.android, name: 'tablet_7', logical: Size(600, 960), dpr: 2, topInset: 24, bottomInset: 16, tablet: true),
];

const storeLocales = [Locale('fr'), Locale('en')];

/// Manrope from assets/fonts (the bundled family) and Material Icons from the
/// Flutter SDK cache, so the renders use the real glyphs rather than Ahem.
Future<void> loadPreviewFonts() async {
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

/// Wraps a scene in the device's safe-area insets and paints the status bar
/// and home indicator over it, the way a device capture shows them.
class StoreFrame extends StatelessWidget {
  final StoreProfile profile;
  final Widget child;
  const StoreFrame({super.key, required this.profile, required this.child});

  @override
  Widget build(BuildContext context) {
    final insets = EdgeInsets.only(top: profile.topInset, bottom: profile.bottomInset);
    final mq = MediaQuery.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        MediaQuery(
          data: mq.copyWith(padding: insets, viewPadding: insets),
          child: child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: profile.topInset,
          // Transparent Material so the time is a plain text, not the
          // yellow-underlined "no Material ancestor" rendering.
          child: Material(type: MaterialType.transparency, child: _StatusBar(profile)),
        ),
        if (profile.bottomInset > 0)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: profile.ios ? 134 : 108,
                height: profile.ios ? 5 : 4,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusBar extends StatelessWidget {
  final StoreProfile profile;
  const _StatusBar(this.profile);

  @override
  Widget build(BuildContext context) {
    final phone = profile.ios && !profile.tablet;
    final fontSize = phone ? 17.0 : (profile.ios ? 12.0 : 14.0);
    final iconSize = phone ? 17.0 : (profile.ios ? 13.0 : 15.0);
    final sidePad = phone ? 46.0 : (profile.ios ? 20.0 : 22.0);
    // iPhone: content centred in the 54 px bar above the 59 px inset.
    final bottomPad = phone ? 5.0 : 0.0;
    const white = Colors.white;
    return Padding(
      padding: EdgeInsets.fromLTRB(sidePad, 0, sidePad - 8, bottomPad),
      child: Row(
        children: [
          Text(
            '9:41',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: white,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: phone ? -0.3 : 0,
              height: 1,
            ),
          ),
          const Spacer(),
          Icon(Icons.signal_cellular_alt_rounded, size: iconSize, color: white),
          const SizedBox(width: 5),
          Icon(Icons.wifi_rounded, size: iconSize, color: white),
          const SizedBox(width: 6),
          _Battery(height: iconSize * 0.72),
        ],
      ),
    );
  }
}

class _Battery extends StatelessWidget {
  final double height;
  const _Battery({required this.height});

  @override
  Widget build(BuildContext context) {
    final width = height * 2.1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: width,
          height: height,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 1),
            borderRadius: BorderRadius.circular(height * 0.3),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(height * 0.15),
            ),
          ),
        ),
        Container(
          width: 1.5,
          height: height * 0.36,
          margin: const EdgeInsets.only(left: 1),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }
}

/// Renders [scene] inside [profile] for [locale] and writes
/// `<outDir>/<platform>/<profile>/<locale>/<name>.png` as 24-bit PNG.
/// Returns the written file.
Future<File> captureStoreShot(
  WidgetTester tester, {
  required String outDir,
  required StoreProfile profile,
  required Locale locale,
  required String name,
  required WidgetBuilder scene,
  Duration settle = Duration.zero,
}) async {
  final key = GlobalKey();
  // The view itself must take the device's size: MaterialApp's MediaQuery
  // reads it from the view, and the game screens pick their layout from it
  // (the default 800×600 reads as landscape).
  tester.view.devicePixelRatio = profile.dpr;
  tester.view.physicalSize = profile.logical * profile.dpr;
  await tester.binding.setSurfaceSize(profile.logical);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: RepaintBoundary(
        key: key,
        child: StoreFrame(profile: profile, child: Builder(builder: scene)),
      ),
    ),
  );
  // Localizations and images (badges, shields, the board photo) resolve
  // asynchronously.
  await tester.runAsync(() async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
  // Two pumps: the first fires delayed starts (count-ups, impact boards),
  // the second runs those animations to their end.
  if (settle > Duration.zero) {
    await tester.pump(settle);
    await tester.pump(settle);
  }
  await tester.pump();

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final file = File('$outDir/${profile.platform.name}/${profile.name}/${locale.languageCode}/$name.png');
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: profile.dpr);
    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgb = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: raw!.buffer,
      numChannels: 4,
    ).convert(numChannels: 3);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(img.encodePng(rgb));
    debugPrint('STORE wrote ${file.path} (${image.width}x${image.height})');
  });
  expect(tester.takeException(), isNull, reason: '$name ${profile.name} ${locale.languageCode}');

  // Tear the scene down and let periodic timers (tournament countdown) fire
  // once so none is pending when the test ends.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  await tester.binding.setSurfaceSize(null);
  return file;
}

/// `<outDir>/index.html`: every PNG under [outDir], one row per
/// platform/profile/locale, to review the set in a browser.
Future<void> writeStoreIndex(String outDir) async {
  final root = Directory(outDir);
  if (!root.existsSync()) return;
  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.png'))
      .map((f) => f.path.substring(outDir.length + 1))
      .toList()
    ..sort();
  final rows = <String, List<String>>{};
  for (final f in files) {
    final slash = f.lastIndexOf('/');
    // PNGs at the root (other previews sharing the folder) go in one row.
    rows.putIfAbsent(slash < 0 ? '.' : f.substring(0, slash), () => []).add(f);
  }
  final b = StringBuffer()
    ..writeln('<!doctype html><meta charset="utf-8"><title>Store screenshots</title>')
    ..writeln('<style>body{font:14px system-ui;background:#111;color:#ddd;margin:20px}'
        'h2{margin:28px 0 8px;font-weight:600}.row{display:flex;gap:12px;overflow-x:auto;padding-bottom:8px}'
        'figure{margin:0;flex:none}img{height:480px;display:block;border:1px solid #333}'
        'figcaption{font-size:12px;color:#888;margin-top:4px}</style>');
  for (final entry in rows.entries) {
    b.writeln('<h2>${entry.key}</h2><div class="row">');
    for (final f in entry.value) {
      final name = f.substring(f.lastIndexOf('/') + 1);
      b.writeln('<figure><img src="$f" loading="lazy"><figcaption>$name</figcaption></figure>');
    }
    b.writeln('</div>');
  }
  await File('$outDir/index.html').writeAsString(b.toString());
}

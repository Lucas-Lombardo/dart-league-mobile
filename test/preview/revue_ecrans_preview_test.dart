// Renders every new screen of the progression feature to one numbered PNG
// each, so Lucas can review them all on a single page
// (docs/progression/captures/revue/NN_name.png + manifest.json). The list and
// its numbers are fixed (the review brief, CONTRACT §11.6 and §14.x).
//
// Each screen is the real widget, on a 390 × 844 iPhone (47 pt status bar,
// 34 pt home bar) at ×3, with the real Manrope fonts, the real content
// (backend/src/progression/content) and item assets
// (backend/public/progression/items). A screen that scrolls is rendered at its
// whole height (1170 px wide, taller); the others are 1170 × 2532.
//
// No network: ApiService goes through an in-memory server (http.runWithClient)
// that answers the demo player's data — Dodo180, level 23 (51 %), Gold 1 409,
// card S1 liège / laiton / monogram T20, premium, Copper league 6th. The
// stores' debug seams (debugSeed, debugLoader, load:) are used where they
// exist. The admin tabs (36–39) come from a headless Chrome script kept out of
// the repository; already up-to-date PNGs are copied (see _copies).
//
// flutter_test draws a text without a font family, and a glyph Manrope lacks
// (« ᵉ »), with boxes: just before each picture they are redrawn with the
// Mac's system fonts, as a phone falls back on its own (_systemFontFallback).
//
// Not a test of behaviour — skipped unless run explicitly:
//
//   flutter test test/preview/revue_ecrans_preview_test.dart \
//     --dart-define=PREVIEW=true
//
// (--dart-define=PREVIEW_OUT=/abs/dir to write elsewhere.)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/match.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/models/user.dart';
import 'package:mobile/providers/auth_provider.dart';
import 'package:mobile/providers/friends_provider.dart';
import 'package:mobile/providers/game_provider.dart' show ScoreMultiplier;
import 'package:mobile/providers/locale_provider.dart';
import 'package:mobile/providers/progression_provider.dart';
import 'package:mobile/providers/referral_provider.dart';
import 'package:mobile/providers/subscription_provider.dart';
import 'package:mobile/screens/achievements/achievement_detail_screen.dart';
import 'package:mobile/screens/achievements/achievement_models.dart';
import 'package:mobile/screens/achievements/achievement_unlock_sheet.dart';
import 'package:mobile/screens/achievements/achievements_screen.dart';
import 'package:mobile/screens/challenge/challenge_api.dart';
import 'package:mobile/screens/challenge/challenge_entry.dart';
import 'package:mobile/screens/challenge/challenge_leaderboard_screen.dart';
import 'package:mobile/screens/challenge/challenge_models.dart';
import 'package:mobile/screens/challenge/challenge_podium_screen.dart';
import 'package:mobile/screens/challenge/challenge_result_screen.dart';
import 'package:mobile/screens/challenge/challenge_session_screen.dart';
import 'package:mobile/screens/challenge/challenge_story.dart';
import 'package:mobile/screens/challenge/logic/challenge_strategy.dart';
import 'package:mobile/screens/game/match_end_view.dart';
import 'package:mobile/screens/ghost/ghost_digest_screen.dart';
import 'package:mobile/screens/ghost/ghost_match_screen.dart';
import 'package:mobile/screens/ghost/ghost_models.dart';
import 'package:mobile/screens/ghost/ghost_play_row.dart';
import 'package:mobile/screens/home/competitive_card.dart';
import 'package:mobile/screens/home/home_other_modes.dart';
import 'package:mobile/screens/home/home_quest_strip.dart';
import 'package:mobile/screens/league/league_models.dart';
import 'package:mobile/screens/league/league_result_screen.dart';
import 'package:mobile/screens/league/league_screen.dart';
import 'package:mobile/screens/league/league_store.dart';
import 'package:mobile/screens/league/league_widgets.dart';
import 'package:mobile/screens/onboarding/onboarding_bilan_screen.dart';
import 'package:mobile/screens/onboarding/onboarding_home_card.dart';
import 'package:mobile/screens/onboarding/onboarding_journey_screen.dart';
import 'package:mobile/screens/onboarding/onboarding_models.dart';
import 'package:mobile/screens/onboarding/onboarding_provider.dart';
import 'package:mobile/screens/profile/player_stats_screen.dart';
import 'package:mobile/screens/progression/level_up_screen.dart';
import 'package:mobile/screens/progression/levels_path_screen.dart';
import 'package:mobile/screens/progression/locker_screen.dart';
import 'package:mobile/screens/progression/progression_format.dart';
import 'package:mobile/screens/progression/progression_screen.dart';
import 'package:mobile/screens/progression/xp_summary_panel.dart';
import 'package:mobile/screens/settings/settings_screen.dart';
import 'package:mobile/screens/training/logic/training_strategy.dart';
import 'package:mobile/screens/training/training_game_view.dart';
import 'package:mobile/services/auto_scoring_service.dart';
import 'package:mobile/services/dart_scoring_service.dart';
import 'package:mobile/services/progression_service.dart';
import 'package:mobile/services/referral_service.dart';
import 'package:mobile/utils/app_theme.dart';
import 'package:mobile/utils/rank_translation.dart';
import 'package:mobile/utils/rank_utils.dart';
import 'package:mobile/widgets/design_system.dart';
import 'package:mobile/widgets/home_tiles.dart';
import 'package:mobile/widgets/progression/player_showcase_card.dart';
import 'package:mobile/widgets/recent_matches_widget.dart';

import 'impacts_fixture.dart';

const _enabled = bool.fromEnvironment('PREVIEW');
const _outArg = String.fromEnvironment('PREVIEW_OUT');

final _root = Directory.current.parent.path;
final _backend = '$_root/backend';
final _captures = '$_root/docs/progression/captures';
final _outDir = _outArg.isNotEmpty ? _outArg : '$_captures/revue';

// ─── The review list (fixed numbers) ─────────────────────────────────────────

/// Already up-to-date PNGs, copied as they are (relative to captures/).
const _copies = {
  12: 'defi_simple/defi_avant.png',
  13: 'defi_simple/defi_apres.png',
  14: 'defi_simple/defi_regle.png',
  26: 'fantome_secours/carte_b_premium.png',
  27: 'fantome_secours/carte_b_gratuit.png',
  28: 'match_trouve_duel/match_trouve_duel.png',
  29: 'match_trouve_duel/match_trouve_duel_fantome.png',
};

/// n → (title, file, note).
const _list = <int, (String, String, String)>{
  1: ('Accueil (ce qu’on voit à l’ouverture)', '01_accueil.png', '390 × 844 avec les marges d’un iPhone, avant le défi du jour.'),
  2: ('Accueil (page entière)', '02_accueil_page_entiere.png', 'Toute la hauteur de la page (elle défile).'),
  3: ('Profil (carte S1 + stats)', '03_profil.png', 'PlayerStatsScreen sur son propre profil, toute la hauteur.'),
  4: ('Niveau gagné', '04_niveau_gagne.png', 'LevelUpScreen du niveau 23 (flight Cuivre), qui ne défile pas.'),
  5: ('Parcours des niveaux', '05_chemin_des_niveaux.png', 'LevelsPathScreen par paliers de 10 (piste C), toute la hauteur : 1 – 10 et 11 – 20 repliés, 21 – 30 ouvert, 31 – 50 et le prestige à venir.'),
  6: ('Progression (quêtes en onglets)', '06_progression.png', 'ProgressionScreen en onglets (piste A), onglet Jour : les quêtes à faire, la terminée repliée.'),
  7: ('XP de fin de match', '07_xp_fin_de_match.png', 'MatchEndView d’une série classée gagnée 2 – 1 avec XpSummaryPanel et la ligne Ligue.'),
  8: ('Casier, grille Avatars', '08_casier_avatars.png', 'LockerScreen, toute la hauteur de la grille.'),
  9: ('Casier, fiche d’un objet bloqué', '09_casier_fiche.png', 'Fléchettes croisées (niveau 27).'),
  10: ('Casier, lettres de l’avatar', '10_casier_lettres.png', 'Monogramme Acier équipé, « Ton double » T20.'),
  11: ('Casier, onglet Badges', '11_casier_badges.png', 'BadgePicker, toute la hauteur.'),
  12: ('Défi, avant l’essai', '12_defi_avant.png', ''),
  13: ('Défi, après l’essai', '13_defi_apres.png', ''),
  14: ('Défi, règle complète', '14_defi_regle.png', ''),
  15: ('Défi, classement complet', '15_defi_classement.png', 'ChallengeLeaderboardScreen, les 12 joueurs Or.'),
  16: ('Défi, écran de jeu', '16_defi_jeu.png', 'TrainingGameView monté comme ChallengePlayScreen, zone caméra vide (pas de caméra en test).'),
  17: ('Défi, résultat', '17_defi_resultat.png', 'ChallengeResultScreen.'),
  18: ('Défi, carte à partager', '18_defi_carte_partage.png', 'ChallengeStorySheet (ChallengeStoryCard) ouverte sur le résultat.'),
  19: ('Défi, podium d’hier', '19_defi_podium.png', 'ChallengePodiumScreen du 8 nov., toute la hauteur.'),
  20: ('Défi, session filmée du n°1', '20_defi_session.png', 'ChallengeSessionScreen, toute la hauteur. Pas de lecteur vidéo en test : la zone vidéo reste noire avec son indicateur de chargement.'),
  21: ('Ligue de la semaine', '21_ligue.png', 'LeagueScreen, Cuivre, 6ᵉ, toute la hauteur.'),
  22: ('Résultat de la ligue du lundi', '22_ligue_resultat.png', 'LeagueResultScreen : montée Acier → Cuivre.'),
  23: ('Liste des succès', '23_succes.png', 'AchievementsScreen, toute la hauteur.'),
  24: ('Fiche d’un succès', '24_succes_fiche.png', 'AchievementDetailScreen « Bulls », Argent, 64 / 100.'),
  25: ('Succès débloqué', '25_succes_debloque.png', 'AchievementUnlockSheet au retour sur l’accueil.'),
  26: ('Recherche classée, carte fantôme premium', '26_file_fantome_premium.png', ''),
  27: ('Recherche classée, carte fantôme gratuit', '27_file_fantome_gratuit.png', ''),
  28: ('Match trouvé (classé)', '28_match_trouve.png', ''),
  29: ('Match trouvé (fantôme)', '29_match_trouve_fantome.png', ''),
  30: ('Match contre un fantôme', '30_match_fantome.png', 'GhostMatchScreen : ma volée (T20, S20, S5) envoyée, puis la volée du fantôme rejouée sur la cible virtuelle (2 fléchettes sur 3). Pas de caméra en test : ce tour-là n’en montre pas.'),
  31: ('Résumé « Ton fantôme a joué »', '31_fantome_resume.png', 'GhostDigestScreen.'),
  32: ('Réglages du fantôme', '32_reglages_fantome.png', 'SettingsScreen avec GhostSettingsSection, toute la hauteur.'),
  33: ('Accueil d’un nouveau joueur', '33_accueil_nouveau_joueur.png', 'Jour 2 des 7 premiers jours, toute la hauteur.'),
  34: ('Parcours des 7 premiers jours', '34_parcours_7_jours.png', 'OnboardingJourneyScreen, jour 2.'),
  35: ('Bilan des 7 jours', '35_bilan_7_jours.png', 'OnboardingBilanScreen, jour 7.'),
  36: ('Admin web : onglet Défi du jour', '36_admin_defi_du_jour.png', 'Chrome sans interface, 1440 × 900, base locale.'),
  37: ('Admin web : onglet Fantôme', '37_admin_fantome.png', 'Chrome sans interface, 1440 × 900, base locale.'),
  38: ('Admin web : Succès à vérifier', '38_admin_succes_a_verifier.png', 'Chrome sans interface, 1440 × 900, base locale.'),
  39: ('Admin web : App Version', '39_admin_app_version.png', 'Champ « Progression pushes — minimum version » affiché, rien modifié.'),
};

String _file(int n) => _list[n]!.$2;

// ─── Fonts, content, assets ──────────────────────────────────────────────────

var _fontsLoaded = false;

Future<void> _loadFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final fonts = Directory('${Directory.current.path}/assets/fonts');
  final loader = FontLoader(AppTheme.fontFamily);
  final files = fonts.listSync().whereType<File>().where((f) => f.path.endsWith('.ttf')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    final bytes = await f.readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? File(Platform.resolvedExecutable).parent.parent.parent.path;
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons');
    final bytes = await icons.readAsBytes();
    l.addFont(Future.value(ByteData.view(bytes.buffer)));
    await l.load();
  }
  for (final (family, path) in const [
    (_systemFamily, '/System/Library/Fonts/SFNS.ttf'),
    (_glyphFamily, '/System/Library/Fonts/HelveticaNeue.ttc'),
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final l = FontLoader(family);
    final bytes = await file.readAsBytes();
    l.addFont(Future.value(ByteData.view(bytes.buffer)));
    await l.load();
  }
}

/// The phone's own font (San Francisco, the macOS file is the iPhone's).
const _systemFamily = 'PreviewSystemFont';

/// A glyph neither Manrope nor San Francisco has (« ᵉ », « ʳ »): the phone
/// takes it from another system font, Helvetica Neue here.
const _glyphFamily = 'PreviewGlyphFallback';

/// flutter_test draws a text without a font family (and a character Manrope
/// lacks, like « ᵉ ») with its box font, where a phone falls back on the
/// system font. Done here on the render tree, just before the picture: a text
/// without family is drawn in San Francisco (not Manrope: what the iPhone
/// shows), and every text falls back on it for a missing glyph. Returns how
/// many texts had no family.
int _systemFontFallback() {
  var bare = 0;
  for (final e in find.byType(RichText).evaluate()) {
    final ro = e.renderObject;
    if (ro is! RenderParagraph) continue;
    if (ro.text.style?.fontFamily == null) bare++;
    ro.text = _withSystemFallback(ro.text, root: true);
  }
  return bare;
}

/// The span tree again, each family followed by the system font (the
/// engine does not merge a parent's fallback into a child's family).
InlineSpan _withSystemFallback(InlineSpan span, {bool root = false}) {
  if (span is! TextSpan) return span;
  var style = span.style;
  if (root && style?.fontFamily == null) style = (style ?? const TextStyle()).copyWith(fontFamily: _systemFamily);
  if (style?.fontFamily != null && !(style!.fontFamilyFallback ?? const []).contains(_systemFamily)) {
    style = style.copyWith(fontFamilyFallback: [...?style.fontFamilyFallback, _systemFamily, _glyphFamily]);
  }
  return TextSpan(
    text: span.text,
    style: style,
    children: span.children?.map(_withSystemFallback).toList(),
    recognizer: span.recognizer,
    mouseCursor: span.mouseCursor,
    onEnter: span.onEnter,
    onExit: span.onExit,
    semanticsLabel: span.semanticsLabel,
    locale: span.locale,
    spellOut: span.spellOut,
  );
}

Map<String, dynamic> _read(String file) =>
    jsonDecode(File('$_backend/src/progression/content/$file').readAsStringSync()) as Map<String, dynamic>;

List<Map<String, dynamic>> _defs(String file) => (_read('defs/$file')['items'] as List).cast<Map<String, dynamic>>();

/// GET /progression/content, with each item's asset copied where
/// ProgressionAssetCache looks for it.
Map<String, dynamic> _contentJson(Directory cache) {
  final assets = Directory('$_backend/public/progression/items');
  final items = [..._read('items.json')['items'] as List, ..._read('badges.json')['items'] as List].cast<Map<String, dynamic>>();
  Directory('${cache.path}/progression/assets').createSync(recursive: true);
  for (final item in items) {
    for (final ext in const ['svg', 'webp', 'png']) {
      final f = File('${assets.path}/${item['id']}.$ext');
      if (!f.existsSync()) continue;
      f.copySync('${cache.path}/progression/assets/${item['id']}.preview.$ext');
      item['asset'] = {'url': '/progression/items/${item['id']}.$ext', 'format': ext, 'hash': 'preview'};
      break;
    }
  }
  final levels = _read('levels.json');
  return {
    'version': 'preview',
    'curve': levels['curve'],
    'prestige': levels['prestige'],
    'metals': _read('metals.json')['metals'],
    'items': items,
    'levels': levels['levels'],
    'events': _read('events.json')['events'],
    'defs': {
      'league': _defs('league.json'),
      'achievement': _defs('achievements.json'),
      'challenge_format': _defs('challenge_formats.json'),
      'onboarding': _defs('onboarding.json'),
      'ghost': _defs('ghost.json'),
    },
    // The constants the server serves (XP_RULES, ghost.json, challenge).
    'xp': {'ranked': 60, 'rankedWin': 40, 'friendly': 30, 'training': 30, 'ghost': 40, 'challenge': 50},
  };
}

late ProgressionContent _content;

// ─── The demo player: Dodo180 ────────────────────────────────────────────────

const _meId = 'u-me';
const _n1 = PublicBadge(id: 'b1', badgeId: 'badge.daily-first', tier: 'gold', date: '2026-11-06');
const _b180 = PublicBadge(id: 'b2', badgeId: 'badge.machine-a-180', tier: 'gold');
const _moy = PublicBadge(id: 'b3', badgeId: 'badge.grosse-moyenne', tier: 'silver');

const _myCosmetics = PublicCosmetics(
  level: 23,
  avatar: 'avatar.monogramme-acier',
  monogram: 'T20',
  frame: 'frame.laiton',
  background: 'background.liege',
  title: 'title.big-fish',
  flight: 'flight.cuivre',
  badges: [_n1, _b180, _moy],
);

Map<String, dynamic> _cosmeticsJson(PublicCosmetics c) => {
      'level': c.level,
      'avatar': c.avatar,
      'monogram': c.monogram,
      'frame': c.frame,
      'background': c.background,
      'title': c.title,
      'flight': c.flight,
      'badges': [
        for (final b in c.badges) {'id': b.id, 'badgeId': b.badgeId, 'tier': b.tier, 'date': b.date},
      ],
    };

const _laFleche = PublicCosmetics(
  level: 63,
  avatar: 'avatar.monogramme-legende',
  monogram: 'D16',
  frame: 'frame.legende',
  background: 'background.dans-le-mille',
  title: 'title.legende',
  badges: [_b180, _moy],
);
const _kev = PublicCosmetics(
  level: 41,
  avatar: 'avatar.trophee',
  monogram: 'KD',
  frame: 'frame.obsidienne',
  background: 'background.carbone',
  title: 'title.machine-a-180',
  badges: [_b180],
);
const _tripleTom = PublicCosmetics(level: 31, avatar: 'avatar.monogramme-acier', monogram: 'TT', frame: 'frame.laiton');

/// The ghost of the queue (§14.12): Bruno_T19, obsidian / carbon / trophy.
const _bruno = PublicCosmetics(
  level: 41,
  avatar: 'avatar.trophee',
  monogram: 'BT',
  frame: 'frame.obsidienne',
  background: 'background.carbone',
  title: 'title.machine-a-180',
  flight: 'flight.damier',
  badges: [_b180, _moy],
);

/// Level 23 at 51 % (xpToNext(23) = 1 580).
int get _xpInto => (_content.curve.xpToNext(23) * 0.51).round();

List<String> _ownedItems() {
  final levels = (_read('levels.json')['levels'] as List).cast<Map<String, dynamic>>();
  return [
    for (final l in levels)
      if ((l['level'] as int) <= 23) ...[...(l['itemIds'] as List).cast<String>(), ...(l['premiumItemIds'] as List).cast<String>()],
    // Checkout 170 (unique), the first promotion, Copper reached.
    'title.big-fish', 'avatar.170', 'title.grimpeur', 'background.cuivre',
  ];
}

Map<String, dynamic> _summaryJson() {
  final owned = _ownedItems();
  return {
    'level': 23,
    'xpTotal': _content.curve.xpForLevel(23) + _xpInto,
    'xpIntoLevel': _xpInto,
    'xpToNext': _content.curve.xpToNext(23),
    'levelSeen': 23,
    'isPremium': true,
    'nextRewards': {'level': 24, 'itemIds': ['flight.damier'], 'premiumItemIds': []},
    'itemsOwned': owned.length,
    'itemsTotal': (_read('items.json')['items'] as List).length,
    'equipment': {
      'avatar': _myCosmetics.avatar,
      'frame': _myCosmetics.frame,
      'background': _myCosmetics.background,
      'title': _myCosmetics.title,
      'flight': _myCosmetics.flight,
      'badges': ['b1', 'b2', 'b3'],
      'monogram': {'kind': 'double', 'value': 'T20'},
    },
    'cosmetics': _cosmeticsJson(_myCosmetics),
  };
}

QuestsSnapshot _quests() {
  final now = DateTime.now();
  final midnight = DateTime(now.year, now.month, now.day + 1);
  Map<String, dynamic> q(String id, String questId, String period, String fr, int progress, int threshold, int xp, {String? reward}) => {
        'id': id,
        'questId': questId,
        'period': period,
        'text': {'fr': fr, 'en': fr},
        'progress': progress,
        'threshold': threshold,
        'xp': xp,
        'status': progress >= threshold ? 'completed' : 'active',
        'rewardItemId': reward,
      };
  return QuestsSnapshot.fromJson({
    'daily': {
      'periodKey': '2026-11-09',
      'endsAt': midnight.toUtc().toIso8601String(),
      'rerollAvailable': true,
      'quests': [
        q('d1', 'q016', 'daily', 'Marque une volée à 100+', 1, 1, 40),
        q('d2', 'q021', 'daily', '5 triples dans une partie', 3, 5, 40),
        q('d3', 'q003', 'daily', 'Joue le défi du jour', 0, 1, 40),
      ],
    },
    'weekly': {
      'periodKey': '2026-11-09',
      'endsAt': midnight.add(const Duration(days: 6)).toUtc().toIso8601String(),
      'quests': [
        q('w1', 'q046', 'weekly', 'Termine 10 séries classées', 3, 10, 250),
        q('w2', 'q047', 'weekly', 'Joue 5 jours différents', 1, 5, 200),
        q('w3', 'q054', 'weekly', 'Bats un joueur mieux classé que toi', 1, 1, 250),
      ],
    },
    'discovery': {
      'quests': [
        q('x1', 'q083', 'discovery', 'Joue une partie de Cricket', 0, 1, 100),
        q('x2', 'q086', 'discovery', 'Regarde un match en spectateur', 0, 1, 50),
        q('x3', 'q081', 'discovery', 'Fais un exercice de chaque famille (horloge, scoring, finitions, doubles)', 3, 4, 100),
        q('x4', 'q076', 'discovery', 'Règle ta caméra', 1, 1, 50),
        q('x5', 'q077', 'discovery', 'Termine ton placement', 1, 1, 150),
        q('x6', 'q084', 'discovery', 'Ajoute un ami', 1, 1, 50),
      ],
    },
  });
}

/// My owned badges: one per achievement reached (highest tier), the pinned
/// three keep their ids b1–b3.
List<Map<String, dynamic>> _ownedBadges() {
  final out = <Map<String, dynamic>>[
    {'id': 'b1', 'badgeId': 'badge.daily-first', 'tier': 'gold', 'date': '2026-11-06'},
    {'id': 'b9', 'badgeId': 'badge.league-podium', 'tier': 'bronze', 'date': '2026-11-02'},
  ];
  for (final d in _defs('achievements.json')) {
    final a = _achievementJson(d);
    final tier = a['tier'] as String?;
    if (tier == null) continue;
    final id = switch (d['id']) {
      'machine-a-180' => 'b2',
      'grosse-moyenne' => 'b3',
      _ => 'ub-${d['id']}',
    };
    out.add({'id': id, 'badgeId': d['badgeId'], 'tier': tier == 'unique' ? null : tier});
  }
  return out;
}

Map<String, dynamic> _inventoryJson() => {
      'items': [
        for (final id in _ownedItems()) {'itemId': id, 'source': 'level', 'isNew': id == 'flight.cuivre'},
      ],
      'badges': _ownedBadges(),
      'equipment': _summaryJson()['equipment'],
    };

/// No refresh ever reaches the network (the seeded data stays).
class _Progression extends ProgressionProvider {
  @override
  Future<void> bootstrap() async {}
  @override
  Future<void> refreshSummary() async {}
  @override
  Future<void> refreshQuests() async {}
  @override
  Future<void> refreshContent() async {}
  @override
  Future<void> refreshInventory() async {}
  @override
  Future<void> markItemsSeen(List<String> itemIds) async {}
  @override
  Future<void> ensurePlayers(Iterable<String?> userIds) async {}
}

_Progression _dodoProgression() => _Progression()
  ..debugSeed(
    content: _content,
    summary: ProgressionSummary.fromJson(_summaryJson()),
    quests: _quests(),
    inventory: Inventory.fromJson(_inventoryJson()),
  );

class _Auth extends AuthProvider {
  final User user;
  _Auth(this.user);
  @override
  User? get currentUser => user;
}

User _dodo() => User(id: _meId, username: 'Dodo180', email: 'dodo@dartrivals.app', elo: 1409, rank: 'gold', isPremium: true);

class _Subscription extends SubscriptionProvider {
  final bool premium;
  _Subscription(this.premium);
  @override
  bool get isPremiumActive => premium;
  @override
  bool get hasPaidSubscription => premium;
  @override
  DateTime? get premiumExpiresAt => premium ? DateTime(2027, 1, 12) : null;
  @override
  bool get isLoading => false;
  @override
  int? get matchesRemainingToday => premium ? null : 1;
  @override
  Future<void> refresh() async {}
}

class _Referral extends ReferralProvider {
  @override
  ReferralOverview? get overview => ReferralOverview(
        code: 'DODO-180X',
        canCreateCode: true,
        isEmailVerified: true,
        rewardMonthlyCents: 500,
        rewardYearlyCents: 1000,
        refereeTrialDays: 7,
        earnedCents: 0,
        pendingCents: 0,
        referees: const [],
        redeem: const ReferralEligibility(eligible: false),
        referredByUsername: null,
      );
  @override
  bool get canRedeem => false;
  @override
  bool get isLoading => false;
  @override
  Future<void> loadOverview() async {}
}

class _Locale extends LocaleProvider {
  @override
  Locale get locale => const Locale('fr');
}

class _Onboarding extends OnboardingProvider {
  @override
  Future<void> refresh() async {}
  @override
  Future<void> markBilanSeen() async {}
}

// ─── Daily challenge (the data of the copied defi_simple PNGs) ──────────────

Map<String, dynamic> _format(String id) => _defs('challenge_formats.json').firstWhere((f) => f['id'] == id);

ChallengeToday _today({Map<String, dynamic>? ranked}) => ChallengeToday.fromJson({
      'date': '2026-11-09',
      'endsAt': DateTime.now().add(const Duration(hours: 14, minutes: 30)).toUtc().toIso8601String(),
      'format': _format('cricket-30'),
      'board': {'rank': 'gold', 'ranks': ['gold'], 'open': true, 'players': 12, 'eloBonus': 24},
      'players': 21,
      'ranked': ranked,
      'streak': {
        'current': ranked == null ? 4 : 5,
        'best': 6,
        'freezeAvailable': true,
        'days': [
          for (var i = 3; i <= 9; i++) {'date': '2026-11-0$i', 'played': i >= 5 && (i < 9 || ranked != null), 'today': i == 9},
        ],
      },
      'remind': true,
      'yesterday': {'date': '2026-11-08', 'crownId': 'c1', 'board': 'gold', 'userId': 'u-tom', 'username': 'TripleTom', 'score': 44, 'verified': true},
    })!;

const _myAttempt = {'id': 'a1', 'status': 'submitted', 'score': 38, 'finished': true, 'position': 4, 'total': 12};

const _goldBoard = <(String, String, int)>[
  ('TripleTom', 'platinum', 41),
  ('Kev_D20', 'gold', 40),
  ('LaFleche', 'gold', 39),
  ('Dodo180', 'gold', 38),
  ('Juju180', 'platinum', 36),
  ('Mika_T19', 'gold', 35),
  ('Bruno_T19', 'gold', 33),
  ('Steph_D16', 'gold', 31),
  ('Nico_Bull', 'gold', 29),
  ('Lou_T20', 'gold', 26),
  ('Sam_Shot', 'gold', 22),
  ('Big_Jim', 'gold', 17),
];

ChallengeLeaderboard _leaderboard() => ChallengeLeaderboard.fromJson({
      'date': '2026-11-09',
      'view': 'rank',
      'board': {'rank': 'gold', 'ranks': ['gold'], 'open': true, 'players': 12},
      'counts': {'rank': 12, 'all': 21, 'friends': 3},
      'rows': [
        for (var i = 0; i < _goldBoard.length; i++)
          {
            'position': i + 1,
            'userId': _goldBoard[i].$1 == 'Dodo180' ? _meId : 'u${i + 1}',
            'username': _goldBoard[i].$1,
            'rank': _goldBoard[i].$2,
            'score': _goldBoard[i].$3,
            'me': _goldBoard[i].$1 == 'Dodo180',
            'crown': i == 0,
            if (i == 0) 'cosmetics': _cosmeticsJson(_tripleTom),
            if (_goldBoard[i].$1 == 'Dodo180') 'cosmetics': _cosmeticsJson(_myCosmetics),
          },
      ],
    });

Map<String, dynamic> _resultJson() => {
      'date': '2026-11-09',
      'endsAt': DateTime.now().add(const Duration(hours: 14, minutes: 30)).toUtc().toIso8601String(),
      'format': _format('cricket-30'),
      'attempt': {'id': 'a1', 'ranked': true, 'status': 'submitted', 'score': 38, 'perVisit': [5, 4, 3, 6, 4, 2, 5, 3, 4, 2], 'finished': true, 'darts': 30},
      'standing': {'board': 'gold', 'ranks': ['gold'], 'open': true, 'position': 4, 'total': 12, 'rankPct': 33, 'top10': false, 'allPosition': 7, 'allTotal': 21, 'eloBonus': 24},
      'passed': [
        {'username': 'Juju180', 'score': 36},
        {'username': 'Mika_T19', 'score': 35},
      ],
      'leader': {'username': 'TripleTom', 'score': 41},
      'streak': {'current': 5, 'best': 6},
      'xp': [
        {'source': 'challenge', 'amount': 50},
      ],
      'proof': {'required': false, 'status': 'none'},
    };

Map<String, dynamic> _podiumJson() => {
      'date': '2026-11-08',
      'available': true,
      'closed': true,
      'format': _format('cricket-30'),
      'board': {'rank': 'gold', 'ranks': ['gold'], 'open': true, 'players': 11},
      'eloBonus': 24,
      'crown': {
        'crownId': 'c1',
        'userId': 'u-tom',
        'username': 'TripleTom',
        'score': 44,
        'status': 'paid',
        'verified': true,
        'aiDarts': 30,
        'correctedDarts': 0,
        'darts': 30,
      },
      'top': [
        {'position': 1, 'userId': 'u-tom', 'username': 'TripleTom', 'rank': 'platinum', 'score': 44, 'crown': true, 'cosmetics': _cosmeticsJson(_tripleTom)},
        {'position': 2, 'userId': 'u2', 'username': 'Kev_D20', 'rank': 'gold', 'score': 42},
        {'position': 3, 'userId': 'u3', 'username': 'LaFleche', 'rank': 'gold', 'score': 40},
        {'position': 4, 'userId': 'u4', 'username': 'Mika_T19', 'rank': 'gold', 'score': 37},
        {'position': 5, 'userId': _meId, 'username': 'Dodo180', 'rank': 'gold', 'score': 36, 'me': true, 'cosmetics': _cosmeticsJson(_myCosmetics)},
      ],
      'me': {'status': 'submitted', 'score': 36, 'position': 5, 'total': 11, 'top10': false, 'xp': 50},
    };

Map<String, dynamic> _sessionJson() {
  final t0 = DateTime(2026, 11, 8, 19, 42).millisecondsSinceEpoch;
  const visits = [
    ['T20', 'T20', 'S20'],
    ['T19', 'S19', 'S19'],
    ['T18', 'S18', 'S1'],
    ['S17', 'T17', 'S17'],
    ['T16', 'S16', 'S8'],
    ['T15', 'S15', 'S2'],
    ['DB', 'S25', 'S5'],
    ['T20', 'S20', 'S3'],
    ['T19', 'S7', 'S19'],
    ['T18', 'S18', 'S4'],
  ];
  return {
    'crownId': 'c1',
    'date': '2026-11-08',
    'board': 'gold',
    'format': _format('cricket-30'),
    'player': {'userId': 'u-tom', 'username': 'TripleTom', 'rank': 'platinum', 'cosmetics': _cosmeticsJson(_tripleTom)},
    'score': 44,
    'finished': true,
    'darts': 30,
    'aiDarts': 30,
    'correctedDarts': 0,
    'verified': true,
    'visits': [
      for (var i = 0; i < visits.length; i++)
        {
          't': t0 + 15000 + i * 21000,
          'value': [7, 5, 4, 5, 4, 4, 3, 4, 4, 4][i],
          'darts': [
            for (final n in visits[i]) {'n': n, 'ai': true},
          ],
        },
    ],
    'clips': [
      {'url': 'https://media.dartrivals.app/preview/challenge-c1.mp4', 'startWallMs': t0, 'durationMs': 240000},
    ],
    'reportable': true,
    'reported': false,
  };
}

// ─── Weekly league ───────────────────────────────────────────────────────────

Map<String, dynamic> _tier(String id) {
  final t = _defs('league.json').firstWhere((d) => d['id'] == id);
  return {'id': t['id'], 'order': t['order'], 'name': t['name'], 'color': t['color'], 'colors': t['colors']};
}

List<Map<String, dynamic>> _ladder() => [
      for (final d in _defs('league.json'))
        if (d['type'] == 'tier') _tier(d['id'] as String),
    ];

const _leagueRows = <(String, String, int, int)>[
  ('Kev_D20', 'gold', 1388, 210),
  ('Mika_T19', 'gold', 1442, 190),
  ('Juju180', 'platinum', 1606, 170),
  ('Steph_D16', 'gold', 1351, 150),
  ('LaFleche', 'platinum', 1612, 140),
  ('Dodo180', 'gold', 1409, 120),
  ('Nico_Bull', 'silver', 1188, 110),
  ('Sam_Shot', 'gold', 1290, 90),
  ('Lou_T20', 'silver', 1150, 80),
  ('TripleTom', 'platinum', 1655, 70),
  ('Big_Jim', 'silver', 1102, 60),
  ('Bruno_T19', 'gold', 1398, 50),
  ('Leo_D20', 'silver', 1050, 40),
  ('Max_Treble', 'gold', 1230, 40),
  ('Ana_D8', 'silver', 990, 30),
  ('Paulo_180', 'gold', 1261, 20),
  ('Rico_T17', 'silver', 1012, 10),
  ('Zoe_Bull', 'bronze', 860, 0),
  ('Hugo_Steel', 'silver', 1170, 0),
  ('Tim_D1', 'bronze', 812, 0),
];

PublicCosmetics? _rowCosmetics(String name) => switch (name) {
      'Dodo180' => _myCosmetics,
      'Kev_D20' => _kev,
      'LaFleche' => _laFleche,
      'TripleTom' => _tripleTom,
      'Bruno_T19' => _bruno,
      _ => null,
    };

Map<String, dynamic> _leagueJson() => {
      'enabled': true,
      'weekKey': '2026-11-09',
      'weekNumber': 46,
      'endsAt': '2026-11-15T21:00:00.000Z',
      'nextStartsAt': '2026-11-16T00:00:00.000Z',
      'league': _tier('cuivre'),
      'ladder': _ladder(),
      'pointRules': (_defs('league.json').firstWhere((d) => d['type'] == 'settings')['points'] as List),
      'hasResult': false,
      'state': 'open',
      'firstWeek': false,
      'group': {
        'id': 'g-46',
        'size': 20,
        'promoteCount': 5,
        'relegateCount': 5,
        'promoteTo': _tier('or'),
        'relegateTo': _tier('acier'),
        'standings': [
          for (var i = 0; i < _leagueRows.length; i++)
            {
              'position': i + 1,
              'userId': _leagueRows[i].$1 == 'Dodo180' ? _meId : 'l${i + 1}',
              'username': _leagueRows[i].$1,
              'elo': _leagueRows[i].$3,
              'rank': _leagueRows[i].$2,
              'league': 'cuivre',
              'points': _leagueRows[i].$4,
              'isMe': _leagueRows[i].$1 == 'Dodo180',
              if (_rowCosmetics(_leagueRows[i].$1) != null) 'cosmetics': _cosmeticsJson(_rowCosmetics(_leagueRows[i].$1)!),
            },
        ],
      },
      'me': {'position': 6, 'points': 120},
    };

Map<String, dynamic> _leagueResultJson() => {
      'weekKey': '2026-11-02',
      'weekNumber': 45,
      'league': _tier('acier'),
      'leagueAfter': _tier('cuivre'),
      'outcome': 'promoted',
      'position': 3,
      'groupSize': 20,
      'points': 1010,
      'xp': 200,
      'itemIds': ['title.grimpeur', 'background.cuivre'],
      'badge': {'badgeId': 'badge.league-podium', 'tier': 'bronze'},
      'promotedWith': ['Mika_T19', 'Steph_D16'],
      'next': {'weekKey': '2026-11-09', 'groupSize': 20, 'endsAt': '2026-11-15T21:00:00.000Z'},
      'ladder': _ladder(),
    };

// ─── Achievements ────────────────────────────────────────────────────────────

/// Dodo180's counters (the rest is 0). Remontada's silver tier waits for an
/// admin (the local demo database has that dossier).
const _achValues = <String, num>{
  'machine-a-180': 104,
  'volees-de-100': 412,
  'volees-de-140': 61,
  'triples': 1840,
  'bulls': 64,
  'grosse-moyenne': 62.4,
  'depart-canon': 226,
  'points-marques': 412000,
  'manche-eclair': 16,
  'tir-groupe': 1,
  'checkout-100': 9,
  'checkout-170': 1,
  'finir-au-bull': 3,
  'checkouts': 148,
  'madhouse': 1,
  'tops': 31,
  'premier-jet': 12,
  'precision-au-double': 44,
  'remontada': 287,
  'zero-bust': 18,
  'tous-les-doubles': 9,
  'calcul': 640,
  'dernier-mot': 4,
  'fidele': 41,
  'semaine-pleine': 9,
  'series-classees': 212,
  'victoires-classees': 118,
  'imbattable': 6,
  'bras-d-acier': 38000,
  'bosseur': 74,
  'records': 11,
  'oiseau-de-nuit': 7,
  'quetes': 186,
  'habitue': 23,
  'serie-du-defi': 6,
  'top-10-du-defi': 8,
  'n-1-du-jour': 1,
  'leve-tot': 2,
  'grimpeur-de-rang': 4,
  'tueur-de-geants': 1,
  'chasseur-de-fantomes': 2,
  'entoure': 4,
  'entre-potes': 12,
  'spectateur': 3,
  'fantome-redoute': 3,
  'collectionneur': 34,
};

const _pendingTiers = {'remontada': 'silver'};

String _aggregateOf(Map<String, dynamic> d) {
  final counter = d['counter'] as Map<String, dynamic>;
  final group = counter['group'];
  if (group is Map) return group['aggregate'] == 'max' ? 'max' : 'count';
  return (counter['aggregate'] as String?) ?? 'count';
}

Map<String, dynamic> _achievementJson(Map<String, dynamic> d, {List<Map<String, dynamic>> recent = const []}) {
  final id = d['id'] as String;
  final value = (_achValues[id] ?? 0).toDouble();
  final lower = _aggregateOf(d) == 'min';
  bool reached(num threshold) => value > 0 && (lower ? value <= threshold : value >= threshold);
  final tiers = (d['tiers'] as List?)?.cast<Map<String, dynamic>>();
  final unique = d['unique'] as Map<String, dynamic>?;
  final rawSteps = tiers ??
      [
        {'tier': 'unique', 'threshold': unique?['threshold'] ?? 1, 'xp': unique?['xp'] ?? 500, 'itemIds': unique?['itemIds'] ?? []},
      ];
  final pending = _pendingTiers[id];
  final steps = <Map<String, dynamic>>[];
  String? tier;
  var day = 0;
  for (final s in rawSteps) {
    final got = reached(s['threshold'] as num) && s['tier'] != pending && !(pending != null && tier == pending);
    if (got) tier = s['tier'] as String;
    day += 9;
    final rarity = switch (s['tier']) {
      'bronze' => 38.0,
      'silver' => 11.0,
      'gold' => 2.4,
      _ => 4.1,
    } * (0.6 + (id.hashCode % 7) / 10);
    steps.add({
      'tier': s['tier'],
      'threshold': s['threshold'],
      'xp': s['xp'],
      'itemIds': s['itemIds'],
      'label': s['label'],
      'unlockedAt': got ? DateTime(2026, 8, 20).add(Duration(days: day + id.length)).toUtc().toIso8601String() : null,
      'rarity': double.parse(rarity.toStringAsFixed(1)),
      'pending': s['tier'] == pending,
    });
  }
  // The next tier to reach (none once the last one is reached).
  Map<String, dynamic>? next;
  final nextStep = steps.where((s) => s['unlockedAt'] == null).firstOrNull;
  if (nextStep != null) {
    final threshold = (nextStep['threshold'] as num).toDouble();
    final ratio = lower
        ? (value == 0 ? 0.0 : (threshold / value).clamp(0.0, 1.0))
        : (value / threshold).clamp(0.0, 1.0);
    next = {'tier': nextStep['tier'], 'threshold': threshold, 'ratio': double.parse(ratio.toStringAsFixed(3)), 'label': nextStep['label']};
  }
  return {
    'id': id,
    'family': d['family'],
    'sortOrder': d['sortOrder'],
    'name': d['name'],
    'description': d['description'],
    'badgeId': d['badgeId'],
    'aiOnly': d['aiOnly'],
    'format': d['format'] ?? 'int',
    'aggregate': _aggregateOf(d),
    'unique': tiers == null,
    'tier': tier,
    'value': value,
    'best': null,
    'next': next,
    'steps': steps,
    'rarity': steps.first['rarity'],
    'unlockedAt': steps.lastWhere((s) => s['unlockedAt'] != null, orElse: () => const {})['unlockedAt'],
    'requires': d['requires'],
    'pendingReview': pending != null,
    if (recent.isNotEmpty) 'recent': recent,
  };
}

Map<String, dynamic> _achievementsJson() {
  final list = [for (final d in _defs('achievements.json')) _achievementJson(d)];
  // As the server (closestAchievement): a "lower is better" one is left out.
  Map<String, dynamic>? closest;
  for (final a in list) {
    if (a['aggregate'] == 'min') continue;
    final n = a['next'] as Map<String, dynamic>?;
    if (n == null) continue;
    final r = n['ratio'] as double;
    if (r <= 0 || r >= 1) continue;
    if (closest == null || r > ((closest['next'] as Map)['ratio'] as double)) closest = a;
  }
  return {
    'families': [
      {'id': 'scoring', 'name': {'fr': 'Scoring', 'en': 'Scoring'}},
      {'id': 'finishing', 'name': {'fr': 'Finition', 'en': 'Finishing'}},
      {'id': 'consistency', 'name': {'fr': 'Régularité', 'en': 'Consistency'}},
      {'id': 'competition', 'name': {'fr': 'Défis et compétition', 'en': 'Challenges & competition'}},
      {'id': 'social', 'name': {'fr': 'Social', 'en': 'Social'}},
    ],
    'achievements': list,
    'unlocked': list.where((a) => a['tier'] != null).length,
    'total': list.length,
    'closestId': closest?['id'],
  };
}

Map<String, dynamic> _bullsDetailJson() => _achievementJson(
      _defs('achievements.json').firstWhere((d) => d['id'] == 'bulls'),
      recent: [
        {'at': DateTime.now().subtract(const Duration(hours: 2)).toUtc().toIso8601String(), 'value': 50, 'mode': 'ranked', 'matchId': 'm-3', 'opponent': {'id': 'u-kev', 'username': 'Kev_D20'}, 'legNumber': 3},
        {'at': DateTime.now().subtract(const Duration(days: 1, hours: 3)).toUtc().toIso8601String(), 'value': 25, 'mode': 'ranked', 'matchId': 'm-2', 'opponent': {'id': 'u-fl', 'username': 'LaFleche'}, 'legNumber': 1},
        {'at': DateTime.now().subtract(const Duration(days: 2)).toUtc().toIso8601String(), 'value': 50, 'mode': 'training', 'matchId': null},
      ],
    );

Map<String, dynamic> _unseenJson() => {
      'unlocks': [
        {
          'id': 'un-1',
          'achievementId': 'volees-de-140',
          'tier': 'silver',
          'retro': false,
          'xp': 250,
          'itemIds': [],
          'context': {'matchId': 'm-3', 'value': 140},
          'name': {'fr': 'Volées de 140+', 'en': '140+ Visits'},
          'badgeId': 'badge.volees-de-140',
          'unlockedAt': DateTime.now().subtract(const Duration(minutes: 3)).toUtc().toIso8601String(),
          'threshold': 25,
          'format': 'int',
          'rarity': 9.8,
          'next': {'tier': 'gold', 'threshold': 100, 'itemIds': ['title.gros-calibre']},
          'userBadgeId': 'ub-volees-de-140',
        },
      ],
    };

// ─── Ghost ───────────────────────────────────────────────────────────────────

Map<String, dynamic> _ghostOpponent() => {
      'ownerId': 'u-bruno',
      'username': 'Bruno_T19',
      'elo': 1398,
      'rank': 'gold',
      'cosmetics': _cosmeticsJson(_bruno),
      'playedAt': '2026-11-02T19:00:00.000Z',
      'average': 55.2,
    };

Map<String, dynamic> _ghostMatchJson({int playerRemaining = 322, int ghostRemaining = 260, int nextVisitIndex = 7}) => {
      'id': 'g-1',
      'status': 'in_progress',
      'bestOf': 3,
      'legsToWin': 2,
      'currentLeg': 1,
      'playerLegsWon': 1,
      'ghostLegsWon': 0,
      'legStarter': 'ghost',
      'turn': 'player',
      'nextVisitIndex': nextVisitIndex,
      'playerRemaining': playerRemaining,
      'ghostRemaining': ghostRemaining,
      'playerAverage': 58.4,
      'ghostAverageLive': 55.0,
      'eloEligible': true,
      'eloIfWin': 13,
      'eloIfLoss': -12,
      'ghost': _ghostOpponent(),
    };

Map<String, dynamic> _ghostVisitResultJson() => {
      'duplicate': false,
      'visit': {'leg': 1, 'index': 7, 'score': 85, 'busted': false, 'checkout': false, 'remaining': 237},
      'ghostVisits': [
        {
          'leg': 1,
          'index': 7,
          'score': 100,
          'remaining': 160,
          'darts': [
            {'notation': 'T20', 'radius': 0.61, 'angle': 4.69, 'delayMs': 500},
            {'notation': 'S20', 'radius': 0.78, 'angle': 4.75, 'delayMs': 600},
            {'notation': 'T20', 'radius': 0.6, 'angle': 4.72, 'delayMs': 20000},
          ],
        },
      ],
      'match': _ghostMatchJson(playerRemaining: 237, ghostRemaining: 160, nextVisitIndex: 8),
    };

Map<String, dynamic> _digestJson() => {
      'count': 3,
      'ghostWins': 2,
      'ghostLosses': 1,
      'xp': 40,
      'source': {'playedAt': '2026-11-02T19:00:00.000Z', 'average': 57.3},
      'beatenBy': {'username': 'Mika_T19', 'userId': 'u-mika', 'darts': 4},
      'games': [
        {'id': 'gd-1', 'opponentId': 'u-kev', 'opponentUsername': 'Kev_D20', 'ghostWon': true, 'ghostLegs': 2, 'opponentLegs': 1, 'finishedAt': DateTime.now().subtract(const Duration(hours: 9)).toUtc().toIso8601String()},
        {'id': 'gd-2', 'opponentId': 'u-mika', 'opponentUsername': 'Mika_T19', 'ghostWon': false, 'ghostLegs': 1, 'opponentLegs': 2, 'finishedAt': DateTime.now().subtract(const Duration(hours: 7)).toUtc().toIso8601String()},
        {'id': 'gd-3', 'opponentId': 'u-juju', 'opponentUsername': 'Juju180', 'ghostWon': true, 'ghostLegs': 2, 'opponentLegs': 0, 'finishedAt': DateTime.now().subtract(const Duration(hours: 4)).toUtc().toIso8601String()},
      ],
    };

// ─── Onboarding (a new player: Tom_D16) ──────────────────────────────────────

Map<String, dynamic> _step(String id, int day, String fr, String status, String action, int xp, {Map<String, dynamic>? item, int premiumDays = 0}) => {
      'id': id,
      'day': day,
      'title': {'fr': fr, 'en': fr},
      'status': status,
      'action': action,
      'xp': xp,
      'rewardItem': item,
      'premiumDays': premiumDays,
      'progress': status == 'done' ? 1 : 0,
      'threshold': 1,
    };

const _recrue = {'id': 'title.nouvelle-recrue', 'type': 'title', 'name': {'fr': 'Nouvelle recrue', 'en': 'New Recruit'}};
const _debutant = {'id': 'frame.debutant', 'type': 'frame', 'name': {'fr': 'Débutant', 'en': 'Rookie'}};

OnboardingStatus _day2() => OnboardingStatus.fromJson({
      'active': true,
      'status': 'active',
      'day': 2,
      'journeyDays': 7,
      'maxDays': 14,
      'doneCount': 2,
      'totalCount': 7,
      'currentStepId': 'visit-60',
      'premiumDays': 7,
      'steps': [
        _step('camera', 1, 'Régler ta caméra', 'done', 'bot_301', 50),
        _step('bot-301', 1, 'Un 301 contre un bot', 'done', 'bot_301', 100),
        _step('visit-60', 2, 'Une volée à 60 ou plus', 'open', 'bot_301', 80),
        _step('placement-1', 3, 'Ton premier match de placement', 'locked', 'placement', 150, item: _recrue),
        _step('challenge', 4, 'Le défi du jour', 'locked', 'challenge', 100),
        _step('friend', 5, 'Ajouter un ami', 'locked', 'friends', 100),
        _step('bilan', 7, 'Ton bilan de la semaine', 'locked', 'bilan', 150, item: _debutant, premiumDays: 7),
      ],
    });

OnboardingStatus _day7() => OnboardingStatus.fromJson({
      'active': true,
      'status': 'completed',
      'day': 7,
      'doneCount': 7,
      'totalCount': 7,
      'premiumDays': 7,
      'premiumUntil': DateTime.now().add(const Duration(days: 7)).toUtc().toIso8601String(),
      'bilanSeen': false,
      'bilan': {'matches': 14, 'average': 44.6, 'averageStart': 38.2, 'averageDelta': 6.4, 'bestVisit': 140, 'rank': 'silver'},
      'steps': [
        _step('camera', 1, 'Régler ta caméra', 'done', 'bot_301', 50),
        _step('bot-301', 1, 'Un 301 contre un bot', 'done', 'bot_301', 100),
        _step('visit-60', 2, 'Une volée à 60 ou plus', 'done', 'bot_301', 80),
        _step('placement-1', 3, 'Ton premier match de placement', 'done', 'placement', 150, item: _recrue),
        _step('challenge', 4, 'Le défi du jour', 'done', 'challenge', 100),
        _step('friend', 5, 'Ajouter un ami', 'done', 'friends', 100),
        _step('bilan', 7, 'Ton bilan de la semaine', 'done', 'bilan', 150, item: _debutant, premiumDays: 7),
      ],
    });

_Progression _tomProgression({required int level, String? frame, String? title}) {
  final cosmetics = {'level': level, 'monogram': 'TD', 'frame': frame, 'title': title, 'badges': []};
  return _Progression()
    ..debugSeed(
      content: _content,
      summary: ProgressionSummary.fromJson({
        'level': level,
        'xpTotal': _content.curve.xpForLevel(level) + 120,
        'xpIntoLevel': 120,
        'xpToNext': _content.curve.xpToNext(level),
        'levelSeen': level,
        'isPremium': false,
        'equipment': {'frame': frame, 'title': title},
        'cosmetics': cosmetics,
      }),
      quests: QuestsSnapshot.fromJson({
        'daily': {
          'quests': [
            {'id': 'd1', 'questId': 'q006', 'period': 'daily', 'text': {'fr': 'Termine un match contre le bot', 'en': 'x'}, 'progress': 0, 'threshold': 1, 'xp': 40},
          ],
        },
      }),
      inventory: Inventory.fromJson({'items': [], 'equipment': {'frame': frame, 'title': title}}),
    );
}

// ─── The in-memory server ────────────────────────────────────────────────────

/// What ApiService asks during each screen, answered with the demo data.
/// Unknown routes get a 404 (logged): a screen that needs one shows it.
Object? _api(String method, String path) {
  switch ('$method $path') {
    case 'GET /users/$_meId/stats':
      return {
        'stats': {
          'totalMatches': 212,
          'winRate': 55.7,
          'threeDartAverage': 52.6,
          'count180s': 104,
          'currentStreak': 3,
          'wins': 118,
          'losses': 94,
          'legsCounted': 498,
          'biggestCheckout': 170,
          'finishingDoublePercentage': 31.4,
        },
        'cosmetics': _cosmeticsJson(_myCosmetics),
      };
    case 'GET /stats/profile/$_meId':
      return {
        'percentiles': {
          'cohort': {'scope': 'rank', 'rank': 'gold', 'size': 64, 'windowDays': 90, 'minLegs': 10},
          'eligible': true,
          'legs': 236,
          'legsUntilEligible': 0,
          'level': {
            'overall': 71,
            'metrics': [
              {'key': 'average', 'value': 52.6, 'percentile': 72, 'median': 47.9},
              {'key': 'first9', 'value': 58.1, 'percentile': 70, 'median': 53.4},
              {'key': 'scoringAverage', 'value': 59.3, 'percentile': 74, 'median': 54.0},
              {'key': 'finishingAverage', 'value': 38.2, 'percentile': 66, 'median': 34.7},
              {'key': 'checkoutPct', 'value': 31.4, 'percentile': 81, 'median': 22.0},
            ],
          },
        },
        'impacts': {
          'scoring': [for (final d in vatiImpacts.scoring) {'radius': d.radius, 'angle': d.angle, 'treble': d.good}],
          'doubles': [for (final d in vatiImpacts.doubles) {'radius': d.radius, 'angle': d.angle, 'hit': d.good}],
        },
        'doubles': [
          {'double': 'D16', 'hits': 31, 'attempts': 88, 'pct': 35.2},
          {'double': 'D20', 'hits': 22, 'attempts': 71, 'pct': 31.0},
          {'double': 'D8', 'hits': 17, 'attempts': 52, 'pct': 32.7},
          {'double': 'D10', 'hits': 12, 'attempts': 44, 'pct': 27.3},
          {'double': 'D4', 'hits': 9, 'attempts': 30, 'pct': 30.0},
          {'double': 'Bull', 'hits': 3, 'attempts': 21, 'pct': 14.3},
        ],
      };
    case 'GET /achievements/summary':
      final a = _achievementsJson();
      return {'unlocked': a['unlocked'], 'total': a['total'], 'tiers': 58};
    case 'GET /achievements':
      return _achievementsJson();
    case 'GET /achievements/unseen':
      return _unseenJson();
    case 'GET /achievements/unlocked':
      return {'unlocks': []};
    case 'GET /progression/me/xp':
      final summary = _summaryJson();
      return {
        'entries': [
          {'source': 'ranked_series', 'refId': 's-1', 'amount': 60, 'label': {'fr': 'Série classée', 'en': 'Ranked series'}},
          {'source': 'ranked_series_win', 'refId': 's-1', 'amount': 40, 'label': {'fr': 'Victoire', 'en': 'Win'}},
          {'source': 'quest', 'refId': 'w3', 'amount': 250, 'label': {'fr': 'Quête « Bats un joueur mieux classé que toi »', 'en': 'Quest'}},
          {'source': 'achievement', 'refId': 'volees-de-140:silver', 'amount': 250, 'label': {'fr': 'Succès', 'en': 'Achievement'}},
        ],
        'totalAmount': 600,
        'levelBefore': 23,
        'levelAfter': 23,
        'levelUps': [],
        'progression': summary,
      };
    case 'GET /stats/match/m-3':
      return {
        'matchId': 'm-3',
        'seriesId': 's-1',
        'legs': 3,
        'gameMode': 'x01',
        'me': {'username': 'Dodo180', 'average': 61.8, 'bestVisit': 140, 'count180': 0, 'doublesHit': 2, 'doublesAttempted': 6, 'checkoutPct': 33.3, 'bestCheckout': 81},
        'opponent': {'username': 'Kev_D20', 'average': 58.2, 'bestVisit': 180, 'count180': 1, 'doublesHit': 1, 'doublesAttempted': 7, 'checkoutPct': 14.3, 'bestCheckout': 40},
        'windowAverage': 52.6,
        'windowDays': 30,
      };
    case 'GET /challenge/podium':
      return _podiumJson();
    case 'GET /challenge/sessions/c1':
      return _sessionJson();
    case 'GET /challenge/today':
      return null;
    case 'GET /league/me':
      return _leagueJson();
    case 'GET /ghost/owner/digest':
      return _digestJson();
    case 'GET /ghost/settings':
      return {'enabled': true, 'notify': true};
    case 'GET /ghost/active':
      return <String, dynamic>{};
    case 'GET /ghost/proof/pending':
    case 'GET /challenge/proof/pending':
      return <Object>[];
    case 'POST /ghost/matches/g-1/visits':
      return _ghostVisitResultJson();
    case 'GET /replays/mine':
      return {'clips': [], 'total': 3, 'limit': 50};
    case 'GET /users/me/notification-settings':
      return {'friendOnline': true};
    case 'GET /progression/cosmetics':
      return {'players': {}};
    case 'POST /progression/client-events':
    case 'POST /achievements/seen':
    case 'POST /ghost/owner/digest/seen':
    case 'POST /league/result/seen':
      return {'ok': true};
  }
  return null;
}

final _unknownRoutes = <String>{};

MockClient _server() => MockClient((req) async {
      final body = _api(req.method, req.url.path);
      if (body == null) {
        _unknownRoutes.add('${req.method} ${req.url.path}');
        return http.Response(jsonEncode({'message': 'preview: no route'}), 404, headers: {'content-type': 'application/json'});
      }
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });

// ─── Harness ─────────────────────────────────────────────────────────────────

const _phoneW = 390.0;
const _phoneH = 844.0;

class _H {
  final WidgetTester t;
  final key = GlobalKey();
  _H(this.t);

  /// The app as main.dart builds it for these screens (French, theme D,
  /// providers), [key] around the whole navigator so sheets are captured.
  Future<void> open(
    Widget home, {
    ProgressionProvider? progression,
    User? user,
    bool premium = true,
    OnboardingProvider? onboarding,
  }) async {
    final p = progression ?? _dodoProgression();
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ProgressionProvider>.value(value: p),
          ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth(user ?? _dodo())),
          ChangeNotifierProvider<SubscriptionProvider>(create: (_) => _Subscription(premium)),
          ChangeNotifierProvider<FriendsProvider>(create: (_) => FriendsProvider()),
          ChangeNotifierProvider<ReferralProvider>(create: (_) => _Referral()),
          ChangeNotifierProvider<LocaleProvider>(create: (_) => _Locale()),
          ChangeNotifierProvider<OnboardingProvider>.value(value: onboarding ?? (_Onboarding()..debugSeed(const OnboardingStatus()))),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          builder: (context, navigator) => RepaintBoundary(key: key, child: navigator),
          theme: AppTheme.themeData,
          locale: const Locale('fr'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await settle();
  }

  /// Localizations, asset images, SVG pictures and WebP textures resolve
  /// asynchronously (real file IO): real time, not only test time.
  Future<void> settle({int rounds = 12}) async {
    await t.runAsync(() async {
      for (var i = 0; i < rounds; i++) {
        await t.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    });
    await t.pump();
    _report();
  }

  void _report() {
    final e = t.takeException();
    if (e != null) debugPrint('[revue] EXCEPTION: $e');
  }

  /// The largest vertical scroll extent on screen (0 = nothing scrolls).
  double extent() {
    var e = 0.0;
    for (final s in t.stateList<ScrollableState>(find.byType(Scrollable))) {
      final p = s.position;
      if (p.axis != Axis.vertical || !p.hasContentDimensions) continue;
      e = math.max(e, p.maxScrollExtent);
    }
    return e;
  }

  /// The empty space under the content of the main vertical list (the one
  /// with the tallest viewport), once everything fits: a lazy list
  /// overestimates its length until all its rows are laid out.
  double _slack() {
    var best = 0.0;
    var bestViewport = 0.0;
    for (final s in t.stateList<ScrollableState>(find.byType(Scrollable))) {
      final p = s.position;
      if (p.axis != Axis.vertical || !p.hasContentDimensions || !p.hasViewportDimension) continue;
      RenderViewportBase? viewport;
      void visit(RenderObject ro) {
        if (viewport != null) return;
        if (ro is RenderViewportBase) {
          viewport = ro;
        } else {
          ro.visitChildren(visit);
        }
      }

      s.context.findRenderObject()?.visitChildren(visit);
      final v = viewport;
      if (v == null) continue;
      var content = 0.0;
      v.visitChildren((c) {
        if (c is RenderSliver && c.geometry != null) content += c.geometry!.scrollExtent;
      });
      if (p.viewportDimension > bestViewport) {
        bestViewport = p.viewportDimension;
        best = p.viewportDimension - content;
      }
    }
    return best;
  }

  Future<void> _grow() async {
    for (var i = 0; i < 6; i++) {
      final e = extent();
      if (e < 0.5) return;
      final h = t.view.physicalSize.height / 3 + e;
      t.view.physicalSize = Size(_phoneW * 3, (h * 3).ceilToDouble());
      await settle(rounds: 5);
    }
  }

  /// Grows the phone until nothing scrolls, then gives back the empty space a
  /// lazy list had over-estimated: the whole page in one picture.
  Future<void> fullHeight() async {
    await _grow();
    final h = t.view.physicalSize.height / 3;
    final slack = _slack();
    if (h > _phoneH && slack > 0.5) {
      final target = math.max(_phoneH, h - slack);
      t.view.physicalSize = Size(_phoneW * 3, (target * 3).ceilToDouble());
      await settle(rounds: 5);
      await _grow();
    }
  }

  Future<void> write(int n, {bool full = false}) async {
    if (full) await fullHeight();
    final bare = _systemFontFallback();
    await t.pump();
    if (bare > 0) debugPrint('[revue] ${_file(n)}: $bare texte(s) sans police (dessinés en San Francisco)');
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = File('$_outDir/${_file(n)}');
      await out.writeAsBytes(bytes!.buffer.asUint8List());
      debugPrint('[revue] wrote ${out.path} (${image.width} × ${image.height})');
    });
  }
}

/// One screen: an iPhone 390 × 844 with its insets, fonts, the in-memory
/// server, then the tree is disposed and pending timers flushed.
Future<void> _shot(WidgetTester t, Future<void> Function(_H h) body) async {
  await t.runAsync(_loadFonts);
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'preview-token'});
  PackageInfo.setMockInitialValues(appName: 'Dart Rivals', packageName: 'app.dartrivals', version: '1.4.0', buildNumber: '1', buildSignature: '');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    (_) async => const StandardMessageCodec().encodeMessage([null]),
  );
  t.view.physicalSize = const Size(_phoneW * 3, _phoneH * 3);
  t.view.devicePixelRatio = 3;
  t.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(t.view.reset);
  await http.runWithClient(() async {
    final h = _H(t);
    await body(h);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
    h._report();
  }, _server);
}

// ─── Home (play_screen.dart's widgets, demo data) ────────────────────────────

Match _match(String id, String opponent, bool won, int my, int their, int elo, Duration ago) => Match(
      id: id,
      player1Id: _meId,
      player2Id: 'u-$opponent',
      player1Username: 'Dodo180',
      player2Username: opponent,
      player1Score: my,
      player2Score: their,
      winnerId: won ? _meId : 'u-$opponent',
      player1EloChange: elo,
      player2EloChange: -elo,
      createdAt: DateTime.now().subtract(ago),
      status: 'completed',
      matchType: 'ranked',
      seriesId: 's-$id',
      seriesPlayer1LegsWon: my,
      seriesPlayer2LegsWon: their,
    );

void _seedStores({Map<String, dynamic>? ranked}) {
  ChallengeStore.instance.debugSeed(_today(ranked: ranked), userId: _meId);
  ChallengeStore.instance.debugLoader = () async => _today(ranked: ranked);
  ChallengeApi.debugLeaderboard = (view) async => _leaderboard();
  LeagueStore.instance.debugSeed(LeagueSnapshot.fromJson(_leagueJson()));
  LeagueStore.instance.debugLoader = () async => LeagueSnapshot.fromJson(_leagueJson());
  GhostHomeStore.instance.debugSeed(digest: GhostDigest.fromJson(_digestJson()));
}

/// The home tab as play_screen.dart builds it (same widgets, in the same
/// order): Dodo180, or a new player on day 2 of the first 7 days.
class _Home extends StatelessWidget {
  final bool newPlayer;
  const _Home({this.newPlayer = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final p = context.watch<ProgressionProvider>();
    final xp = p.content?.xp;
    final onboarding = maybeWatchOnboarding(context);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlayerShowcaseCard(
          username: newPlayer ? 'Tom_D16' : 'Dodo180',
          rank: newPlayer ? 'unranked' : 'gold',
          cosmetics: newPlayer ? p.summary?.cosmetics : _myCosmetics,
          isPremium: !newPlayer,
          level: p.summary?.level,
          onEdit: () {},
          footer: HomeQuestStrip.fromProvider(context),
        ),
        const SizedBox(height: 12),
        if (newPlayer)
          CompetitiveCard(
            leading: CompetitiveCard.rankImage(RankUtils.getRankIcon('unranked')),
            label: '${l10n.competitiveModeTitle} · ${l10n.homePlacementLabel}',
            value: '0 / 4',
            progress: 0,
            caption: l10n.homePlacementLeft(4),
            actionLabel: l10n.play,
            onTap: () {},
            liveRanked: 3,
            liveTotal: 3,
          )
        else
          CompetitiveCard(
            leading: CompetitiveCard.rankImage(RankUtils.getRankIcon('gold')),
            label: '${l10n.competitiveModeTitle} · #17',
            value: formatXp(1409),
            progress: rankProgress('gold', 1409),
            caption: l10n.homeNextRankIn(RankTranslation.translate(l10n, nextRank('gold')), eloNeededForNextRank('gold', 1409)),
            actionLabel: l10n.play,
            actionXp: l10n.homeXpGain(xp!.ranked!),
            onTap: () {},
            liveRanked: 3,
            liveTotal: 3,
          ),
        const OnboardingHomeCard(topSpacing: 12),
        if (!(onboarding?.isActive ?? false))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HomeSectionTitle(l10n.questsToday),
                HomeTileRow(children: [
                  ChallengeTodayTile(xp: xp?.challenge),
                  LeagueTodayTile(xpForPosition: p.content?.leagueXpFor),
                ]),
              ],
            ),
          ),
        const SizedBox(height: 12),
        HomeOtherModes(xp: xp, friendLocked: newPlayer, onFriend: () {}, onLocal: () {}, onTraining: () {}),
        if (!newPlayer) const GhostHomeRows(),
        const SizedBox(height: 16),
        DsSectionHeader(title: l10n.recentMatches, actionLabel: l10n.viewAll, onAction: () {}),
        const SizedBox(height: 12),
        if (newPlayer)
          DsCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(Icons.history_rounded, size: 32, color: AppTheme.textTertiary),
                const SizedBox(height: 10),
                Text(l10n.noMatchesYet, textAlign: TextAlign.center, style: AppTheme.rowTitle),
                const SizedBox(height: 4),
                Text(l10n.playFirstGameToSeeHistory, textAlign: TextAlign.center, style: AppTheme.caption),
              ],
            ),
          )
        else
          RecentMatchesWidget(
            userId: _meId,
            matches: [
              _match('a', 'Kev_D20', true, 2, 1, 16, const Duration(hours: 2)),
              _match('b', 'LaFleche', false, 1, 2, -14, const Duration(days: 1)),
              _match('c', 'Juju180', true, 2, 0, 12, const Duration(days: 1, hours: 3)),
            ],
          ),
      ],
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: DsBrandHeader(actions: [
                DsIconButton(icon: Icons.chat_bubble_outline_rounded, onTap: () {}),
                DsIconButton(icon: Icons.settings_outlined, onTap: () {}),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: column,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: DsBottomBar(
        currentIndex: 2,
        onSelect: (_) {},
        centerLabel: l10n.play,
        items: [
          DsBottomBarItem(icon: Icons.bar_chart_rounded, label: l10n.stats),
          DsBottomBarItem(icon: Icons.emoji_events_outlined, label: l10n.tournament),
          DsBottomBarItem(icon: Icons.people_outline_rounded, label: l10n.friends),
          DsBottomBarItem(icon: Icons.trending_up_rounded, label: l10n.rankings),
        ],
      ),
    );
  }
}

/// The end of a won ranked series as GameScreen.buildEndScreen builds it:
/// MatchEndView, the XP panel in preCard, the accept / report panel.
class _MatchEnd extends StatelessWidget {
  final DateTime since;
  const _MatchEnd({required this.since});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final panel = Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: double.infinity, height: 52, child: ElevatedButton(onPressed: () {}, child: Text(dsSentence(l10n.acceptResult)))),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.flag_outlined, size: 16),
          label: Text(dsSentence(l10n.reportPlayer)),
        ),
      ),
    ]);
    return MatchEndView(
      didWin: true,
      title: l10n.victory,
      subtitle: l10n.provenLegend,
      scoreLine: '2 – 1',
      scoreCaption: l10n.bestOfN(3),
      panel: panel,
      // As GameScreen._endPreCard: the panel, then the pre-card's bottom gap.
      preCard: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: XpSummaryPanel(
          since: since,
          expectRefId: 's-1',
          loadLeague: (_) async => LeagueMatchDelta.fromJson({
            'weekKey': '2026-11-09',
            'league': _tier('cuivre'),
            'points': 50,
            'positionBefore': 9,
            'positionAfter': 6,
            'size': 20,
          }),
        ),
      ),
      statsMatchId: 'm-3',
    );
  }
}

/// AutoScoringService without a camera: the drill's capture state.
class _ScoringStub extends AutoScoringService {
  @override
  bool get isCapturing => true;
}

/// ChallengePlayScreen's game view (TrainingGameView with ChallengeStrategy,
/// the same arguments), after 4 visits of Cricket · 30. No camera in a test:
/// the camera zone is left empty.
class _ChallengePlay extends StatelessWidget {
  final ChallengeStrategy strategy;
  final AutoScoringService scoring;
  const _ChallengePlay(this.strategy, this.scoring);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppTheme.gameBackground,
      body: TrainingGameView(
        scoringService: scoring,
        strategy: strategy,
        pending: const [],
        title: '${strategy.format.short.resolve(context)} · ${l10n.challengeRankedBadge}',
        onConfirm: () {},
        localCameraPreview: null,
        onBack: () {},
        onEditSlot: (_, _) {},
        onRemoveLast: () {},
        onToggleAi: null,
        aiEnabled: true,
      ),
    );
  }
}

// ─── PNG size (IHDR) ─────────────────────────────────────────────────────────

(int, int)? _pngSize(File f) {
  if (!f.existsSync()) return null;
  final b = f.openSync()..setPositionSync(16);
  final bytes = b.readSync(8);
  b.closeSync();
  final d = ByteData.sublistView(Uint8List.fromList(bytes));
  return (d.getUint32(0), d.getUint32(4));
}

void main() {
  setUpAll(() {
    Directory(_outDir).createSync(recursive: true);
    final cache = Directory.systemTemp.createTempSync('revue-preview-');
    ProgressionAssetCache.debugDirectory = cache;
    _content = ProgressionContent.fromJson(_contentJson(cache));
  });

  setUp(() => _seedStores());

  tearDownAll(() {
    if (_unknownRoutes.isNotEmpty) debugPrint('[revue] routes sans réponse : ${_unknownRoutes.toList()..sort()}');
  });

  test('copies of the up-to-date PNGs', () {
    for (final e in _copies.entries) {
      File('$_captures/${e.value}').copySync('$_outDir/${_file(e.key)}');
    }
  }, skip: !_enabled);

  testWidgets('01 accueil', (t) => _shot(t, (h) async {
        await h.open(const _Home());
        await h.write(1);
      }), skip: !_enabled);

  testWidgets('02 accueil page entière', (t) => _shot(t, (h) async {
        await h.open(const _Home());
        await h.write(2, full: true);
      }), skip: !_enabled);

  testWidgets('03 profil', (t) => _shot(t, (h) async {
        await h.open(const PlayerStatsScreen(userId: _meId, username: 'Dodo180'));
        await h.write(3, full: true);
      }), skip: !_enabled);

  testWidgets('04 niveau gagné', (t) => _shot(t, (h) async {
        await h.open(const LevelUpScreen(level: 23, itemIds: ['flight.cuivre']));
        await h.write(4, full: true);
      }), skip: !_enabled);

  testWidgets('05 chemin des niveaux', (t) => _shot(t, (h) async {
        await h.open(const LevelsPathScreen());
        await h.write(5, full: true);
      }), skip: !_enabled);

  testWidgets('06 progression', (t) => _shot(t, (h) async {
        await h.open(const ProgressionScreen());
        await h.write(6, full: true);
      }), skip: !_enabled);

  testWidgets('07 XP de fin de match', (t) => _shot(t, (h) async {
        await h.open(_MatchEnd(since: DateTime.now().subtract(const Duration(minutes: 14))));
        await h.settle(rounds: 20);
        await h.write(7, full: true);
      }), skip: !_enabled);

  testWidgets('08 casier avatars', (t) => _shot(t, (h) async {
        await h.open(const LockerScreen());
        await h.write(8, full: true);
      }), skip: !_enabled);

  testWidgets('09 casier fiche', (t) => _shot(t, (h) async {
        await h.open(const LockerScreen());
        await t.tap(find.byKey(const Key('locker-locked-avatar.flechettes-croisees')));
        await h.settle();
        await h.write(9);
      }), skip: !_enabled);

  testWidgets('10 casier lettres', (t) => _shot(t, (h) async {
        await h.open(const LockerScreen());
        await t.tap(find.byKey(const Key('locker-owned-avatar.monogramme-acier')));
        await h.settle();
        await h.write(10);
      }), skip: !_enabled);

  testWidgets('11 casier badges', (t) => _shot(t, (h) async {
        await h.open(const LockerScreen(initialTab: ItemType.badge));
        await h.write(11, full: true);
      }), skip: !_enabled);

  testWidgets('15 défi classement', (t) => _shot(t, (h) async {
        final today = _today(ranked: _myAttempt);
        await h.open(ChallengeLeaderboardScreen(today: today, boards: {ChallengeView.rank: _leaderboard()}));
        await h.write(15, full: true);
      }), skip: !_enabled);

  testWidgets('16 défi jeu', (t) => _shot(t, (h) async {
        final format = ChallengeFormat.fromJson(_format('cricket-30'))!;
        final strategy = ChallengeStrategy(format);
        const s = ScoreMultiplier.single, d = ScoreMultiplier.double, tr = ScoreMultiplier.triple;
        for (final visit in const [
          [TrainingDart(20, tr), TrainingDart(20, s), TrainingDart(5, s)],
          [TrainingDart(19, tr), TrainingDart(19, s), TrainingDart(7, s)],
          [TrainingDart(18, s), TrainingDart(18, d), TrainingDart(1, s)],
          [TrainingDart(17, tr), TrainingDart(17, s), TrainingDart(3, s)],
        ]) {
          strategy.submitVisit(visit);
        }
        await h.open(_ChallengePlay(strategy, _ScoringStub()));
        await h.write(16);
      }), skip: !_enabled);

  testWidgets('17 défi résultat', (t) => _shot(t, (h) async {
        await h.open(ChallengeResultScreen(result: ChallengeResult.fromJson(_resultJson())!));
        await h.write(17, full: true);
      }), skip: !_enabled);

  testWidgets('18 défi carte à partager', (t) => _shot(t, (h) async {
        final result = ChallengeResult.fromJson(_resultJson())!;
        await h.open(ChallengeResultScreen(result: result));
        unawaited(ChallengeStorySheet.show(t.element(find.byType(ChallengeResultScreen)), result));
        await h.settle();
        await h.write(18);
      }), skip: !_enabled);

  testWidgets('19 défi podium', (t) => _shot(t, (h) async {
        await h.open(const ChallengePodiumScreen(date: '2026-11-08'));
        await h.write(19, full: true);
      }), skip: !_enabled);

  testWidgets('20 défi session', (t) => _shot(t, (h) async {
        await h.open(const ChallengeSessionScreen(crownId: 'c1'));
        await h.write(20, full: true);
      }), skip: !_enabled);

  testWidgets('21 ligue', (t) => _shot(t, (h) async {
        await h.open(const LeagueScreen());
        await h.write(21, full: true);
      }), skip: !_enabled);

  testWidgets('22 ligue résultat', (t) => _shot(t, (h) async {
        await h.open(LeagueResultScreen(result: LeagueResult.fromJson(_leagueResultJson())!));
        await h.write(22, full: true);
      }), skip: !_enabled);

  testWidgets('23 succès', (t) => _shot(t, (h) async {
        await h.open(AchievementsScreen(load: () async => AchievementsSnapshot.fromJson(_achievementsJson())));
        await h.write(23, full: true);
      }), skip: !_enabled);

  testWidgets('24 fiche succès', (t) => _shot(t, (h) async {
        final json = _bullsDetailJson();
        await h.open(AchievementDetailScreen(
          achievement: Achievement.fromJson(json)!,
          load: (_) async => AchievementDetail.fromJson(json),
        ));
        await h.write(24, full: true);
      }), skip: !_enabled);

  testWidgets('25 succès débloqué', (t) => _shot(t, (h) async {
        await h.open(const _Home());
        unawaited(AchievementUnlockSheet.showIfPending(t.element(find.byType(_Home))));
        await h.settle();
        await h.write(25);
      }), skip: !_enabled);

  testWidgets('30 match fantôme', (t) => _shot(t, (h) async {
        await h.open(GhostMatchScreen(initial: GhostMatchState.fromJson(_ghostMatchJson())!));
        // The camera cannot start in a test: the player's turn shows an
        // empty camera zone. Three darts are handed to the screen as the AI
        // would (T20, S20, S5 = 85), the visit is confirmed and sent to the
        // server, whose answer replays the ghost's visit: 2 of its 3 darts.
        final screen = t.state(find.byType(GhostMatchScreen)) as dynamic;
        for (final (i, score, segment, ring, radius, angle) in const [
          (0, 60, 20, 'triple', 0.61, 4.71),
          (1, 20, 20, 'outer_single', 0.8, 4.68),
          (2, 5, 5, 'outer_single', 0.75, 4.3),
        ]) {
          screen.onAiDartDetected(i, DartScore(score: score, segment: segment, ring: ring, radius: radius, angle: angle));
          await t.pump();
        }
        await t.tap(find.text('Confirmer'));
        await t.pump();
        await t.pump(const Duration(milliseconds: 50));
        await h.settle(rounds: 14);
        await h.write(30);
      }), skip: !_enabled);

  testWidgets('31 fantôme résumé', (t) => _shot(t, (h) async {
        await h.open(GhostDigestScreen(initial: GhostDigest.fromJson(_digestJson())));
        await h.write(31, full: true);
      }), skip: !_enabled);

  testWidgets('32 réglages fantôme', (t) => _shot(t, (h) async {
        await h.open(const SettingsScreen());
        await h.write(32, full: true);
      }), skip: !_enabled);

  testWidgets('33 accueil nouveau joueur', (t) => _shot(t, (h) async {
        await h.open(
          const _Home(newPlayer: true),
          progression: _tomProgression(level: 3),
          user: User(id: 'u-tom16', username: 'Tom_D16', email: 'tom@x.fr', elo: 0, rank: 'unranked'),
          premium: false,
          onboarding: _Onboarding()..debugSeed(_day2()),
        );
        await h.write(33, full: true);
      }), skip: !_enabled);

  testWidgets('34 parcours 7 jours', (t) => _shot(t, (h) async {
        await h.open(
          const OnboardingJourneyScreen(),
          progression: _tomProgression(level: 3),
          user: User(id: 'u-tom16', username: 'Tom_D16', email: 'tom@x.fr', elo: 0, rank: 'unranked'),
          premium: false,
          onboarding: _Onboarding()..debugSeed(_day2()),
        );
        await h.write(34, full: true);
      }), skip: !_enabled);

  testWidgets('35 bilan 7 jours', (t) => _shot(t, (h) async {
        await h.open(
          const OnboardingBilanScreen(),
          progression: _tomProgression(level: 9, frame: 'frame.debutant', title: 'title.nouvelle-recrue'),
          user: User(id: 'u-tom16', username: 'Tom_D16', email: 'tom@x.fr', elo: 1004, rank: 'silver'),
          premium: false,
          onboarding: _Onboarding()..debugSeed(_day7()),
        );
        await h.write(35, full: true);
      }), skip: !_enabled);

  // Last: the manifest of the 39 numbers, from the files actually there.
  test('manifest', () {
    final entries = <Map<String, dynamic>>[];
    for (final e in _list.entries) {
      final n = e.key;
      final (titre, fichier, note) = e.value;
      final size = _pngSize(File('$_outDir/$fichier'));
      final copy = _copies[n];
      entries.add({
        'n': n,
        'titre': titre,
        'fichier': fichier,
        'largeur': size?.$1,
        'hauteur': size?.$2,
        'source': size == null ? 'absent' : (copy != null ? 'copie de $copy' : 'nouveau'),
        'note': size == null ? 'Pas rendu : voir le rapport.' : note,
      });
    }
    File('$_outDir/manifest.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(entries)}\n');
    debugPrint('[revue] manifest: ${entries.where((e) => e['source'] != 'absent').length} / ${entries.length} PNG');
  }, skip: !_enabled);
}

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/progression.dart';
import 'package:mobile/models/user.dart';

void main() {
  group('ProgressionContent', () {
    final json = {
      'version': 'abc123',
      'curve': {'base': 200, 'perLevel': 60},
      'metals': {
        'acier': ['#E2E8F0', '#7B8798', '#CBD5E1'],
        'broken': ['#zzz'],
      },
      'items': [
        {
          'id': 'avatar.monogramme-acier',
          'type': 'avatar',
          'name': {'fr': 'Monogramme Acier', 'en': 'Steel Monogram'},
          'source': {'kind': 'level', 'level': 2, 'label': {'fr': 'niveau 2', 'en': 'level 2'}},
          'render': {'kind': 'monogram', 'metal': 'acier', 'shape': 'round'},
          'asset': null,
        },
        {
          'id': 'frame.damas',
          'type': 'frame',
          'name': {'fr': 'Damas', 'en': 'Damascus'},
          'source': {'kind': 'level', 'level': 35, 'label': {'fr': 'niveau 35', 'en': 'level 35'}},
          'render': {'kind': 'frame', 'metal': 'damas'},
          'asset': {'url': '/progression/items/frame.damas.svg?v=1', 'format': 'svg', 'hash': '1'},
        },
        // A type this app version does not know: hidden, never a crash.
        {'id': 'emote.wave', 'type': 'emote', 'name': {'fr': 'x', 'en': 'x'}},
        'garbage',
      ],
      'levels': [
        {'level': 2, 'itemIds': ['avatar.monogramme-acier'], 'premiumItemIds': []},
      ],
    };

    test('parses known items and drops unknown types', () {
      final c = ProgressionContent.fromJson(json);
      expect(c.version, 'abc123');
      expect(c.items.keys, ['avatar.monogramme-acier', 'frame.damas']);
      expect(c.item('avatar.monogramme-acier')!.isMonogram, isTrue);
      expect(c.item('frame.damas')!.asset!.isSvg, isTrue);
      expect(c.item('emote.wave'), isNull);
      expect(c.metals.keys, ['acier']);
      expect(c.levels[2]!.itemIds, ['avatar.monogramme-acier']);
      expect(c.item('avatar.monogramme-acier')!.name.of(const Locale('fr')), 'Monogramme Acier');
      expect(c.item('avatar.monogramme-acier')!.name.of(const Locale('en')), 'Steel Monogram');
    });

    test('mirrors the server XP curve', () {
      const curve = XpCurve();
      expect(curve.xpToNext(1), 260);
      expect(curve.xpToNext(14), 1040);
      expect(curve.xpForLevel(1), 0);
      expect(curve.xpForLevel(10), 4500);
      expect(curve.xpForLevel(50), 83300);
    });
  });

  test('PublicCosmetics is optional and defensive', () {
    expect(PublicCosmetics.fromJson(null), isNull);
    expect(PublicCosmetics.fromJson('x'), isNull);
    final c = PublicCosmetics.fromJson({
      'level': 14,
      'avatar': 'avatar.flechette',
      'monogram': 'DO',
      'frame': null,
      'title': 'title.finisseur',
      'badges': [
        {'id': 'u1', 'badgeId': 'badge.machine-a-180', 'tier': 'silver', 'date': null},
        {'nope': true},
      ],
    })!;
    expect(c.level, 14);
    expect(c.frame, isNull);
    expect(c.badges.single.tier, 'silver');
  });

  test('User.fromJson reads the additive cosmetics field', () {
    final old = User.fromJson({'id': 'u', 'username': 'Dodo180', 'elo': 1601, 'rank': 'platinum'});
    expect(old.cosmetics, isNull);
    final fresh = User.fromJson({
      'id': 'u',
      'username': 'Dodo180',
      'cosmetics': {'level': 3, 'monogram': 'DO'},
    });
    expect(fresh.cosmetics!.level, 3);
  });

  test('summary, quests and XP feed parse with defaults', () {
    final s = ProgressionSummary.fromJson({'level': 14, 'xpIntoLevel': 812, 'xpToNext': 1040, 'levelSeen': 13});
    expect(s.progress, closeTo(0.78, 0.01));
    expect(s.equipment.avatar, isNull);
    final q = QuestsSnapshot.fromJson({
      'daily': {
        'periodKey': '2026-11-08',
        'rerollAvailable': true,
        'quests': [
          {'id': 'a', 'questId': 'q016', 'text': {'fr': 'Marque une volée à 60+', 'en': 'Score a 60+ visit'}, 'progress': 1, 'threshold': 1, 'xp': 40, 'status': 'completed'},
          {'id': 'b', 'questId': 'q005', 'text': {'fr': 'Lance 90 fléchettes', 'en': 'Throw 90 darts'}, 'progress': 30, 'threshold': 90, 'xp': 40},
          {'broken': 1},
        ],
      },
    });
    expect(q.daily.quests, hasLength(2));
    expect(q.daily.done, 1);
    expect(q.daily.xpLeft, 40);
    expect(q.weekly.quests, isEmpty);
    final feed = XpFeed.fromJson({
      'entries': [
        {'source': 'ranked_series', 'refId': 's1', 'amount': 60, 'label': {'fr': 'Série classée', 'en': 'Ranked series'}},
      ],
      'totalAmount': 60,
      'levelBefore': 14,
      'levelAfter': 15,
      'levelUps': [{'level': 15, 'itemIds': ['frame.laiton'], 'premiumItemIds': []}],
    });
    expect(feed.levelUps.single.itemIds, ['frame.laiton']);
  });

  test('EquipRequest only sends the slots that are set (null resets)', () {
    expect(EquipRequest(frame: 'frame.acier').body, {'frame': 'frame.acier'});
    expect(EquipRequest(title: null).body, {'title': null});
    expect(EquipRequest(monogram: const MonogramChoice(kind: 'double', value: 'D16')).body, {
      'monogram': {'kind': 'double', 'value': 'D16'},
    });
    expect(EquipRequest.slot(ItemType.flight, 'flight.classique').body, {'flight': 'flight.classique'});
  });
}

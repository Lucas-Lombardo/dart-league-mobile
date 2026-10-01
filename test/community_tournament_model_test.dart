import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/tournament.dart';

void main() {
  test('a community tournament carries its organiser and format', () {
    final t = Tournament.fromJson({
      'id': 't1',
      'name': 'Soirée du jeudi',
      'scheduledDate': '2026-10-01T19:00:00.000Z',
      'status': 'registration_open',
      'maxParticipants': 16,
      'currentParticipants': 5,
      'winnerEloReward': 0,
      'organizerId': 'u-org',
      'organizerUsername': 'Dodo180',
      'bestOf': 5,
    });

    expect(t.isCommunity, isTrue);
    expect(t.isOfficial, isFalse);
    expect(t.organizerUsername, 'Dodo180');
    expect(t.bestOf, 5);
    expect(t.winnerEloReward, 0);
    expect(t.isOrganizedBy('u-org'), isTrue);
    expect(t.isOrganizedBy('someone'), isFalse);
    expect(t.isOrganizedBy(null), isFalse);
  });

  test('an official tournament (older backend payload) keeps BO3', () {
    final t = Tournament.fromJson({
      'id': 't2',
      'name': 'Tournoi du Samedi',
      'scheduledDate': '2026-10-03T16:00:00.000Z',
      'status': 'registration_open',
      'maxParticipants': 32,
      'currentParticipants': 14,
      'winnerEloReward': 500,
    });

    expect(t.isOfficial, isTrue);
    expect(t.organizerId, isNull);
    expect(t.bestOf, 3);
  });
}

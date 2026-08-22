import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations_en.dart';
import 'package:mobile/l10n/app_localizations_fr.dart';
import 'package:mobile/models/season.dart';
import 'package:mobile/providers/season_provider.dart';
import 'package:mobile/utils/season_format.dart';

/// The countdown is recomputed from `endAt − now` on every tick, so it can
/// never drift, and it is rendered in days/hours, hours/minutes or minutes.
void main() {
  group('formatSeasonCountdown', () {
    final fr = AppLocalizationsFr();
    final en = AppLocalizationsEn();

    test('days and hours', () {
      expect(formatSeasonCountdown(fr, const Duration(days: 9, hours: 14, minutes: 30)), '9 j 14 h');
      expect(formatSeasonCountdown(en, const Duration(days: 9, hours: 14, minutes: 30)), '9 d 14 h');
    });

    test('hours and minutes under a day', () {
      expect(formatSeasonCountdown(fr, const Duration(hours: 3, minutes: 5)), '3 h 05 min');
      expect(formatSeasonCountdown(en, const Duration(hours: 23, minutes: 59)), '23 h 59 min');
    });

    test('minutes under an hour, zero included', () {
      expect(formatSeasonCountdown(fr, const Duration(minutes: 12)), '12 min');
      expect(formatSeasonCountdown(fr, Duration.zero), '0 min');
    });

    test('no end date', () {
      expect(formatSeasonCountdown(fr, null), 'fin à annoncer');
      expect(formatSeasonCountdown(en, null), 'end to be announced');
    });
  });

  group('SeasonProvider countdown', () {
    test('recomputes endAt − now on each tick and stops at zero', () {
      fakeAsync((async) {
        final provider = SeasonProvider();
        var now = DateTime.utc(2026, 8, 22, 9, 45);
        provider.clock = () => now;
        provider.debugSetCurrent(
          CurrentSeason(
            season: Season.fromJson({
              'number': 1,
              'status': 'active',
              'startedAt': '2026-08-01T00:00:00.000Z',
              'endAt': '2026-08-31T21:59:00.000Z',
            }),
          ),
        );

        expect(provider.timeLeft, const Duration(days: 9, hours: 12, minutes: 14));

        var notified = 0;
        provider.addListener(() => notified++);

        // One minute passes: the periodic ticker fires and re-reads the clock.
        now = now.add(const Duration(minutes: 1));
        async.elapse(const Duration(minutes: 1));
        expect(notified, 1);
        expect(provider.timeLeft, const Duration(days: 9, hours: 12, minutes: 13));

        // Past the end, the countdown clamps to zero rather than going negative.
        now = DateTime.utc(2026, 9, 1);
        async.elapse(const Duration(minutes: 1));
        expect(provider.timeLeft, Duration.zero);

        provider.dispose();
      });
    });

    test('has no countdown and no ticker without an end date', () {
      fakeAsync((async) {
        final provider = SeasonProvider();
        provider.clock = () => DateTime.utc(2026, 8, 22);
        provider.debugSetCurrent(
          CurrentSeason(season: Season.fromJson({'number': 0, 'status': 'active'})),
        );
        var notified = 0;
        provider.addListener(() => notified++);
        expect(provider.timeLeft, isNull);
        async.elapse(const Duration(minutes: 5));
        expect(notified, 0);
        provider.dispose();
      });
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/heavy_capability_probe.dart';

/// The verdict is the ONLY thing that decides heavy-vs-v13 on Android, and it
/// is persisted, so its two rules — the budget and how long a verdict holds —
/// are pinned here. The measurement itself needs the native plugin and is
/// exercised on device.
void main() {
  final t0 = DateTime(2026, 9, 6, 12);

  group('HeavyProbeVerdict.fromSamples', () {
    test('a flagship-class median clears the budget', () {
      final v = HeavyProbeVerdict.fromSamples([150, 160, 170],
          appVersion: '1.0.0+1', now: t0);
      expect(v.capable, isTrue);
      expect(v.medianMs, 160);
    });

    test('the Redmi 13C number fails it', () {
      // 826 ms measured 2026-08-28 on the Mali-G52 GPU.
      final v =
          HeavyProbeVerdict.fromSamples([826], appVersion: '1.0.0+1', now: t0);
      expect(v.capable, isFalse);
      expect(v.medianMs, 826);
    });

    test('the budget is inclusive and the decision is the median', () {
      expect(
        HeavyProbeVerdict.fromSamples([HeavyProbeVerdict.heavyBudgetMs],
                appVersion: 'v', now: t0)
            .capable,
        isTrue,
      );
      // One slow outlier does not sink a phone that is otherwise fine.
      expect(
        HeavyProbeVerdict.fromSamples([200, 900, 210], appVersion: 'v', now: t0)
            .capable,
        isTrue,
      );
      expect(
        HeavyProbeVerdict.fromSamples([200, 900, 910], appVersion: 'v', now: t0)
            .capable,
        isFalse,
      );
    });

    test('nothing measured means not capable, never capable by default', () {
      final v = HeavyProbeVerdict.fromSamples([], appVersion: 'v', now: t0);
      expect(v.capable, isFalse);
      expect(v.medianMs, isNull);
    });

    test('early exit fires on a single sample at twice the budget', () {
      expect(HeavyProbeVerdict.earlyExitMs, 2 * HeavyProbeVerdict.heavyBudgetMs);
    });
  });

  group('HeavyProbeVerdict.isValidFor', () {
    test('a capable verdict holds for its app version, however old', () {
      final v = HeavyProbeVerdict.fromSamples([100], appVersion: '1.2.50+3', now: t0);
      expect(v.isValidFor('1.2.50+3', now: t0.add(const Duration(days: 400))),
          isTrue);
    });

    test('any verdict dies with the app version it was measured on', () {
      final v = HeavyProbeVerdict.fromSamples([100], appVersion: '1.2.50+3', now: t0);
      expect(v.isValidFor('1.2.51+4', now: t0), isFalse);
    });

    test('a not-capable verdict gets re-measured after a week', () {
      // A capable phone that was hot or busy on first launch must not be
      // stuck on v13 until the next release.
      final v = HeavyProbeVerdict.fromSamples([826], appVersion: 'v', now: t0);
      expect(v.isValidFor('v', now: t0.add(const Duration(days: 6))), isTrue);
      expect(v.isValidFor('v', now: t0.add(const Duration(days: 8))), isFalse);
    });

    test('a failure that measured nothing is retried the next day', () {
      // The first device run hit a native bug on the reference photo
      // (landscape overrun): a bug, not a number, and it would have parked
      // every phone on v13 for a week.
      final v = HeavyProbeVerdict.notCapable('v', reason: 'boom', now: t0);
      expect(v.capable, isFalse);
      expect(v.medianMs, isNull);
      expect(v.isValidFor('v', now: t0.add(const Duration(hours: 23))), isTrue);
      expect(v.isValidFor('v', now: t0.add(const Duration(hours: 25))), isFalse);
    });

    test('a wedge is held as long as a slow measurement', () {
      // Re-wedging the native thread at every launch would cost every
      // match that follows.
      final v = HeavyProbeVerdict.notCapable('v',
          reason: 'timeout', wedged: true, now: t0);
      expect(v.isValidFor('v', now: t0.add(const Duration(days: 6))), isTrue);
      expect(v.isValidFor('v', now: t0.add(const Duration(days: 8))), isFalse);
    });
  });

  group('persistence', () {
    test('survives an encode/decode round trip', () {
      final v = HeavyProbeVerdict.fromSamples([150, 160, 170],
          appVersion: '1.2.50+3', now: t0);
      final back = HeavyProbeVerdict.decode(v.encode());
      expect(back, isNotNull);
      expect(back!.capable, v.capable);
      expect(back.medianMs, v.medianMs);
      expect(back.appVersion, v.appVersion);
      expect(back.at, v.at);
      expect(back.reason, v.reason);
      expect(back.validFor, isNull);
      final slow = HeavyProbeVerdict.decode(
          HeavyProbeVerdict.fromSamples([826], appVersion: 'v', now: t0).encode());
      expect(slow!.validFor, HeavyProbeVerdict.retryAfter);
    });

    test('a value this build did not write is treated as no verdict', () {
      // The safe reading of junk is "measure again", not "capable".
      expect(HeavyProbeVerdict.decode(null), isNull);
      expect(HeavyProbeVerdict.decode(''), isNull);
      expect(HeavyProbeVerdict.decode('not json'), isNull);
      expect(HeavyProbeVerdict.decode('{"capable":"yes"}'), isNull);
      expect(HeavyProbeVerdict.decode('{"capable":true}'), isNull);
      // A record from before validFor existed is re-measured, not trusted.
      expect(
        HeavyProbeVerdict.decode(
            '{"capable":false,"appVersion":"v","at":"2026-09-06T16:32:59"}'),
        isNull,
      );
    });
  });
}

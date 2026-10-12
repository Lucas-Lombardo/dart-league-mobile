import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/services/api_service.dart';

void main() {
  setUp(() {
    ApiService.resetAuthFailure();
    ApiService.markSessionValid();
    ApiService.isMatchLive = null;
  });

  tearDown(() {
    ApiService.resetAuthFailure();
    ApiService.isMatchLive = null;
  });

  test('signs out at once when no match is being played', () {
    var calls = 0;
    ApiService.onAuthFailure = () => calls++;
    ApiService.isMatchLive = () => false;

    ApiService.handleAuthFailure();
    ApiService.handleAuthFailure();

    expect(calls, 1, reason: 'one sign-out per lost session');
  });

  test('holds the sign-out until the live match is over', () {
    fakeAsync((async) {
      var calls = 0;
      var live = true;
      ApiService.onAuthFailure = () => calls++;
      ApiService.isMatchLive = () => live;

      ApiService.handleAuthFailure();
      async.elapse(const Duration(minutes: 2));
      expect(calls, 0, reason: 'the player keeps playing on the socket');

      live = false;
      async.elapse(const Duration(seconds: 6));
      expect(calls, 1);

      // A later sign-in clears the verdict: the next loss signs out again.
      ApiService.markSessionValid();
      ApiService.handleAuthFailure();
      expect(calls, 2);
    });
  });
}

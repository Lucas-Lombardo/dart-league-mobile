import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/services/socket_service.dart';

/// Regression cover for the stale-JWT reconnect loop (2026-07-25 tournament
/// outage): socket_io_client caches the Socket per URL, so a token baked into
/// the options at construction outlives every refresh — after the 15-minute
/// access-token expiry the socket reconnected with the same dead JWT forever
/// ("Connexion perdue — reconnexion…"). The fix resolves the token inside an
/// auth *callback* invoked by socket.io on every connection attempt.
String _jwt({required int expSecondsFromNow}) {
  String enc(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(json.encode(m))).replaceAll('=', '');
  final exp =
      DateTime.now().add(Duration(seconds: expSecondsFromNow)).millisecondsSinceEpoch ~/
          1000;
  return '${enc({'alg': 'HS256', 'typ': 'JWT'})}.${enc({'sub': 'u1', 'exp': exp})}.sig';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('local token expiry check', () {
    test('a token expired an hour ago is flagged', () {
      expect(
        SocketService.debugTokenLooksExpired(_jwt(expSecondsFromNow: -3600)),
        isTrue,
      );
    });

    test('a token expiring within the 30s skew is flagged early', () {
      expect(
        SocketService.debugTokenLooksExpired(_jwt(expSecondsFromNow: 10)),
        isTrue,
      );
    });

    test('a token with plenty of life left is not flagged', () {
      expect(
        SocketService.debugTokenLooksExpired(_jwt(expSecondsFromNow: 600)),
        isFalse,
      );
    });

    test('unparseable tokens are treated as valid — server stays authority',
        () {
      expect(SocketService.debugTokenLooksExpired('garbage'), isFalse);
      expect(SocketService.debugTokenLooksExpired('a.b'), isFalse);
      expect(SocketService.debugTokenLooksExpired('a.!!!.c'), isFalse);
    });

    test('a token without exp is treated as valid', () {
      String enc(Map<String, dynamic> m) =>
          base64Url.encode(utf8.encode(json.encode(m))).replaceAll('=', '');
      final noExp = '${enc({'alg': 'none'})}.${enc({'sub': 'u1'})}.sig';
      expect(SocketService.debugTokenLooksExpired(noExp), isFalse);
    });
  });

  group('auth payload callback', () {
    test('always completes and delivers a token map, even without storage',
        () async {
      // In the test environment flutter_secure_storage has no platform
      // channel and throws; the payload must swallow that and still hand
      // socket.io a CONNECT payload — otherwise the connection attempt
      // silently never happens.
      dynamic delivered;
      await SocketService.debugAuthPayload((data) => delivered = data);
      expect(delivered, isA<Map>());
      expect((delivered as Map).containsKey('token'), isTrue);
    });
  });
}

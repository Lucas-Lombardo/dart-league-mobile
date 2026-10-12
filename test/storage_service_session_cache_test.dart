import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/utils/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    StorageService.resetSessionCache();
    FlutterSecureStorage.setMockInitialValues({
      'jwt_token': 'stored-access',
      'refresh_token': 'stored-refresh',
    });
  });

  test('reads the keychain once, then serves the session from memory', () async {
    expect(await StorageService.getToken(), 'stored-access');
    expect(await StorageService.getRefreshToken(), 'stored-refresh');

    await StorageService.saveToken('fresh-access');
    await StorageService.saveRefreshToken('fresh-refresh');

    expect(await StorageService.getToken(), 'fresh-access');
    expect(await StorageService.getRefreshToken(), 'fresh-refresh');
    // ...and the keychain copy followed.
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'jwt_token'), 'fresh-access');
    expect(await storage.read(key: 'refresh_token'), 'fresh-refresh');
    expect(StorageService.hasPendingPersist, isFalse);
  });

  test('a deleted token stays deleted in memory and in the keychain', () async {
    await StorageService.deleteToken();
    await StorageService.deleteRefreshToken();
    expect(await StorageService.getToken(), isNull);
    expect(await StorageService.getRefreshToken(), isNull);
    const storage = FlutterSecureStorage();
    expect(await storage.read(key: 'jwt_token'), isNull);
  });

  test('remembers the last sign-in e-mail', () async {
    expect(await StorageService.getRememberedEmail(), isNull);
    await StorageService.saveRememberedEmail(' Greg@x.com ');
    expect(await StorageService.getRememberedEmail(), 'Greg@x.com');
  });
}

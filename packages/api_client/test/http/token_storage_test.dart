import 'package:api_client/api_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late _MockSecureStorage secureStorage;

  setUp(() {
    secureStorage = _MockSecureStorage();
  });

  test(
    'repairs an Android store restored without its encryption key',
    () async {
      var readAttempts = 0;
      when(() => secureStorage.read(key: 'auth_device_id')).thenAnswer((
        _,
      ) async {
        readAttempts++;
        if (readAttempts == 1) {
          throw PlatformException(code: 'InvalidKeyException');
        }
        return null;
      });
      when(() => secureStorage.deleteAll()).thenAnswer((_) async {});

      final storage = SecureTokenStorage(secureStorage, true);

      expect(await storage.readDeviceId(), isNull);
      expect(readAttempts, 2);
      verify(() => secureStorage.deleteAll()).called(1);
    },
  );

  test('retries the complete token write after repairing storage', () async {
    var writeAttempts = 0;
    when(
      () => secureStorage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {
      writeAttempts++;
      if (writeAttempts == 1) {
        throw PlatformException(code: 'BadPaddingException');
      }
    });
    when(
      () => secureStorage.read(key: 'auth_access_token'),
    ).thenAnswer((_) async => 'access-token');
    when(
      () => secureStorage.read(key: 'auth_refresh_token'),
    ).thenAnswer((_) async => 'refresh-token');
    when(() => secureStorage.deleteAll()).thenAnswer((_) async {});

    final storage = SecureTokenStorage(secureStorage, true);
    await storage.writeTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
    );

    expect(writeAttempts, 3);
    verify(() => secureStorage.deleteAll()).called(1);
  });

  test(
    'does not erase storage on platforms where recovery is disabled',
    () async {
      when(
        () => secureStorage.read(key: 'auth_device_id'),
      ).thenThrow(PlatformException(code: 'KeychainUnavailable'));

      final storage = SecureTokenStorage(secureStorage, false);

      await expectLater(
        storage.readDeviceId(),
        throwsA(isA<PlatformException>()),
      );
      verifyNever(() => secureStorage.deleteAll());
    },
  );

  test(
    'persists and reuses a refresh attempt without storing the bearer',
    () async {
      final values = <String, String>{};
      when(() => secureStorage.read(key: any(named: 'key'))).thenAnswer(
        (invocation) async =>
            values[invocation.namedArguments[const Symbol('key')] as String],
      );
      when(
        () => secureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((invocation) async {
        values[invocation.namedArguments[const Symbol('key')] as String] =
            invocation.namedArguments[const Symbol('value')] as String;
      });
      when(() => secureStorage.delete(key: any(named: 'key'))).thenAnswer((
        invocation,
      ) async {
        values.remove(invocation.namedArguments[const Symbol('key')] as String);
      });

      final firstProcess = SecureTokenStorage(secureStorage, false);
      final first = await firstProcess.readOrCreate('secret-refresh-bearer');
      final afterRestart = SecureTokenStorage(secureStorage, false);
      final recovered = await afterRestart.readOrCreate(
        'secret-refresh-bearer',
      );

      expect(recovered, first);
      expect(isCanonicalRefreshAttemptId(first), isTrue);
      expect(values.values.single, isNot(contains('secret-refresh-bearer')));

      await afterRestart.clearIfMatches(
        refreshToken: 'secret-refresh-bearer',
        attemptId: generateRefreshAttemptId(),
      );
      expect(values, isNotEmpty);
      await afterRestart.clearIfMatches(
        refreshToken: 'secret-refresh-bearer',
        attemptId: first,
      );
      expect(values, isEmpty);
    },
  );
}

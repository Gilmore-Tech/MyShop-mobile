import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

class _MemoryInstallEpochStore implements InstallEpochStore {
  String? epoch;

  @override
  Future<String?> readInstallEpoch() async => epoch;

  @override
  Future<void> writeInstallEpoch(String epoch) async {
    this.epoch = epoch;
  }
}

void main() {
  late _MockSecureStorage secureStorage;

  setUp(() {
    secureStorage = _MockSecureStorage();
    when(() => secureStorage.read(key: any(named: 'key')))
        .thenAnswer((_) async => null);
    when(() => secureStorage.delete(key: any(named: 'key')))
        .thenAnswer((_) async {});
  });

  test('Android device metadata reads never reset stored credentials',
      () async {
    var readAttempts = 0;
    when(() => secureStorage.read(key: 'auth_device_id')).thenAnswer((_) async {
      readAttempts++;
      throw PlatformException(code: 'InvalidKeyException');
    });
    when(() => secureStorage.deleteAll()).thenAnswer((_) async {});

    final storage = SecureTokenStorage(secureStorage, true);

    await expectLater(
      storage.readDeviceId(),
      throwsA(isA<PlatformException>()),
    );
    expect(readAttempts, 1);
    verifyNever(() => secureStorage.deleteAll());
  });

  test('repairs an unreadable store before publishing the token pair',
      () async {
    var tokenPairReads = 0;
    final values = <String, String>{};
    when(() => secureStorage.read(key: any(named: 'key')))
        .thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      if (key == 'auth_token_pair_v1') {
        tokenPairReads += 1;
        if (tokenPairReads == 1) {
          throw PlatformException(code: 'BadPaddingException');
        }
      }
      return values[key];
    });
    when(
      () => secureStorage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((invocation) async {
      values[invocation.namedArguments[#key] as String] =
          invocation.namedArguments[#value] as String;
    });
    when(() => secureStorage.deleteAll()).thenAnswer((_) async {
      values.clear();
    });

    final accepted = _session('A', accessVersion: 1, refreshVersion: 1);
    final storage = SecureTokenStorage(secureStorage, true);
    await storage.writeTokens(
      accessToken: accepted.accessToken!,
      refreshToken: accepted.refreshToken!,
    );

    expect(tokenPairReads, 3);
    verify(() => secureStorage.deleteAll()).called(1);
  });

  test('replacement write failure preserves a readable session and cache',
      () async {
    final oldSession = _session('A', accessVersion: 1, refreshVersion: 1);
    final newSession = _session('B', accessVersion: 1, refreshVersion: 1);
    final oldPair = jsonEncode({
      'version': 1,
      'accessToken': oldSession.accessToken,
      'refreshToken': oldSession.refreshToken,
    });
    when(() => secureStorage.read(key: 'auth_token_pair_v1'))
        .thenAnswer((_) async => oldPair);
    when(() => secureStorage.read(key: 'auth_cached_profile'))
        .thenAnswer((_) async => '{"id":"user-old"}');
    when(
      () => secureStorage.write(
        key: 'auth_token_pair_v1',
        value: any(named: 'value'),
      ),
    ).thenThrow(PlatformException(code: 'BadPaddingException'));

    final storage = SecureTokenStorage(secureStorage, true);

    await expectLater(
      storage.writeTokens(
        accessToken: newSession.accessToken!,
        refreshToken: newSession.refreshToken!,
      ),
      throwsA(isA<PlatformException>()),
    );
    expect(await secureStorage.read(key: 'auth_token_pair_v1'), oldPair);
    expect(
      await secureStorage.read(key: 'auth_cached_profile'),
      '{"id":"user-old"}',
    );
    verifyNever(() => secureStorage.deleteAll());
    verifyNever(() => secureStorage.delete(key: 'auth_cached_profile'));
  });

  test('rejects a silent write that reads back the previous token pair',
      () async {
    final oldSession = _session('A', accessVersion: 1, refreshVersion: 1);
    final newSession = _session('B', accessVersion: 1, refreshVersion: 1);
    when(
      () => secureStorage.write(
        key: 'auth_token_pair_v1',
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(() => secureStorage.read(key: 'auth_token_pair_v1')).thenAnswer(
      (_) async => jsonEncode({
        'version': 1,
        'accessToken': oldSession.accessToken,
        'refreshToken': oldSession.refreshToken,
      }),
    );

    final storage = SecureTokenStorage(secureStorage, false);

    await expectLater(
      storage.writeTokens(
        accessToken: newSession.accessToken!,
        refreshToken: newSession.refreshToken!,
      ),
      throwsA(isA<StateError>()),
    );
    verifyNever(() => secureStorage.delete(key: any(named: 'key')));
  });

  test('stores one versioned pair and an exact rollback mirror', () async {
    final values = <String, String>{};
    _stubMemoryStorage(secureStorage, values);
    final accepted = _session('A', accessVersion: 1, refreshVersion: 1);
    final storage = SecureTokenStorage(secureStorage, false);
    await storage.writeTokens(
      accessToken: accepted.accessToken!,
      refreshToken: accepted.refreshToken!,
    );

    expect(
      values['auth_token_pair_v1'],
      jsonEncode({
        'version': 1,
        'accessToken': accepted.accessToken,
        'refreshToken': accepted.refreshToken,
      }),
    );
    expect(values['auth_access_token'], accepted.accessToken);
    expect(values['auth_refresh_token'], accepted.refreshToken);
  });

  test('same-SID mirror crash never crosses session identity', () async {
    final oldA = _session('A', accessVersion: 1, refreshVersion: 1);
    final rotatedA = _session('A', accessVersion: 2, refreshVersion: 2);
    final values = <String, String>{
      'auth_token_pair_v1': jsonEncode({
        'version': 1,
        'accessToken': oldA.accessToken,
        'refreshToken': oldA.refreshToken,
      }),
      'auth_access_token': oldA.accessToken!,
      'auth_refresh_token': oldA.refreshToken!,
    };
    _stubMemoryStorageWithWriteFailure(
      secureStorage,
      values,
      failingKey: 'auth_access_token',
      failingValue: rotatedA.accessToken!,
    );
    final storage = SecureTokenStorage(secureStorage, false);

    expect(
      await storage.replaceTokensIfCurrent(
        expected: oldA,
        accessToken: rotatedA.accessToken!,
        refreshToken: rotatedA.refreshToken!,
      ),
      isTrue,
    );

    final rollbackState = AuthTokenSnapshot(
      accessToken: values['auth_access_token'],
      refreshToken: values['auth_refresh_token'],
      storageFormat: AuthTokenStorageFormat.legacy,
    );
    expect(rollbackState.identity, oldA.identity);
    expect(values['auth_access_token'], oldA.accessToken);
    expect(values['auth_refresh_token'], rotatedA.refreshToken);
  });

  test('same-SID successor refresh failure leaves the predecessor intact',
      () async {
    final oldA = _session('A', accessVersion: 1, refreshVersion: 1);
    final rotatedA = _session('A', accessVersion: 2, refreshVersion: 2);
    final values = <String, String>{
      'auth_token_pair_v1': _encodedPair(oldA),
      'auth_access_token': oldA.accessToken!,
      'auth_refresh_token': oldA.refreshToken!,
    };
    _stubMemoryStorageWithWriteFailure(
      secureStorage,
      values,
      failingKey: 'auth_refresh_token',
      failingValue: rotatedA.refreshToken!,
    );
    final storage = SecureTokenStorage(secureStorage, false);

    await expectLater(
      storage.replaceTokensIfCurrent(
        expected: oldA,
        accessToken: rotatedA.accessToken!,
        refreshToken: rotatedA.refreshToken!,
      ),
      throwsA(isA<PlatformException>()),
    );

    expect(values['auth_token_pair_v1'], _encodedPair(oldA));
    expect(values['auth_access_token'], oldA.accessToken);
    expect(values['auth_refresh_token'], oldA.refreshToken);
  });

  test('same-SID canonical failure leaves a downgrade-recoverable pair',
      () async {
    final oldA = _session('A', accessVersion: 1, refreshVersion: 1);
    final rotatedA = _session('A', accessVersion: 2, refreshVersion: 2);
    final values = <String, String>{
      'auth_token_pair_v1': _encodedPair(oldA),
      'auth_access_token': oldA.accessToken!,
      'auth_refresh_token': oldA.refreshToken!,
    };
    _stubMemoryStorageWithWriteFailure(
      secureStorage,
      values,
      failingKey: 'auth_token_pair_v1',
      failingValue: _encodedPair(rotatedA),
    );
    final storage = SecureTokenStorage(secureStorage, false);

    await expectLater(
      storage.replaceTokensIfCurrent(
        expected: oldA,
        accessToken: rotatedA.accessToken!,
        refreshToken: rotatedA.refreshToken!,
      ),
      throwsA(isA<PlatformException>()),
    );

    expect(values['auth_token_pair_v1'], _encodedPair(oldA));
    final rollback = AuthTokenSnapshot(
      accessToken: values['auth_access_token'],
      refreshToken: values['auth_refresh_token'],
      storageFormat: AuthTokenStorageFormat.legacy,
    );
    expect(rollback.identity, oldA.identity);
    expect(rollback.accessToken, oldA.accessToken);
    expect(rollback.refreshToken, rotatedA.refreshToken);
  });

  test('A-to-B mirror crash can leave only B refresh', () async {
    final sessionA = _session('A', accessVersion: 1, refreshVersion: 1);
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_token_pair_v1': jsonEncode({
        'version': 1,
        'accessToken': sessionA.accessToken,
        'refreshToken': sessionA.refreshToken,
      }),
      'auth_access_token': sessionA.accessToken!,
      'auth_refresh_token': sessionA.refreshToken!,
    };
    _stubMemoryStorageWithWriteFailure(
      secureStorage,
      values,
      failingKey: 'auth_access_token',
      failingValue: sessionB.accessToken!,
    );
    final storage = SecureTokenStorage(secureStorage, false);

    await storage.writeTokens(
      accessToken: sessionB.accessToken!,
      refreshToken: sessionB.refreshToken!,
    );

    expect(values, isNot(contains('auth_access_token')));
    expect(values['auth_refresh_token'], sessionB.refreshToken);
    expect(
      AuthTokenLineage.tryParseJwt(values['auth_refresh_token'])?.identity,
      sessionB.identity,
    );
  });

  test('A-to-B successor refresh failure leaves no cross-owner raw pair',
      () async {
    final sessionA = _session('A', accessVersion: 1, refreshVersion: 1);
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_token_pair_v1': _encodedPair(sessionA),
      'auth_access_token': sessionA.accessToken!,
      'auth_refresh_token': sessionA.refreshToken!,
    };
    _stubMemoryStorageWithWriteFailure(
      secureStorage,
      values,
      failingKey: 'auth_refresh_token',
      failingValue: sessionB.refreshToken!,
    );
    final storage = SecureTokenStorage(secureStorage, false);

    await storage.writeTokens(
      accessToken: sessionB.accessToken!,
      refreshToken: sessionB.refreshToken!,
    );

    expect(values['auth_token_pair_v1'], _encodedPair(sessionB));
    expect(values, isNot(contains('auth_access_token')));
    expect(values['auth_refresh_token'], sessionA.refreshToken);
  });

  test('explicit logout fence survives restart and rejects a late refresh',
      () async {
    final sessionA = _session('A', accessVersion: 1, refreshVersion: 1);
    final rotatedA = _session('A', accessVersion: 2, refreshVersion: 2);
    final values = <String, String>{
      'auth_token_pair_v1': _encodedPair(sessionA),
      'auth_access_token': sessionA.accessToken!,
      'auth_refresh_token': sessionA.refreshToken!,
      'auth_cached_profile': '{"id":"client-account-A"}',
    };
    _stubMemoryStorage(secureStorage, values);
    final firstProcess = SecureTokenStorage(secureStorage, false);

    final fence = await firstProcess.beginExplicitLogout();

    expect(fence, isNotNull);
    expect((await firstProcess.readTokenSnapshot()).hasCredentials, isFalse);
    final restartedProcess = SecureTokenStorage(secureStorage, false);
    expect(
      (await restartedProcess.readTokenSnapshot()).hasCredentials,
      isFalse,
    );
    expect(
      await restartedProcess.replaceTokensIfCurrent(
        expected: sessionA,
        accessToken: rotatedA.accessToken!,
        refreshToken: rotatedA.refreshToken!,
      ),
      isFalse,
    );
    expect(
      await restartedProcess.finishExplicitLogout(fence!),
      isTrue,
    );
    expect(values, isNot(contains('auth_token_pair_v1')));
    expect(values, isNot(contains('auth_cached_profile')));
    expect(values, isNot(contains('auth_explicit_logout_fence_v1')));
  });

  test('accepted login B clears A fence only after B is canonical', () async {
    final sessionA = _session('A', accessVersion: 1, refreshVersion: 1);
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_token_pair_v1': _encodedPair(sessionA),
      'auth_access_token': sessionA.accessToken!,
      'auth_refresh_token': sessionA.refreshToken!,
      'auth_cached_profile': '{"id":"client-account-A"}',
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);
    final fence = await storage.beginExplicitLogout();

    await storage.writeTokens(
      accessToken: sessionB.accessToken!,
      refreshToken: sessionB.refreshToken!,
    );

    expect(
      (await storage.readTokenSnapshot()).isExactCredentialState(sessionB),
      isTrue,
    );
    expect(values, isNot(contains('auth_explicit_logout_fence_v1')));
    expect(await storage.finishExplicitLogout(fence!), isFalse);
    expect(
      (await storage.readTokenSnapshot()).isExactCredentialState(sessionB),
      isTrue,
    );
  });

  test(
      'pre-SID A fence cannot hide or clear same-principal accepted login B '
      'when fence cleanup is interrupted', () async {
    final legacyA = _legacyPair('A', role: 'client');
    final sessionB = _identityPair(
      subject: 'auth-root-A',
      role: 'client',
      sid: 'session-B',
      roleAccountId: 'client-account-A',
    );
    final values = <String, String>{
      'auth_access_token': legacyA.accessToken!,
      'auth_refresh_token': legacyA.refreshToken!,
      'auth_cached_profile': '{"id":"client-account-A"}',
    };
    _stubMemoryStorageWithOneDeleteFailure(
      secureStorage,
      values,
      failingKey: 'auth_explicit_logout_fence_v1',
    );
    final storage = SecureTokenStorage(secureStorage, false);
    final fence = await storage.beginExplicitLogout();

    await storage.writeTokens(
      accessToken: sessionB.accessToken!,
      refreshToken: sessionB.refreshToken!,
    );

    expect(
      (await storage.readTokenSnapshot()).isExactCredentialState(sessionB),
      isTrue,
    );
    expect(await storage.finishExplicitLogout(fence!), isFalse);
    expect(
      (await storage.readTokenSnapshot()).isExactCredentialState(sessionB),
      isTrue,
    );
    expect(values['auth_cached_profile'], '{"id":"client-account-A"}');
  });

  test('accepted write stays failed closed when its remaining fence covers it',
      () async {
    final sessionA = _session('A', accessVersion: 1, refreshVersion: 1);
    final rotatedA = _session('A', accessVersion: 2, refreshVersion: 2);
    final values = <String, String>{
      'auth_token_pair_v1': _encodedPair(sessionA),
      'auth_access_token': sessionA.accessToken!,
      'auth_refresh_token': sessionA.refreshToken!,
    };
    _stubMemoryStorageWithOneDeleteFailure(
      secureStorage,
      values,
      failingKey: 'auth_explicit_logout_fence_v1',
    );
    final storage = SecureTokenStorage(secureStorage, false);
    await storage.beginExplicitLogout();

    await expectLater(
      storage.writeTokens(
        accessToken: rotatedA.accessToken!,
        refreshToken: rotatedA.refreshToken!,
      ),
      throwsA(isA<PlatformException>()),
    );

    expect((await storage.readTokenSnapshot()).hasCredentials, isFalse);
  });

  test('legacy logout repair stays invisible behind its durable fence',
      () async {
    final legacy = _legacyPair('A', role: 'client');
    final upgraded = _session('A', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_access_token': legacy.accessToken!,
      'auth_refresh_token': legacy.refreshToken!,
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);
    final fence = await storage.beginExplicitLogout();

    expect((await storage.readTokenSnapshot()).hasCredentials, isFalse);
    expect(
      await storage.replaceExplicitLogoutTokensIfCurrent(
        fence: fence!,
        expected: legacy,
        accessToken: upgraded.accessToken!,
        refreshToken: upgraded.refreshToken!,
      ),
      isTrue,
    );
    expect((await storage.readTokenSnapshot()).hasCredentials, isFalse);
    final privileged = await storage.readExplicitLogoutOwner(fence);
    expect(privileged?.identity, upgraded.identity);
    expect(await storage.finishExplicitLogout(fence), isTrue);
    expect((await storage.readTokenSnapshot()).hasCredentials, isFalse);
  });

  test('restart between legacy fence evolution and canonical repair stays out',
      () async {
    final legacy = _legacyPair('A', role: 'client');
    final upgraded = _session('A', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_access_token': legacy.accessToken!,
      'auth_refresh_token': legacy.refreshToken!,
    };
    _stubMemoryStorageWithWriteFailure(
      secureStorage,
      values,
      failingKey: 'auth_token_pair_v1',
      failingValue: _encodedPair(upgraded),
    );
    final storage = SecureTokenStorage(secureStorage, false);
    final fence = await storage.beginExplicitLogout();

    await expectLater(
      storage.replaceExplicitLogoutTokensIfCurrent(
        fence: fence!,
        expected: legacy,
        accessToken: upgraded.accessToken!,
        refreshToken: upgraded.refreshToken!,
      ),
      throwsA(isA<PlatformException>()),
    );

    final restarted = SecureTokenStorage(secureStorage, false);
    expect((await restarted.readTokenSnapshot()).hasCredentials, isFalse);
    expect(
      (await restarted.readExplicitLogoutOwner(fence))
          ?.hasExactRawCredentials(legacy),
      isTrue,
    );
  });

  test('stale A attempt cannot replace or clear B attempt metadata', () async {
    final sessionA = _session('A', accessVersion: 1, refreshVersion: 1);
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_token_pair_v1': _encodedPair(sessionA),
      'auth_access_token': sessionA.accessToken!,
      'auth_refresh_token': sessionA.refreshToken!,
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);
    final attemptA = await storage.readOrCreateIfCurrent(sessionA);

    await storage.writeTokens(
      accessToken: sessionB.accessToken!,
      refreshToken: sessionB.refreshToken!,
    );
    final attemptB = await storage.readOrCreateIfCurrent(sessionB);
    await storage.clearIfMatches(
      refreshToken: sessionA.refreshToken!,
      attemptId: attemptA!,
    );

    expect(await storage.readOrCreateIfCurrent(sessionA), isNull);
    expect(await storage.readOrCreateIfCurrent(sessionB), attemptB);
    expect(attemptB, isNot(attemptA));
  });

  for (final fixture in [
    (name: 'pre-SID', owner: _legacyPair('A', role: 'client')),
    (
      name: 'interrupted split',
      owner: _interruptedUpgrade(
        'A',
        role: 'client',
        sid: 'session-A',
      ),
    ),
  ]) {
    test('${fixture.name} canonical failure preserves both released raw keys',
        () async {
      final owner = fixture.owner;
      final upgraded = _session('A', accessVersion: 2, refreshVersion: 2);
      final values = <String, String>{
        'auth_access_token': owner.accessToken!,
        'auth_refresh_token': owner.refreshToken!,
      };
      _stubMemoryStorageWithWriteFailure(
        secureStorage,
        values,
        failingKey: 'auth_token_pair_v1',
        failingValue: _encodedPair(upgraded),
      );
      final storage = SecureTokenStorage(secureStorage, false);

      final mutation = owner.isInterruptedPreSessionIdUpgrade
          ? storage.replaceInterruptedLegacyTokensIfCurrent(
              expected: owner,
              accessToken: upgraded.accessToken!,
              refreshToken: upgraded.refreshToken!,
            )
          : storage.replaceLegacyTokensIfCurrent(
              expected: owner,
              accessToken: upgraded.accessToken!,
              refreshToken: upgraded.refreshToken!,
            );
      await expectLater(mutation, throwsA(isA<PlatformException>()));

      expect(values['auth_access_token'], owner.accessToken);
      expect(values['auth_refresh_token'], owner.refreshToken);
      expect(values, isNot(contains('auth_token_pair_v1')));
    });
  }

  for (final failingDeleteKey in const ['auth_access_token']) {
    test('cross-owner $failingDeleteKey failure stays downgrade-owner-safe',
        () async {
      final sessionA = _session('A', accessVersion: 1, refreshVersion: 1);
      final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
      final values = <String, String>{
        'auth_token_pair_v1': _encodedPair(sessionA),
        'auth_access_token': sessionA.accessToken!,
        'auth_refresh_token': sessionA.refreshToken!,
      };
      _stubMemoryStorageWithDeleteFailure(
        secureStorage,
        values,
        failingKey: failingDeleteKey,
      );
      final storage = SecureTokenStorage(secureStorage, false);

      await storage.writeTokens(
        accessToken: sessionB.accessToken!,
        refreshToken: sessionB.refreshToken!,
      );

      expect(
        (await storage.readTokenSnapshot()).isExactCredentialState(sessionB),
        isTrue,
      );
      final rollback = AuthTokenSnapshot(
        accessToken: values['auth_access_token'],
        refreshToken: values['auth_refresh_token'],
        storageFormat: AuthTokenStorageFormat.legacy,
      );
      expect(
        rollback.identity == sessionA.identity ||
            (rollback.accessToken == null &&
                rollback.refreshToken == sessionA.refreshToken),
        isTrue,
      );
    });
  }

  test('prefers the complete versioned pair over legacy token keys', () async {
    when(() => secureStorage.read(key: 'auth_token_pair_v1')).thenAnswer(
      (_) async =>
          '{"version":1,"accessToken":"pair-access","refreshToken":"pair-refresh"}',
    );

    final storage = SecureTokenStorage(secureStorage, false);

    expect(await storage.readAccessToken(), 'pair-access');
    expect(await storage.readRefreshToken(), 'pair-refresh');
    verifyNever(() => secureStorage.read(key: 'auth_access_token'));
    verifyNever(() => secureStorage.read(key: 'auth_refresh_token'));
  });

  test('reading a complete legacy pair never migrates or deletes it', () async {
    final legacyAccess = _jwt(
      subject: 'user-A',
      role: 'client',
      marker: 'legacy-access',
    );
    final legacyRefresh = _jwt(
      subject: 'user-A',
      role: 'client',
      marker: 'legacy-refresh',
    );
    final values = <String, String>{
      'auth_access_token': legacyAccess,
      'auth_refresh_token': legacyRefresh,
    };
    _stubMemoryStorage(secureStorage, values);

    final storage = SecureTokenStorage(secureStorage, false);
    final snapshot = await storage.readTokenSnapshot();

    expect(snapshot.accessToken, legacyAccess);
    expect(snapshot.refreshToken, legacyRefresh);
    expect(snapshot.storageFormat, AuthTokenStorageFormat.legacy);
    expect(values, isNot(contains('auth_token_pair_v1')));
    expect(values['auth_access_token'], legacyAccess);
    expect(values['auth_refresh_token'], legacyRefresh);
    verifyNever(
      () => secureStorage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    );
    verifyNever(() => secureStorage.delete(key: any(named: 'key')));
  });

  test('background legacy read cannot attempt a write or touch cache',
      () async {
    final legacyAccess = _jwt(
      subject: 'user-A',
      role: 'client',
      marker: 'legacy-access',
    );
    final legacyRefresh = _jwt(
      subject: 'user-A',
      role: 'client',
      marker: 'legacy-refresh',
    );
    when(() => secureStorage.read(key: 'auth_token_pair_v1'))
        .thenAnswer((_) async => null);
    when(() => secureStorage.read(key: 'auth_access_token'))
        .thenAnswer((_) async => legacyAccess);
    when(() => secureStorage.read(key: 'auth_refresh_token'))
        .thenAnswer((_) async => legacyRefresh);
    final storage = SecureTokenStorage(secureStorage, false);

    final snapshot = await storage.readTokenSnapshot();

    expect(snapshot.accessToken, legacyAccess);
    expect(snapshot.refreshToken, legacyRefresh);
    expect(snapshot.storageFormat, AuthTokenStorageFormat.legacy);
    verifyNever(
      () => secureStorage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    );
    verifyNever(() => secureStorage.delete(key: 'auth_access_token'));
    verifyNever(() => secureStorage.delete(key: 'auth_refresh_token'));
    verifyNever(() => secureStorage.delete(key: 'auth_cached_profile'));
    verifyNever(() => secureStorage.deleteAll());
  });

  test('a paused legacy reader instance cannot overwrite a newer account',
      () async {
    final legacyA = _session('A', accessVersion: 1, refreshVersion: 1);
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_access_token': legacyA.accessToken!,
      'auth_refresh_token': legacyA.refreshToken!,
      'auth_cached_profile': '{"id":"client-account-A"}',
    };
    _stubMemoryStorage(secureStorage, values);
    final pausedA = SecureTokenStorage(secureStorage, false);
    final foregroundB = SecureTokenStorage(secureStorage, false);

    final observedA = await pausedA.readTokenSnapshot();
    expect(observedA.storageFormat, AuthTokenStorageFormat.legacy);

    await foregroundB.writeTokens(
      accessToken: sessionB.accessToken!,
      refreshToken: sessionB.refreshToken!,
    );
    values['auth_cached_profile'] = '{"id":"client-account-B"}';

    expect(await pausedA.clearTokensIfCurrent(observedA), isFalse);
    expect(
      await pausedA.writeSessionMetadataIfCurrent(
        expected: observedA,
        phone: '+233240000001',
        role: 'client',
      ),
      isFalse,
    );
    final current = await pausedA.readTokenSnapshot();
    expect(current.isExactCredentialState(sessionB), isTrue);
    expect(values['auth_cached_profile'], '{"id":"client-account-B"}');
  });

  for (final fixture in [
    (
      name: 'mixed account',
      access: _jwt(
        subject: 'user-A',
        role: 'client',
        marker: 'legacy-access',
      ),
      refresh: _jwt(
        subject: 'user-B',
        role: 'client',
        marker: 'legacy-refresh',
      ),
    ),
    (
      name: 'mixed role',
      access: _jwt(
        subject: 'user-A',
        role: 'client',
        marker: 'legacy-access',
      ),
      refresh: _jwt(
        subject: 'user-A',
        role: 'driver',
        marker: 'legacy-refresh',
      ),
    ),
    (
      name: 'mixed SID',
      access: _jwt(
        subject: 'user-A',
        role: 'client',
        sid: 'session-A',
        marker: 'access',
      ),
      refresh: _jwt(
        subject: 'user-A',
        role: 'client',
        sid: 'session-B',
        marker: 'refresh',
      ),
    ),
  ]) {
    test('${fixture.name} legacy pair is preserved and never cemented',
        () async {
      final values = <String, String>{
        'auth_access_token': fixture.access,
        'auth_refresh_token': fixture.refresh,
      };
      _stubMemoryStorage(secureStorage, values);
      final storage = SecureTokenStorage(secureStorage, false);

      final snapshot = await storage.readTokenSnapshot();

      expect(snapshot.storageFormat, AuthTokenStorageFormat.legacy);
      expect(snapshot.accessToken, fixture.access);
      expect(snapshot.refreshToken, fixture.refresh);
      expect(values, isNot(contains('auth_token_pair_v1')));
      expect(values['auth_access_token'], fixture.access);
      expect(values['auth_refresh_token'], fixture.refresh);
      verifyNever(
        () => secureStorage.write(
          key: 'auth_token_pair_v1',
          value: any(named: 'value'),
        ),
      );
      verifyNever(() => secureStorage.delete(key: 'auth_access_token'));
      verifyNever(() => secureStorage.delete(key: 'auth_refresh_token'));
    });
  }

  test(
      'interrupted pre-SID upgrade is classified and preserved as a split '
      'legacy pair', () async {
    final access = _jwt(
      subject: 'user-A',
      role: 'client',
      sid: 'session-A',
      includeRoleAccountId: false,
      marker: 'migrated-access',
    );
    final refresh = _jwt(
      subject: 'user-A',
      role: 'client',
      marker: 'legacy-refresh',
    );
    final values = <String, String>{
      'auth_access_token': access,
      'auth_refresh_token': refresh,
      'auth_cached_profile': '{"id":"user-A"}',
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);

    final snapshot = await storage.readTokenSnapshot();

    expect(snapshot.isInterruptedPreSessionIdUpgrade, isTrue);
    expect(snapshot.isPreSessionIdCredentialState, isFalse);
    expect(snapshot.accessLineage?.sessionId, 'session-A');
    expect(snapshot.refreshIdentity, isNull);
    expect(snapshot.storageFormat, AuthTokenStorageFormat.legacy);
    expect(values, isNot(contains('auth_token_pair_v1')));
    expect(values['auth_access_token'], access);
    expect(values['auth_refresh_token'], refresh);
    expect(values['auth_cached_profile'], '{"id":"user-A"}');
    verifyNever(() => secureStorage.delete(key: 'auth_access_token'));
    verifyNever(() => secureStorage.delete(key: 'auth_refresh_token'));
  });

  test('malformed versioned state never resurrects legacy credentials',
      () async {
    when(() => secureStorage.read(key: 'auth_token_pair_v1'))
        .thenAnswer((_) async => '{"version":1,"accessToken":"partial"}');

    final storage = SecureTokenStorage(secureStorage, false);

    await expectLater(
      storage.readTokenSnapshot(),
      throwsA(isA<StateError>()),
    );
    verifyNever(() => secureStorage.read(key: 'auth_access_token'));
    verifyNever(() => secureStorage.read(key: 'auth_refresh_token'));
  });

  test('updating only access preserves refresh in one complete pair', () async {
    final oldA = _session('A', accessVersion: 1, refreshVersion: 1);
    final rotatedA = _session('A', accessVersion: 2, refreshVersion: 2);
    final values = <String, String>{
      'auth_token_pair_v1': jsonEncode({
        'version': 1,
        'accessToken': oldA.accessToken,
        'refreshToken': oldA.refreshToken,
      }),
    };
    _stubMemoryStorage(secureStorage, values);

    final storage = SecureTokenStorage(secureStorage, false);
    await storage.writeAccessToken(rotatedA.accessToken!);

    expect(
      values['auth_token_pair_v1'],
      jsonEncode({
        'version': 1,
        'accessToken': rotatedA.accessToken,
        'refreshToken': oldA.refreshToken,
      }),
    );
    expect(values['auth_access_token'], rotatedA.accessToken);
    expect(values['auth_refresh_token'], oldA.refreshToken);
  });

  test('a stale refresh compare-and-set preserves a replacement account',
      () async {
    final sessionA = _session('A', accessVersion: 1, refreshVersion: 1);
    final rotatedA = _session('A', accessVersion: 2, refreshVersion: 2);
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_token_pair_v1': jsonEncode({
        'version': 1,
        'accessToken': sessionA.accessToken,
        'refreshToken': sessionA.refreshToken,
      }),
      'auth_cached_profile': '{"id":"user-B"}',
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);
    final observedA = await storage.readTokenSnapshot();

    await storage.writeTokens(
      accessToken: sessionB.accessToken!,
      refreshToken: sessionB.refreshToken!,
    );
    final replaced = await storage.replaceTokensIfCurrent(
      expected: observedA,
      accessToken: rotatedA.accessToken!,
      refreshToken: rotatedA.refreshToken!,
    );

    expect(replaced, isFalse);
    final current = await storage.readTokenSnapshot();
    expect(current.accessToken, sessionB.accessToken);
    expect(current.refreshToken, sessionB.refreshToken);
    expect(values['auth_cached_profile'], '{"id":"user-B"}');
  });

  test('identity-bound logout clears a same-SID rotated token pair', () async {
    final sessionA = _session('A', accessVersion: 1, refreshVersion: 1);
    final rotatedA = _session('A', accessVersion: 2, refreshVersion: 2);
    final values = <String, String>{
      'auth_token_pair_v1': jsonEncode({
        'version': 1,
        'accessToken': rotatedA.accessToken,
        'refreshToken': rotatedA.refreshToken,
      }),
      'auth_access_token': rotatedA.accessToken!,
      'auth_refresh_token': rotatedA.refreshToken!,
      'auth_cached_profile': '{"id":"client-account-A"}',
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);

    expect(
      await storage.clearTokensForIdentityIfCurrent(sessionA.identity!),
      isTrue,
    );
    expect((await storage.readTokenSnapshot()).hasCredentials, isFalse);
    expect(values, isNot(contains('auth_cached_profile')));
  });

  test('identity-bound A logout cannot clear session B', () async {
    final sessionA = _session('A', accessVersion: 1, refreshVersion: 1);
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_token_pair_v1': jsonEncode({
        'version': 1,
        'accessToken': sessionB.accessToken,
        'refreshToken': sessionB.refreshToken,
      }),
      'auth_access_token': sessionB.accessToken!,
      'auth_refresh_token': sessionB.refreshToken!,
      'auth_cached_profile': '{"id":"client-account-B"}',
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);

    expect(
      await storage.clearTokensForIdentityIfCurrent(sessionA.identity!),
      isFalse,
    );
    expect(
      (await storage.readTokenSnapshot()).isExactCredentialState(sessionB),
      isTrue,
    );
    expect(values['auth_cached_profile'], '{"id":"client-account-B"}');
  });

  test('bootstrap migration upgrades an exact pre-SID refresh credential',
      () async {
    final legacyRefresh = _jwt(
      subject: 'auth-root-A',
      role: 'client',
      marker: 'legacy-refresh',
    );
    final upgraded = _session('A', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_refresh_token': legacyRefresh,
      'auth_cached_profile': '{"id":"user-A"}',
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);
    final observed = await storage.readTokenSnapshot();

    final replaced = await storage.replaceLegacyTokensIfCurrent(
      expected: observed,
      accessToken: upgraded.accessToken!,
      refreshToken: upgraded.refreshToken!,
    );

    expect(replaced, isTrue);
    final current = await storage.readTokenSnapshot();
    expect(current.identity, upgraded.identity);
    expect(current.accessToken, upgraded.accessToken);
    expect(current.refreshToken, upgraded.refreshToken);
    expect(values['auth_access_token'], upgraded.accessToken);
    expect(values['auth_refresh_token'], upgraded.refreshToken);
    expect(values['auth_cached_profile'], '{"id":"user-A"}');
  });

  test('bootstrap finishes an exact interrupted pre-SID upgrade', () async {
    final interrupted = _interruptedUpgrade(
      'A',
      role: 'client',
      sid: 'session-A',
    );
    final upgraded = _session('A', accessVersion: 2, refreshVersion: 2);
    final values = <String, String>{
      'auth_access_token': interrupted.accessToken!,
      'auth_refresh_token': interrupted.refreshToken!,
      'auth_cached_profile': '{"id":"user-A"}',
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);
    final observed = await storage.readTokenSnapshot();

    final replaced = await storage.replaceInterruptedLegacyTokensIfCurrent(
      expected: observed,
      accessToken: upgraded.accessToken!,
      refreshToken: upgraded.refreshToken!,
    );

    expect(replaced, isTrue);
    final current = await storage.readTokenSnapshot();
    expect(current.identity?.generation, interrupted.accessLineage?.generation);
    expect(current.accessToken, upgraded.accessToken);
    expect(current.refreshToken, upgraded.refreshToken);
    expect(values['auth_access_token'], upgraded.accessToken);
    expect(values['auth_refresh_token'], upgraded.refreshToken);
    expect(values['auth_cached_profile'], '{"id":"user-A"}');
  });

  for (final fixture in [
    (
      name: 'account',
      returned: _identityPair(
        subject: 'user-B',
        role: 'client',
        sid: 'session-A',
      ),
    ),
    (
      name: 'role',
      returned: _identityPair(
        subject: 'user-A',
        role: 'driver',
        sid: 'session-A',
      ),
    ),
    (
      name: 'SID',
      returned: _identityPair(
        subject: 'user-A',
        role: 'client',
        sid: 'session-other',
      ),
    ),
  ]) {
    test('interrupted upgrade rejects a returned ${fixture.name} mismatch',
        () async {
      final interrupted = _interruptedUpgrade(
        'A',
        role: 'client',
        sid: 'session-A',
      );
      final values = <String, String>{
        'auth_access_token': interrupted.accessToken!,
        'auth_refresh_token': interrupted.refreshToken!,
      };
      _stubMemoryStorage(secureStorage, values);
      final storage = SecureTokenStorage(secureStorage, false);
      final observed = await storage.readTokenSnapshot();

      final replaced = await storage.replaceInterruptedLegacyTokensIfCurrent(
        expected: observed,
        accessToken: fixture.returned.accessToken!,
        refreshToken: fixture.returned.refreshToken!,
      );

      expect(replaced, isFalse);
      expect(values, isNot(contains('auth_token_pair_v1')));
      expect(values['auth_access_token'], interrupted.accessToken);
      expect(values['auth_refresh_token'], interrupted.refreshToken);
    });
  }

  test('stale interrupted A upgrade cannot overwrite account B', () async {
    final interruptedA = _interruptedUpgrade(
      'A',
      role: 'client',
      sid: 'session-A',
    );
    final upgradedA = _session('A', accessVersion: 2, refreshVersion: 2);
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_access_token': interruptedA.accessToken!,
      'auth_refresh_token': interruptedA.refreshToken!,
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);
    final observedA = await storage.readTokenSnapshot();
    await storage.writeTokens(
      accessToken: sessionB.accessToken!,
      refreshToken: sessionB.refreshToken!,
    );

    final replaced = await storage.replaceInterruptedLegacyTokensIfCurrent(
      expected: observedA,
      accessToken: upgradedA.accessToken!,
      refreshToken: upgradedA.refreshToken!,
    );

    expect(replaced, isFalse);
    final current = await storage.readTokenSnapshot();
    expect(current.isExactCredentialState(sessionB), isTrue);
  });

  for (final fixture in [
    (
      name: 'both missing',
      accessHasRoleAccount: false,
      refreshHasRoleAccount: false
    ),
    (
      name: 'access-only',
      accessHasRoleAccount: true,
      refreshHasRoleAccount: false
    ),
    (
      name: 'refresh-only',
      accessHasRoleAccount: false,
      refreshHasRoleAccount: true
    ),
  ]) {
    test('upgrades SID lineage with roleAccountId ${fixture.name}', () async {
      final legacy = _roleAccountUpgrade(
        'A',
        accessHasRoleAccount: fixture.accessHasRoleAccount,
        refreshHasRoleAccount: fixture.refreshHasRoleAccount,
      );
      final upgraded = _session('A', accessVersion: 2, refreshVersion: 2);
      final values = <String, String>{
        'auth_access_token': legacy.accessToken!,
        'auth_refresh_token': legacy.refreshToken!,
      };
      _stubMemoryStorage(secureStorage, values);
      final storage = SecureTokenStorage(secureStorage, false);
      final observed = await storage.readTokenSnapshot();

      expect(observed.isPreSessionIdCredentialState, isFalse);
      expect(observed.isSessionRoleAccountIdUpgrade, isTrue);
      final replaced = await storage.replaceSessionLineageTokensIfCurrent(
        expected: observed,
        accessToken: upgraded.accessToken!,
        refreshToken: upgraded.refreshToken!,
      );

      expect(replaced, isTrue);
      final current = await storage.readTokenSnapshot();
      expect(current.identity, upgraded.identity);
      expect(current.identity?.generation, observed.generation);
      expect(current.identity?.roleAccountId, 'client-account-A');
    });
  }

  for (final fixture in [
    (
      name: 'private root',
      returned: _identityPair(
        subject: 'auth-root-B',
        role: 'client',
        sid: 'session-A',
      ),
    ),
    (
      name: 'role',
      returned: _identityPair(
        subject: 'auth-root-A',
        role: 'driver',
        sid: 'session-A',
      ),
    ),
    (
      name: 'SID',
      returned: _identityPair(
        subject: 'auth-root-A',
        role: 'client',
        sid: 'session-other',
      ),
    ),
    (
      name: 'populated role account',
      returned: _identityPair(
        subject: 'auth-root-A',
        role: 'client',
        sid: 'session-A',
        roleAccountId: 'different-client-account',
      ),
    ),
  ]) {
    test('role-account lineage upgrade rejects ${fixture.name} replacement',
        () async {
      final legacy = _roleAccountUpgrade(
        'A',
        accessHasRoleAccount: true,
        refreshHasRoleAccount: false,
      );
      final values = <String, String>{
        'auth_access_token': legacy.accessToken!,
        'auth_refresh_token': legacy.refreshToken!,
      };
      _stubMemoryStorage(secureStorage, values);
      final storage = SecureTokenStorage(secureStorage, false);
      final observed = await storage.readTokenSnapshot();

      expect(
        await storage.replaceSessionLineageTokensIfCurrent(
          expected: observed,
          accessToken: fixture.returned.accessToken!,
          refreshToken: fixture.returned.refreshToken!,
        ),
        isFalse,
      );
      expect(values, isNot(contains('auth_token_pair_v1')));
      expect(values['auth_access_token'], legacy.accessToken);
      expect(values['auth_refresh_token'], legacy.refreshToken);
    });
  }

  test('stale SID-lineage A upgrade cannot overwrite account B', () async {
    final legacyA = _roleAccountUpgrade(
      'A',
      accessHasRoleAccount: false,
      refreshHasRoleAccount: false,
    );
    final upgradedA = _session('A', accessVersion: 2, refreshVersion: 2);
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_access_token': legacyA.accessToken!,
      'auth_refresh_token': legacyA.refreshToken!,
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);
    final observedA = await storage.readTokenSnapshot();
    await storage.writeTokens(
      accessToken: sessionB.accessToken!,
      refreshToken: sessionB.refreshToken!,
    );

    expect(
      await storage.replaceSessionLineageTokensIfCurrent(
        expected: observedA,
        accessToken: upgradedA.accessToken!,
        refreshToken: upgradedA.refreshToken!,
      ),
      isFalse,
    );
    expect(
      (await storage.readTokenSnapshot()).isExactCredentialState(sessionB),
      isTrue,
    );
  });

  test('legacy migration rejects a returned pair for another principal',
      () async {
    final legacyRefresh = _jwt(
      subject: 'user-A',
      role: 'client',
      marker: 'legacy-refresh',
    );
    final accountB = _session('B', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_refresh_token': legacyRefresh,
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);
    final observed = await storage.readTokenSnapshot();

    final replaced = await storage.replaceLegacyTokensIfCurrent(
      expected: observed,
      accessToken: accountB.accessToken!,
      refreshToken: accountB.refreshToken!,
    );

    expect(replaced, isFalse);
    expect(await storage.readRefreshToken(), legacyRefresh);
    expect(values, isNot(contains('auth_token_pair_v1')));
  });

  test('released-key fixture upgrades in place without losing session metadata',
      () async {
    final released = _legacyPair('A', role: 'client');
    final upgraded = _identityPair(
      subject: 'auth-root-A',
      role: 'client',
      sid: 'session-A',
      roleAccountId: 'client-account-A',
    );
    const cachedProfile = '''
{"id":"auth-root-A","phone":"+233240000001","client":{"id":"client-account-A","name":"Ama"}}''';
    final values = <String, String>{
      'auth_access_token': released.accessToken!,
      'auth_refresh_token': released.refreshToken!,
      'auth_phone': '+233240000001',
      'auth_role': 'client',
      'auth_session_started_at': '2026-07-01T10:00:00.000Z',
      'auth_cached_profile': cachedProfile,
      'auth_device_id': 'released-device-id',
      'onboarding_seen': 'true',
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);

    expect(values, isNot(contains('auth_token_pair_v1')));
    expect(values, isNot(contains('auth_refresh_attempt_v1')));
    expect(values, isNot(contains('auth_explicit_logout_fence_v1')));
    final observed = await storage.readTokenSnapshot();
    expect(observed.storageFormat, AuthTokenStorageFormat.legacy);
    expect(observed.hasExactRawCredentials(released), isTrue);

    expect(
      await storage.replaceLegacyTokensIfCurrent(
        expected: observed,
        accessToken: upgraded.accessToken!,
        refreshToken: upgraded.refreshToken!,
      ),
      isTrue,
    );

    final current = await storage.readTokenSnapshot();
    expect(current.isExactCredentialState(upgraded), isTrue);
    expect(values['auth_token_pair_v1'], _encodedPair(upgraded));
    expect(values['auth_access_token'], upgraded.accessToken);
    expect(values['auth_refresh_token'], upgraded.refreshToken);
    expect(values['auth_phone'], '+233240000001');
    expect(values['auth_role'], 'client');
    expect(values['auth_session_started_at'], '2026-07-01T10:00:00.000Z');
    expect(values['auth_cached_profile'], cachedProfile);
    expect(values['auth_device_id'], 'released-device-id');
    expect(values['onboarding_seen'], 'true');
    expect(values, isNot(contains('auth_refresh_attempt_v1')));
    expect(values, isNot(contains('auth_explicit_logout_fence_v1')));
  });

  test('terminal clear removes the exact raw legacy owner', () async {
    final legacyRefresh = _jwt(
      subject: 'user-A',
      role: 'client',
      marker: 'legacy-refresh',
    );
    final values = <String, String>{
      'auth_refresh_token': legacyRefresh,
      'auth_cached_profile': '{"id":"user-A"}',
      'auth_phone': '+233240000001',
      'auth_role': 'client',
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);
    final observedA = await storage.readTokenSnapshot();

    final cleared = await storage.clearTokensIfCurrent(observedA);

    expect(cleared, isTrue);
    expect(values, isNot(contains('auth_refresh_token')));
    expect(values, isNot(contains('auth_cached_profile')));
    expect(values, isNot(contains('auth_phone')));
    expect(values, isNot(contains('auth_role')));
  });

  test('stale legacy A clear and metadata writes leave account B untouched',
      () async {
    final legacyRefresh = _jwt(
      subject: 'user-A',
      role: 'client',
      marker: 'legacy-refresh',
    );
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_refresh_token': legacyRefresh,
      'auth_cached_profile': '{"id":"user-A"}',
      'auth_phone': '+233240000001',
      'auth_role': 'client',
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);
    final observedA = await storage.readTokenSnapshot();
    await storage.writeTokens(
      accessToken: sessionB.accessToken!,
      refreshToken: sessionB.refreshToken!,
    );
    values['auth_cached_profile'] = '{"id":"user-B"}';
    values['auth_phone'] = '+233240000002';
    values['auth_role'] = 'artisan';

    expect(await storage.clearTokensIfCurrent(observedA), isFalse);
    expect(await storage.clearAuthTokensOnlyIfCurrent(observedA), isFalse);
    expect(await storage.clearCachedProfileIfCurrent(observedA), isFalse);
    expect(
      await storage.writeSessionMetadataIfCurrent(
        expected: observedA,
        phone: '+233240000001',
        role: 'client',
      ),
      isFalse,
    );

    final current = await storage.readTokenSnapshot();
    expect(current.accessToken, sessionB.accessToken);
    expect(current.refreshToken, sessionB.refreshToken);
    expect(values['auth_cached_profile'], '{"id":"user-B"}');
    expect(values['auth_phone'], '+233240000002');
    expect(values['auth_role'], 'artisan');
  });

  test('takeover soft-clear follows same-session token rotation', () async {
    final originalA = _session('A', accessVersion: 1, refreshVersion: 1);
    final rotatedA = _session('A', accessVersion: 2, refreshVersion: 2);
    final values = <String, String>{
      'auth_token_pair_v1': _encodedPair(rotatedA),
      'auth_access_token': rotatedA.accessToken!,
      'auth_refresh_token': rotatedA.refreshToken!,
      'auth_cached_profile': '{"id":"client-account-A"}',
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);

    expect(
      await storage.clearAuthTokensOnlyForIdentityIfCurrent(
        originalA.identity!,
      ),
      isTrue,
    );
    expect((await storage.readTokenSnapshot()).hasCredentials, isFalse);
    expect(values['auth_cached_profile'], '{"id":"client-account-A"}');
  });

  test('takeover soft-clear for account A preserves current account B',
      () async {
    final sessionA = _session('A', accessVersion: 1, refreshVersion: 1);
    final sessionB = _session('B', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_token_pair_v1': _encodedPair(sessionB),
      'auth_access_token': sessionB.accessToken!,
      'auth_refresh_token': sessionB.refreshToken!,
      'auth_cached_profile': '{"id":"client-account-B"}',
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(secureStorage, false);

    expect(
      await storage.clearAuthTokensOnlyForIdentityIfCurrent(
        sessionA.identity!,
      ),
      isFalse,
    );
    expect(
      (await storage.readTokenSnapshot()).isExactCredentialState(sessionB),
      isTrue,
    );
    expect(values['auth_cached_profile'], '{"id":"client-account-B"}');
  });

  test('first iOS boundary deterministically grandfathers an existing install',
      () async {
    final session = _session('A', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_token_pair_v1': jsonEncode({
        'version': 1,
        'accessToken': session.accessToken,
        'refreshToken': session.refreshToken,
      }),
      'auth_access_token': session.accessToken!,
      'auth_refresh_token': session.refreshToken!,
      'auth_device_id': 'existing-device-id',
    };
    _stubMemoryStorage(secureStorage, values);
    final epochStore = _MemoryInstallEpochStore();
    final first = SecureTokenStorage(secureStorage, false, epochStore, true);

    expect((await first.readTokenSnapshot()).identity, session.identity);
    final firstEpoch = epochStore.epoch;
    expect(firstEpoch, isNotNull);
    expect(
      jsonDecode(values['auth_install_boundary_v1']!) as Map<String, dynamic>,
      containsPair('state', 'active'),
    );

    final second = SecureTokenStorage(secureStorage, false, epochStore, true);
    expect((await second.readTokenSnapshot()).identity, session.identity);
    expect(epochStore.epoch, firstEpoch);
    expect(values['auth_device_id'], 'existing-device-id');
  });

  test('active iOS epoch mismatch clears all install-owned secure values',
      () async {
    final session = _session('A', accessVersion: 1, refreshVersion: 1);
    final values = <String, String>{
      'auth_install_boundary_v1':
          '{"v":1,"state":"active","epoch":"old-install"}',
      'auth_token_pair_v1': jsonEncode({
        'version': 1,
        'accessToken': session.accessToken,
        'refreshToken': session.refreshToken,
      }),
      'auth_access_token': session.accessToken!,
      'auth_refresh_token': session.refreshToken!,
      'auth_phone': '+233240000001',
      'auth_role': 'client',
      'auth_cached_profile': '{"id":"client-account-A"}',
      'auth_device_id': 'old-device',
      'onboarding_seen': 'true',
    };
    _stubMemoryStorage(secureStorage, values);
    final epochStore = _MemoryInstallEpochStore();
    final storage = SecureTokenStorage(secureStorage, false, epochStore, true);

    expect((await storage.readTokenSnapshot()).hasCredentials, isFalse);

    for (final key in const [
      'auth_token_pair_v1',
      'auth_access_token',
      'auth_refresh_token',
      'auth_phone',
      'auth_role',
      'auth_cached_profile',
      'auth_device_id',
      'onboarding_seen',
    ]) {
      expect(values, isNot(contains(key)));
    }
    final boundary =
        jsonDecode(values['auth_install_boundary_v1']!) as Map<String, dynamic>;
    expect(boundary['state'], 'active');
    expect(boundary['epoch'], epochStore.epoch);
    expect(epochStore.epoch, isNot('old-install'));
  });

  test('resetting iOS boundary resumes per-key cleanup after interruption',
      () async {
    final values = <String, String>{
      'auth_install_boundary_v1':
          '{"v":1,"state":"active","epoch":"old-install"}',
      'auth_access_token': 'old-access',
      'auth_refresh_token': 'old-refresh',
      'auth_device_id': 'old-device',
    };
    var interrupted = false;
    when(() => secureStorage.read(key: any(named: 'key'))).thenAnswer(
      (invocation) async => values[invocation.namedArguments[#key] as String],
    );
    when(
      () => secureStorage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((invocation) async {
      values[invocation.namedArguments[#key] as String] =
          invocation.namedArguments[#value] as String;
    });
    when(() => secureStorage.delete(key: any(named: 'key')))
        .thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      if (key == 'auth_refresh_token' && !interrupted) {
        interrupted = true;
        throw PlatformException(code: 'SIMULATED_PROCESS_DEATH');
      }
      values.remove(key);
    });
    final epochStore = _MemoryInstallEpochStore();
    final storage = SecureTokenStorage(secureStorage, false, epochStore, true);

    await expectLater(
      storage.readTokenSnapshot(),
      throwsA(isA<PlatformException>()),
    );
    final resetting =
        jsonDecode(values['auth_install_boundary_v1']!) as Map<String, dynamic>;
    expect(resetting['state'], 'resetting');
    expect(values, isNot(contains('auth_access_token')));
    expect(values['auth_refresh_token'], 'old-refresh');

    expect((await storage.readTokenSnapshot()).hasCredentials, isFalse);
    final active =
        jsonDecode(values['auth_install_boundary_v1']!) as Map<String, dynamic>;
    expect(active['state'], 'active');
    expect(active['epoch'], epochStore.epoch);
    expect(values, isNot(contains('auth_refresh_token')));
    expect(values, isNot(contains('auth_device_id')));
  });

  test('cached-profile reads are gated by the iOS install boundary', () async {
    final values = <String, String>{
      'auth_install_boundary_v1':
          '{"v":1,"state":"active","epoch":"previous-install"}',
      'auth_cached_profile': '{"id":"stale-profile"}',
      'auth_device_id': 'stale-device',
    };
    _stubMemoryStorage(secureStorage, values);
    final storage = SecureTokenStorage(
      secureStorage,
      false,
      _MemoryInstallEpochStore(),
      true,
    );

    expect(await storage.readCachedProfileJson(), isNull);
    expect(values, isNot(contains('auth_cached_profile')));
    expect(values, isNot(contains('auth_device_id')));
  });

  test('does not erase storage on platforms where recovery is disabled',
      () async {
    when(() => secureStorage.read(key: 'auth_device_id')).thenThrow(
      PlatformException(code: 'KeychainUnavailable'),
    );

    final storage = SecureTokenStorage(secureStorage, false);

    await expectLater(
      storage.readDeviceId(),
      throwsA(isA<PlatformException>()),
    );
    verifyNever(() => secureStorage.deleteAll());
  });

  test('does not erase Android storage for a transient platform failure',
      () async {
    when(() => secureStorage.read(key: 'auth_token_pair_v1'))
        .thenAnswer((_) async => null);
    when(() => secureStorage.read(key: 'auth_access_token')).thenThrow(
      PlatformException(
        code: 'KeyStoreUnavailable',
        message: 'Keystore service is temporarily unavailable',
      ),
    );

    final storage = SecureTokenStorage(secureStorage, true);

    await expectLater(
      storage.readAccessToken(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'KeyStoreUnavailable',
        ),
      ),
    );
    verifyNever(() => secureStorage.deleteAll());
  });

  test('background credential reads never perform Android crypto recovery',
      () async {
    when(() => secureStorage.read(key: 'auth_token_pair_v1')).thenThrow(
      PlatformException(code: 'InvalidKeyException'),
    );
    when(() => secureStorage.deleteAll()).thenAnswer((_) async {});
    final storage = SecureTokenStorage(secureStorage, true);

    await expectLater(
      storage.readTokenSnapshot(),
      throwsA(isA<PlatformException>()),
    );

    verifyNever(() => secureStorage.deleteAll());
  });

  test('failed Android credential reset is attempted only once', () async {
    when(() => secureStorage.read(key: 'auth_token_pair_v1')).thenThrow(
      PlatformException(code: 'BadPaddingException'),
    );
    when(() => secureStorage.deleteAll()).thenAnswer((_) async {});
    final storage = SecureTokenStorage(secureStorage, true);
    final accepted = _session('A', accessVersion: 1, refreshVersion: 1);

    for (var attempt = 0; attempt < 2; attempt += 1) {
      await expectLater(
        storage.writeTokens(
          accessToken: accepted.accessToken!,
          refreshToken: accepted.refreshToken!,
        ),
        throwsA(isA<PlatformException>()),
      );
    }

    verify(() => secureStorage.deleteAll()).called(1);
  });

  test('does not erase Android storage for an unknown Dart exception',
      () async {
    when(() => secureStorage.read(key: 'auth_token_pair_v1'))
        .thenAnswer((_) async => null);
    when(() => secureStorage.read(key: 'auth_access_token'))
        .thenThrow(StateError('temporary channel failure'));

    final storage = SecureTokenStorage(secureStorage, true);

    await expectLater(
      storage.readAccessToken(),
      throwsA(isA<StateError>()),
    );
    verifyNever(() => secureStorage.deleteAll());
  });
}

void _stubMemoryStorage(
  _MockSecureStorage secureStorage,
  Map<String, String> values,
) {
  when(() => secureStorage.read(key: any(named: 'key'))).thenAnswer(
    (invocation) async => values[invocation.namedArguments[#key] as String],
  );
  when(
    () => secureStorage.write(
      key: any(named: 'key'),
      value: any(named: 'value'),
    ),
  ).thenAnswer((invocation) async {
    values[invocation.namedArguments[#key] as String] =
        invocation.namedArguments[#value] as String;
  });
  when(() => secureStorage.delete(key: any(named: 'key'))).thenAnswer(
    (invocation) async {
      values.remove(invocation.namedArguments[#key] as String);
    },
  );
}

void _stubMemoryStorageWithWriteFailure(
  _MockSecureStorage secureStorage,
  Map<String, String> values, {
  required String failingKey,
  required String failingValue,
}) {
  when(() => secureStorage.read(key: any(named: 'key'))).thenAnswer(
    (invocation) async => values[invocation.namedArguments[#key] as String],
  );
  when(
    () => secureStorage.write(
      key: any(named: 'key'),
      value: any(named: 'value'),
    ),
  ).thenAnswer((invocation) async {
    final key = invocation.namedArguments[#key] as String;
    final value = invocation.namedArguments[#value] as String;
    if (key == failingKey && value == failingValue) {
      throw PlatformException(code: 'SIMULATED_PROCESS_DEATH');
    }
    values[key] = value;
  });
  when(() => secureStorage.delete(key: any(named: 'key'))).thenAnswer(
    (invocation) async {
      values.remove(invocation.namedArguments[#key] as String);
    },
  );
}

void _stubMemoryStorageWithDeleteFailure(
  _MockSecureStorage secureStorage,
  Map<String, String> values, {
  required String failingKey,
}) {
  when(() => secureStorage.read(key: any(named: 'key'))).thenAnswer(
    (invocation) async => values[invocation.namedArguments[#key] as String],
  );
  when(
    () => secureStorage.write(
      key: any(named: 'key'),
      value: any(named: 'value'),
    ),
  ).thenAnswer((invocation) async {
    values[invocation.namedArguments[#key] as String] =
        invocation.namedArguments[#value] as String;
  });
  when(() => secureStorage.delete(key: any(named: 'key'))).thenAnswer(
    (invocation) async {
      final key = invocation.namedArguments[#key] as String;
      if (key == failingKey) {
        throw PlatformException(code: 'SIMULATED_PROCESS_DEATH');
      }
      values.remove(key);
    },
  );
}

void _stubMemoryStorageWithOneDeleteFailure(
  _MockSecureStorage secureStorage,
  Map<String, String> values, {
  required String failingKey,
}) {
  var failed = false;
  when(() => secureStorage.read(key: any(named: 'key'))).thenAnswer(
    (invocation) async => values[invocation.namedArguments[#key] as String],
  );
  when(
    () => secureStorage.write(
      key: any(named: 'key'),
      value: any(named: 'value'),
    ),
  ).thenAnswer((invocation) async {
    values[invocation.namedArguments[#key] as String] =
        invocation.namedArguments[#value] as String;
  });
  when(() => secureStorage.delete(key: any(named: 'key'))).thenAnswer(
    (invocation) async {
      final key = invocation.namedArguments[#key] as String;
      if (key == failingKey && !failed) {
        failed = true;
        throw PlatformException(code: 'SIMULATED_PROCESS_DEATH');
      }
      values.remove(key);
    },
  );
}

String _encodedPair(AuthTokenSnapshot snapshot) => jsonEncode({
      'version': 1,
      'accessToken': snapshot.accessToken,
      'refreshToken': snapshot.refreshToken,
    });

AuthTokenSnapshot _session(
  String account, {
  required int accessVersion,
  required int refreshVersion,
}) {
  final subject = 'auth-root-$account';
  final roleAccountId = 'client-account-$account';
  final sid = 'session-$account';
  return AuthTokenSnapshot(
    accessToken: _jwt(
      subject: subject,
      role: 'client',
      roleAccountId: roleAccountId,
      sid: sid,
      marker: 'access-$accessVersion',
    ),
    refreshToken: _jwt(
      subject: subject,
      role: 'client',
      roleAccountId: roleAccountId,
      sid: sid,
      marker: 'refresh-$refreshVersion',
    ),
    storageFormat: AuthTokenStorageFormat.versioned,
  );
}

AuthTokenSnapshot _legacyPair(
  String account, {
  required String role,
}) =>
    AuthTokenSnapshot(
      accessToken: _jwt(
        subject: 'auth-root-$account',
        role: role,
        marker: 'legacy-access',
      ),
      refreshToken: _jwt(
        subject: 'auth-root-$account',
        role: role,
        marker: 'legacy-refresh',
      ),
      storageFormat: AuthTokenStorageFormat.legacy,
    );

AuthTokenSnapshot _interruptedUpgrade(
  String account, {
  required String role,
  required String sid,
}) =>
    AuthTokenSnapshot(
      accessToken: _jwt(
        subject: 'auth-root-$account',
        role: role,
        sid: sid,
        includeRoleAccountId: false,
        marker: 'migrated-access',
      ),
      refreshToken: _jwt(
        subject: 'auth-root-$account',
        role: role,
        marker: 'legacy-refresh',
      ),
      storageFormat: AuthTokenStorageFormat.legacy,
    );

AuthTokenSnapshot _identityPair({
  required String subject,
  required String role,
  required String sid,
  String? roleAccountId,
}) =>
    AuthTokenSnapshot(
      accessToken: _jwt(
        subject: subject,
        role: role,
        roleAccountId: roleAccountId,
        sid: sid,
        marker: 'returned-access',
      ),
      refreshToken: _jwt(
        subject: subject,
        role: role,
        roleAccountId: roleAccountId,
        sid: sid,
        marker: 'returned-refresh',
      ),
      storageFormat: AuthTokenStorageFormat.versioned,
    );

AuthTokenSnapshot _roleAccountUpgrade(
  String account, {
  required bool accessHasRoleAccount,
  required bool refreshHasRoleAccount,
}) =>
    AuthTokenSnapshot(
      accessToken: _jwt(
        subject: 'auth-root-$account',
        role: 'client',
        roleAccountId: 'client-account-$account',
        sid: 'session-$account',
        includeRoleAccountId: accessHasRoleAccount,
        marker: 'legacy-access',
      ),
      refreshToken: _jwt(
        subject: 'auth-root-$account',
        role: 'client',
        roleAccountId: 'client-account-$account',
        sid: 'session-$account',
        includeRoleAccountId: refreshHasRoleAccount,
        marker: 'legacy-refresh',
      ),
      storageFormat: AuthTokenStorageFormat.legacy,
    );

String _jwt({
  required String subject,
  required String role,
  String? roleAccountId,
  String? sid,
  bool includeRoleAccountId = true,
  required String marker,
}) {
  final claims = <String, dynamic>{'sub': subject, 'role': role};
  if (sid != null) claims['sid'] = sid;
  if (sid != null && includeRoleAccountId) {
    claims['roleAccountId'] = roleAccountId ?? '$role-account-for-$subject';
  }
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode(claims),
        ),
      )
      .replaceAll('=', '');
  return 'e30.$payload.$marker';
}

import 'dart:async';
import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockTokenStorage extends Mock implements TokenStorage {}

class _MockTokenRefresher extends Mock implements TokenRefresher {}

void main() {
  const config = ApiConfig(baseUrl: 'http://127.0.0.1:1/v1');

  for (final transport in <({
    String name,
    Object Function(TokenStorage, TokenRefresher) create,
    Future<void> Function(Object) connect,
    AuthSessionIdentity? Function(Object) owner,
    void Function(Object) dispose,
  })>[
    (
      name: 'main',
      create: (storage, refresher) => SocketService(
            config: config,
            tokenStorage: storage,
            tokenRefresher: refresher,
          ),
      connect: (transport) => (transport as SocketService).connect(),
      owner: (transport) => (transport as SocketService).socketOwnerForTesting,
      dispose: (transport) => (transport as SocketService).dispose(),
    ),
    (
      name: 'chat',
      create: (storage, refresher) => ChatRealtime(
            config: config,
            tokenStorage: storage,
            tokenRefresher: refresher,
          ),
      connect: (transport) => (transport as ChatRealtime).connect(),
      owner: (transport) => (transport as ChatRealtime).socketOwnerForTesting,
      dispose: (transport) => (transport as ChatRealtime).dispose(),
    ),
    (
      name: 'call',
      create: (storage, refresher) => AppCallSocketService(
            config: config,
            tokenStorage: storage,
            tokenRefresher: refresher,
          ),
      connect: (transport) => (transport as AppCallSocketService).connect(),
      owner: (transport) =>
          (transport as AppCallSocketService).socketOwnerForTesting,
      dispose: (transport) => (transport as AppCallSocketService).dispose(),
    ),
  ]) {
    test('${transport.name} does not create A socket after B replaces storage',
        () async {
      final storage = _MockTokenStorage();
      final refresher = _MockTokenRefresher();
      final firstRead = Completer<AuthTokenSnapshot>();
      var reads = 0;
      when(() => storage.readTokenSnapshot()).thenAnswer((_) {
        reads += 1;
        return reads == 1 ? firstRead.future : Future.value(_sessionB);
      });
      final subject = transport.create(storage, refresher);

      final connecting = transport.connect(subject);
      firstRead.complete(_sessionA);
      await connecting;

      expect(transport.owner(subject), isNull);
      transport.dispose(subject);
    });

    test('${transport.name} dispose wins over a pending A token read',
        () async {
      final storage = _MockTokenStorage();
      final refresher = _MockTokenRefresher();
      final firstRead = Completer<AuthTokenSnapshot>();
      when(() => storage.readTokenSnapshot())
          .thenAnswer((_) => firstRead.future);
      final subject = transport.create(storage, refresher);

      final connecting = transport.connect(subject);
      transport.dispose(subject);
      firstRead.complete(_sessionA);
      await connecting;

      expect(transport.owner(subject), isNull);
    });
  }
}

final _sessionA = _session('account-A', 'session-A');
final _sessionB = _session('account-B', 'session-B');

AuthTokenSnapshot _session(String account, String sid) => AuthTokenSnapshot(
      accessToken: _jwt(account, sid, 'access'),
      refreshToken: _jwt(account, sid, 'refresh'),
      storageFormat: AuthTokenStorageFormat.versioned,
    );

String _jwt(String account, String sid, String marker) {
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'sub': 'root-$account',
            'role': 'client',
            'roleAccountId': account,
            'sid': sid,
            'exp': 4102444800,
          }),
        ),
      )
      .replaceAll('=', '');
  return 'e30.$payload.$marker';
}

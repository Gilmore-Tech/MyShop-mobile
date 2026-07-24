import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/features/auth/data/auth_repository.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockTokenStorage extends Mock implements TokenStorage {}

class _MockDeviceIdProvider extends Mock implements DeviceIdProvider {}

void main() {
  late _MockAuthService service;
  late _MockTokenStorage storage;
  late ClientAuthRepository repository;

  setUp(() {
    service = _MockAuthService();
    storage = _MockTokenStorage();
    repository = ClientAuthRepository(
      service: service,
      tokenStorage: storage,
      deviceIdProvider: _MockDeviceIdProvider(),
    );
  });

  test('restores a cached client profile without requesting another OTP',
      () async {
    when(() => storage.readAccessToken()).thenAnswer((_) async => 'access');
    when(() => storage.readCachedProfileJson())
        .thenAnswer((_) async => jsonEncode(_profileJson));

    final profile = await repository.bootstrap();

    expect(profile?.id, 'user-1');
    expect(profile?.client?.id, 'client-1');
    verifyNever(() => service.getMe());
    verifyNever(() => service.getMeWithRaw());
    verifyNever(() => storage.clearTokens());
  });

  test('successful profile reads refresh the durable local cache', () async {
    final profile = UserProfile.fromJson(_profileJson);
    when(() => service.getMeWithRaw()).thenAnswer(
      (_) async => (profile: profile, raw: _profileJson),
    );
    when(() => storage.writeCachedProfileJson(any())).thenAnswer((_) async {});

    final result = await repository.fetchProfile();

    expect(result.id, 'user-1');
    final captured =
        verify(() => storage.writeCachedProfileJson(captureAny())).captured;
    expect(jsonDecode(captured.single as String), _profileJson);
  });
}

final Map<String, dynamic> _profileJson = {
  'id': 'user-1',
  'phone': '+233241234567',
  'fullName': 'Client User',
  'languagePref': 'en',
  'status': 'active',
  'createdAt': '2026-01-01T00:00:00.000Z',
  'updatedAt': '2026-07-24T00:00:00.000Z',
  'client': {
    'id': 'client-1',
    'ghanaCardVerified': false,
    'kycStatus': 'not_started',
    'languagePref': 'en',
  },
};

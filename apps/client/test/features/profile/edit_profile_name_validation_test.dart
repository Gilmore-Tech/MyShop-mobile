import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/features/auth/data/auth_repository.dart';
import 'package:myshop_client/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_client/src/features/profile/providers/edit_profile_provider.dart';
import 'package:shared_ui/shared_ui.dart';

class _MockTokenStorage extends Mock implements TokenStorage {}

ClientAuthRepository _repository() {
  final storage = _MockTokenStorage();
  return ClientAuthRepository(
    service: MockAuthService(),
    tokenStorage: storage,
    deviceIdProvider: DeviceIdProvider(storage),
  );
}

const _profile = UserProfile(
  id: 'private-auth-id',
  phone: '+233241234567',
  fullName: 'Ama Mensah',
  languagePref: 'en',
  status: 'active',
  createdAt: '2026-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
  client: ClientProfile(
    id: 'client-role-id',
    legalName: 'Ama Mensah',
    languagePref: 'en',
    ghanaCardVerified: false,
    kycStatus: 'not_started',
  ),
);

class _RecordingClientAuthController extends ClientAuthController {
  _RecordingClientAuthController() : super(_repository()) {
    state = const AuthAuthenticated(_profile);
  }

  int updateCalls = 0;
  UpdateProfileRequest? lastUpdateRequest;

  @override
  Future<String?> updateProfile(UpdateProfileRequest request) async {
    updateCalls += 1;
    lastUpdateRequest = request;
    return null;
  }
}

void main() {
  test('invalid client profile name blocks the update API', () async {
    final auth = _RecordingClientAuthController();
    final notifier = EditProfileNotifier(auth);
    addTearDown(notifier.dispose);
    addTearDown(auth.dispose);

    for (final invalidName in const [
      'Ama123',
      'Ama😀',
      'Am\uFE0E',
      'Am\uFE0F',
      '\tAma Mensah\n',
    ]) {
      notifier.updateFullName(invalidName);

      expect(
        notifier.state.nameError,
        Validators.invalidFullNameMessage,
        reason: invalidName,
      );
      expect(notifier.state.canSave, isFalse, reason: invalidName);
      await notifier.saveChanges();
      expect(auth.updateCalls, 0, reason: invalidName);
    }
  });

  test('client profile state accepts approved international names', () {
    for (final validName in const [
      'Ɛsi Ɔfori',
      'Élodie',
      'E\u0301lodie',
      'O’Connor',
      'NʼDour',
      'Osei-Tutu',
      '李小龙',
    ]) {
      final state = EditProfileState(fullName: validName);
      expect(state.nameError, isNull, reason: validName);
      expect(state.canSave, isTrue, reason: validName);
    }
  });

  test('valid Unicode client name is normalized and sent once', () async {
    final auth = _RecordingClientAuthController();
    final notifier = EditProfileNotifier(auth);
    addTearDown(notifier.dispose);
    addTearDown(auth.dispose);

    notifier.updateFullName('  Ɛsi Ɔfori  ');
    expect(notifier.state.nameError, isNull);
    expect(notifier.state.canSave, isTrue);

    await notifier.saveChanges();

    expect(auth.updateCalls, 1);
    expect(auth.lastUpdateRequest?.fullName, 'Ɛsi Ɔfori');
  });
}

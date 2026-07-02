import 'package:api_client/api_client.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockTokenStorage extends Mock implements TokenStorage {}

void main() {
  test('keeps login usable when device-id persistence is unavailable',
      () async {
    final storage = _MockTokenStorage();
    when(() => storage.readDeviceId()).thenThrow(StateError('unreadable'));
    when(() => storage.writeDeviceId(any()))
        .thenThrow(StateError('unwritable'));

    final provider = DeviceIdProvider(storage);
    final first = await provider.ensureDeviceId();
    final second = await provider.ensureDeviceId();

    expect(first, isNotEmpty);
    expect(second, first);
    verify(() => storage.readDeviceId()).called(1);
    verify(() => storage.writeDeviceId(first)).called(1);
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:myshop_provider/src/core/providers/provider_location_session_provider.dart';

void main() {
  const epoch = '60000000-0000-4000-8000-000000000006';

  test('installs a server epoch and reserves monotonic sequences', () {
    final controller = ProviderLocationSessionController();

    controller.install(epoch, 7);

    expect(controller.nextSequence(), 8);
    expect(controller.nextSequence(), 9);
    expect(controller.state?.onlineSessionId, epoch);
    expect(controller.state?.lastSequence, 9);
  });

  test('an older response for the same epoch cannot rewind reservations', () {
    final controller = ProviderLocationSessionController()..install(epoch, 10);

    controller.install(epoch, 4);

    expect(controller.nextSequence(), 11);
  });

  test('a new server epoch replaces the previous sequence authority', () {
    final controller = ProviderLocationSessionController()..install(epoch, 10);

    controller.install('70000000-0000-4000-8000-000000000007', 0);

    expect(controller.nextSequence(), 1);
  });

  test('invalid and incomplete responses fail closed and clear authority', () {
    final controller = ProviderLocationSessionController()..install(epoch, 10);

    expect(
      () => controller.installResponse(<String, dynamic>{
        'onlineSessionId': epoch,
      }),
      throwsFormatException,
    );
    expect(controller.state, isNull);

    expect(
      () => controller.install('', 0),
      throwsFormatException,
    );
    expect(controller.state, isNull);
  });

  test('sequence exhaustion clears the epoch instead of wrapping', () {
    final controller = ProviderLocationSessionController()
      ..install(epoch, providerLocationSequenceMax);

    expect(controller.nextSequence, throwsStateError);
    expect(controller.state, isNull);
  });
}

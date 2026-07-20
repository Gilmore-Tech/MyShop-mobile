import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_provider/src/core/providers/availability_controller.dart';
import 'package:myshop_provider/src/core/providers/provider_location_session_provider.dart';
import 'package:myshop_provider/src/core/providers/provider_status_provider.dart';
import 'package:myshop_provider/src/core/providers/socket_provider.dart';
import 'package:myshop_provider/src/features/auth/providers/current_user_provider.dart';
import 'package:myshop_provider/src/features/driver_home/providers/driver_location_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';

class _MockSocketService extends Mock implements SocketService {}

Position _position() => Position(
      latitude: 6.6885,
      longitude: -1.6244,
      timestamp: DateTime.now().toUtc(),
      accuracy: 8,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  test('cached Online fix is emitted only after bridge initialization',
      () async {
    final socket = _MockSocketService();
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(
          const AuthUser(
            id: 'driver-user-1',
            phone: '+233241234567',
            fullName: 'Driver One',
            role: AuthRole.driver,
          ),
        ),
        socketServiceProvider.overrideWithValue(socket),
        driverLocationStreamProvider.overrideWith(
          (_) => const Stream<Position>.empty(),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(providerTypeProvider.notifier).state = ProviderType.driver;
    container.read(providerStatusProvider.notifier).goOnline();
    container.read(socketConnectedProvider.notifier).state = true;
    container
        .read(providerLocationSessionProvider.notifier)
        .install('11111111-1111-4111-8111-111111111111', 0);
    container.read(lastKnownPositionProvider.notifier).state = _position();

    expect(
      () => container.read(locationSocketBridgeProvider),
      returnsNormally,
    );
    // Reserving the first sequence synchronously here is the Riverpod
    // initialization violation reproduced by the device log.
    expect(container.read(providerLocationSessionProvider)?.lastSequence, 0);

    await Future<void>.delayed(Duration.zero);

    expect(container.read(providerLocationSessionProvider)?.lastSequence, 1);
    final payload = verify(
      () => socket.emit('driver:location:update', captureAny()),
    ).captured.single as Map<dynamic, dynamic>;
    expect(payload['sampleSequence'], 1);
    expect(payload['latitude'], 6.6885);
    expect(payload['longitude'], -1.6244);
  });
}

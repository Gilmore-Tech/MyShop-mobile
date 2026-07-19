import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/core/providers/availability_controller.dart';
import 'package:myshop_provider/src/core/providers/provider_online_intent.dart';
import 'package:myshop_provider/src/core/providers/provider_status_provider.dart';
import 'package:myshop_provider/src/core/providers/location_degradation_provider.dart';

class _FakeAvailabilityService extends ProviderAvailabilityService {
  _FakeAvailabilityService() : super(Dio());

  Object? failure;
  int calls = 0;
  ProviderAvailabilitySnapshot? current;

  @override
  Future<ProviderAvailabilitySnapshot> getMyAvailability() async {
    return current ??
        ProviderAvailabilitySnapshot(
          role: ProviderAvailabilityRole.artisan,
          providerId: 'artisan-1',
          status: ProviderAvailabilityStatus.offline,
          activeRideId: null,
          activeJobId: null,
          lastSeenAt: null,
          selectedVehicleId: null,
          locationHealth: ProviderLocationHealth.healthy,
          locationRecoveryRequired: false,
          locationDegradedAt: null,
          locationDegradedReason: null,
          locationDegradedEscalatedAt: null,
        );
  }

  @override
  Future<ProviderAvailabilitySnapshot> setMyAvailability({
    required ProviderAvailabilityStatus status,
    String? vehicleId,
  }) async {
    calls += 1;
    if (failure case final Object error) throw error;
    return ProviderAvailabilitySnapshot(
      role: ProviderAvailabilityRole.driver,
      providerId: 'driver-1',
      status: status,
      activeRideId: null,
      activeJobId: null,
      lastSeenAt: null,
      selectedVehicleId: null,
      locationHealth: ProviderLocationHealth.healthy,
      locationRecoveryRequired: false,
      locationDegradedAt: null,
      locationDegradedReason: null,
      locationDegradedEscalatedAt: null,
    );
  }
}

class _FakeLocationService extends LocationService {
  _FakeLocationService() : super(Dio());

  LocationUnavailableReason? reportedReason;

  @override
  Future<Map<String, dynamic>> reportUnavailable(
    LocationUnavailableReason reason,
  ) async {
    reportedReason = reason;
    return <String, dynamic>{};
  }
}

ProviderContainer _container(
  _FakeAvailabilityService service, {
  _FakeLocationService? location,
}) =>
    ProviderContainer(
      overrides: [
        providerAvailabilityServiceProvider.overrideWithValue(service),
        currentProviderOnlineIntentIdentityProvider.overrideWith((_) => null),
        if (location != null)
          locationServiceProvider.overrideWithValue(location),
      ],
    );

void main() {
  test('changes local state only after authoritative no-GPS Offline succeeds',
      () async {
    final service = _FakeAvailabilityService();
    final container = _container(service);
    addTearDown(container.dispose);
    container.read(providerStatusProvider.notifier).goOnline();

    final error =
        await container.read(availabilityControllerProvider).goOffline();

    expect(error, isNull);
    expect(service.calls, 1);
    expect(container.read(providerStatusProvider), DriverStatus.offline);
  });

  test('keeps local Online state when the server cannot confirm Offline',
      () async {
    final service = _FakeAvailabilityService()
      ..failure = const ApiException(
        message: 'raw backend detail must not be shown',
        errorCode: 'TOGGLE_LOCKED_ACTIVE_RIDE',
      );
    final container = _container(service);
    addTearDown(container.dispose);
    container.read(providerStatusProvider.notifier).goOnline();

    final error =
        await container.read(availabilityControllerProvider).goOffline();

    expect(error, "You can't go offline while a ride is active.");
    expect(container.read(providerStatusProvider), DriverStatus.online);
  });

  test('reports location loss without forcing active work offline', () async {
    final service = _FakeAvailabilityService()
      ..current = ProviderAvailabilitySnapshot(
        role: ProviderAvailabilityRole.artisan,
        providerId: 'artisan-1',
        status: ProviderAvailabilityStatus.online,
        activeRideId: null,
        activeJobId: 'job-1',
        lastSeenAt: null,
        selectedVehicleId: null,
        locationHealth: ProviderLocationHealth.degraded,
        locationRecoveryRequired: true,
        locationDegradedAt: DateTime.utc(2026, 7, 18, 12),
        locationDegradedReason: 'permission_lost',
        locationDegradedEscalatedAt: null,
      );
    final location = _FakeLocationService();
    final container = _container(service, location: location);
    addTearDown(container.dispose);
    container.read(providerStatusProvider.notifier).setBusy();

    await container
        .read(availabilityControllerProvider)
        .reportLocationUnavailable(LocationUnavailableReason.permissionLost);

    expect(location.reportedReason, LocationUnavailableReason.permissionLost);
    expect(container.read(providerStatusProvider), DriverStatus.busy);
    expect(
      container.read(providerLocationDegradationProvider).isDegraded,
      isTrue,
    );
  });
}

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/core/providers/availability_controller.dart';
import 'package:myshop_provider/src/core/providers/provider_online_intent.dart';
import 'package:myshop_provider/src/core/providers/provider_status_provider.dart';
import 'package:myshop_provider/src/core/providers/location_degradation_provider.dart';
import 'package:myshop_provider/src/core/providers/provider_location_session_provider.dart';
import 'package:myshop_provider/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_provider/src/features/driver_home/providers/driver_location_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';

class _FakeAvailabilityService extends ProviderAvailabilityService {
  _FakeAvailabilityService() : super(Dio());

  Object? failure;
  int calls = 0;
  ProviderAvailabilitySnapshot? current;
  Completer<ProviderAvailabilitySnapshot>? pending;
  String? expectedProviderId;
  String? expectedOnlineSessionId;
  ProviderAvailabilityRole responseRole = ProviderAvailabilityRole.driver;
  String responseProviderId = 'driver-1';

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
    String? expectedProviderId,
    String? expectedOnlineSessionId,
  }) async {
    calls += 1;
    this.expectedProviderId = expectedProviderId;
    this.expectedOnlineSessionId = expectedOnlineSessionId;
    if (failure case final Object error) throw error;
    final pendingResponse = pending;
    if (pendingResponse != null) return pendingResponse.future;
    return ProviderAvailabilitySnapshot(
      role: responseRole,
      providerId: responseProviderId,
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

class _FakeOnlineIntentStore implements ProviderOnlineIntentStore {
  bool shouldBeOnline = true;
  Completer<void>? blockedFalseWrite;
  Completer<void>? falseWriteStarted;
  final writes = <bool>[];

  @override
  Future<bool> read(ProviderOnlineIntentIdentity identity) async =>
      shouldBeOnline;

  @override
  Future<void> write(
    ProviderOnlineIntentIdentity identity, {
    required bool shouldBeOnline,
  }) async {
    writes.add(shouldBeOnline);
    if (!shouldBeOnline && blockedFalseWrite != null) {
      falseWriteStarted?.complete();
      await blockedFalseWrite!.future;
    }
    this.shouldBeOnline = shouldBeOnline;
  }
}

class _FakeLocationService extends LocationService {
  _FakeLocationService() : super(Dio());

  LocationUnavailableReason? reportedReason;
  Position? driverPosition;
  int? driverSampleSequence;

  @override
  Future<Map<String, dynamic>> reportUnavailable(
    LocationUnavailableReason reason,
  ) async {
    reportedReason = reason;
    return <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> updateDriverLocation({
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime recordedAt,
    String? onlineSessionId,
    int? sampleSequence,
    String? vehicleId,
    String status = 'online',
  }) async {
    driverPosition = _position(recordedAt);
    driverSampleSequence = sampleSequence;
    return <String, dynamic>{};
  }
}

Position _position(DateTime timestamp) => Position(
      latitude: 6.6885,
      longitude: -1.6244,
      timestamp: timestamp,
      accuracy: 8,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

const _driverEpochA = '11111111-1111-4111-8111-111111111111';
const _driverEpochB = '22222222-2222-4222-8222-222222222222';

ProviderContainer _recoveryContainer(
  _FakeAvailabilityService service, {
  required StateProvider<AuthSessionIdentity?> authState,
  required ProviderOnlineIntentIdentity intentIdentity,
  required _FakeOnlineIntentStore intentStore,
}) {
  return ProviderContainer(
    overrides: [
      providerAvailabilityServiceProvider.overrideWithValue(service),
      currentAuthSessionIdentityProvider.overrideWith(
        (ref) => ref.watch(authState),
      ),
      currentProviderOnlineIntentIdentityProvider.overrideWith(
        (_) => intentIdentity,
      ),
      providerOnlineIntentStoreProvider.overrideWithValue(intentStore),
    ],
  );
}

ProviderRecoveryOfflineAuthority _recoveryAuthority(
  ProviderContainer container,
  AuthSessionIdentity authSession,
  String onlineSessionId,
) {
  return ProviderRecoveryOfflineAuthority(
    authSession: authSession,
    onlineSessionId: onlineSessionId,
    transitionRevision:
        container.read(providerStatusProvider.notifier).transitionRevision,
  );
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

  for (final fixture in <({String role, String providerId})>[
    (role: 'driver', providerId: 'driver-1'),
    (role: 'artisan', providerId: 'artisan-1'),
  ]) {
    test('${fixture.role} recovery Offline uses exact authority and converges',
        () async {
      final authSession = AuthSessionIdentity(
        subject: 'private-1',
        role: fixture.role,
        roleAccountId: fixture.providerId,
        sessionId: 'auth-session-a',
      );
      final authState = StateProvider<AuthSessionIdentity?>(
        (_) => authSession,
      );
      final intentIdentity = ProviderOnlineIntentIdentity(
        role: fixture.role == 'driver'
            ? ProviderOnlineIntentRole.driver
            : ProviderOnlineIntentRole.artisan,
        roleAccountId: fixture.providerId,
      );
      final intentStore = _FakeOnlineIntentStore();
      final service = _FakeAvailabilityService()
        ..responseRole = fixture.role == 'driver'
            ? ProviderAvailabilityRole.driver
            : ProviderAvailabilityRole.artisan
        ..responseProviderId = fixture.providerId;
      final container = _recoveryContainer(
        service,
        authState: authState,
        intentIdentity: intentIdentity,
        intentStore: intentStore,
      );
      addTearDown(container.dispose);
      container.read(providerStatusProvider.notifier).goOnline();
      container
          .read(providerLocationSessionProvider.notifier)
          .install(_driverEpochA, 0);

      final result = await container
          .read(availabilityControllerProvider)
          .goOfflineIfCurrent(
            _recoveryAuthority(container, authSession, _driverEpochA),
          );

      expect(
        result.disposition,
        ProviderRecoveryOfflineDisposition.confirmed,
      );
      expect(service.expectedProviderId, fixture.providerId);
      expect(service.expectedOnlineSessionId, _driverEpochA);
      expect(intentStore.writes, <bool>[false]);
      expect(intentStore.shouldBeOnline, isFalse);
      expect(container.read(providerStatusProvider), DriverStatus.offline);
      expect(container.read(providerLocationSessionProvider), isNull);
    });

    test('${fixture.role} recovery mismatch leaves all local authority intact',
        () async {
      final authSession = AuthSessionIdentity(
        subject: 'private-1',
        role: fixture.role,
        roleAccountId: fixture.providerId,
        sessionId: 'auth-session-a',
      );
      final authState = StateProvider<AuthSessionIdentity?>(
        (_) => authSession,
      );
      final intentIdentity = ProviderOnlineIntentIdentity(
        role: fixture.role == 'driver'
            ? ProviderOnlineIntentRole.driver
            : ProviderOnlineIntentRole.artisan,
        roleAccountId: fixture.providerId,
      );
      final intentStore = _FakeOnlineIntentStore();
      final service = _FakeAvailabilityService()
        ..failure = const ApiException(
          message: 'The Online authority changed.',
          statusCode: 409,
          errorCode: 'PROVIDER_AVAILABILITY_AUTHORITY_CHANGED',
        );
      final container = _recoveryContainer(
        service,
        authState: authState,
        intentIdentity: intentIdentity,
        intentStore: intentStore,
      );
      addTearDown(container.dispose);
      container.read(providerStatusProvider.notifier).goOnline();
      container
          .read(providerLocationSessionProvider.notifier)
          .install(_driverEpochA, 4);

      final result = await container
          .read(availabilityControllerProvider)
          .goOfflineIfCurrent(
            _recoveryAuthority(container, authSession, _driverEpochA),
          );

      expect(
        result.disposition,
        ProviderRecoveryOfflineDisposition.authorityChanged,
      );
      expect(intentStore.writes, isEmpty);
      expect(intentStore.shouldBeOnline, isTrue);
      expect(container.read(providerStatusProvider), DriverStatus.online);
      expect(
        container.read(providerLocationSessionProvider)?.onlineSessionId,
        _driverEpochA,
      );
      expect(container.read(providerLocationSessionProvider)?.lastSequence, 4);
    });
  }

  test('delayed epoch-A CAS cannot demote replacement epoch B or SID',
      () async {
    const authA = AuthSessionIdentity(
      subject: 'private-1',
      role: 'driver',
      roleAccountId: 'driver-1',
      sessionId: 'auth-session-a',
    );
    const authB = AuthSessionIdentity(
      subject: 'private-1',
      role: 'driver',
      roleAccountId: 'driver-1',
      sessionId: 'auth-session-b',
    );
    final authState = StateProvider<AuthSessionIdentity?>((_) => authA);
    const intentIdentity = ProviderOnlineIntentIdentity(
      role: ProviderOnlineIntentRole.driver,
      roleAccountId: 'driver-1',
    );
    final intentStore = _FakeOnlineIntentStore();
    final pending = Completer<ProviderAvailabilitySnapshot>();
    final service = _FakeAvailabilityService()..pending = pending;
    final container = _recoveryContainer(
      service,
      authState: authState,
      intentIdentity: intentIdentity,
      intentStore: intentStore,
    );
    addTearDown(container.dispose);
    container.read(providerStatusProvider.notifier).goOnline();
    container
        .read(providerLocationSessionProvider.notifier)
        .install(_driverEpochA, 1);

    final resultFuture =
        container.read(availabilityControllerProvider).goOfflineIfCurrent(
              _recoveryAuthority(container, authA, _driverEpochA),
            );
    await Future<void>.delayed(Duration.zero);
    expect(service.calls, 1);

    container.read(authState.notifier).state = authB;
    container
        .read(providerLocationSessionProvider.notifier)
        .install(_driverEpochB, 7);
    pending.complete(
      ProviderAvailabilitySnapshot(
        role: ProviderAvailabilityRole.driver,
        providerId: 'driver-1',
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
      ),
    );
    final result = await resultFuture;

    expect(
      result.disposition,
      ProviderRecoveryOfflineDisposition.authorityChanged,
    );
    expect(intentStore.writes, isEmpty);
    expect(container.read(providerStatusProvider), DriverStatus.online);
    expect(
      container.read(providerLocationSessionProvider)?.onlineSessionId,
      _driverEpochB,
    );
    expect(container.read(providerLocationSessionProvider)?.lastSequence, 7);
  });

  for (final fixture in <({String role, String providerId})>[
    (role: 'driver', providerId: 'driver-1'),
    (role: 'artisan', providerId: 'artisan-1'),
  ]) {
    test(
        '${fixture.role} busy replacement installed during intent clear is preserved',
        () async {
      final authA = AuthSessionIdentity(
        subject: 'private-1',
        role: fixture.role,
        roleAccountId: fixture.providerId,
        sessionId: 'auth-session-a',
      );
      final authB = AuthSessionIdentity(
        subject: 'private-1',
        role: fixture.role,
        roleAccountId: fixture.providerId,
        sessionId: 'auth-session-b',
      );
      final authState = StateProvider<AuthSessionIdentity?>((_) => authA);
      final intentIdentity = ProviderOnlineIntentIdentity(
        role: fixture.role == 'driver'
            ? ProviderOnlineIntentRole.driver
            : ProviderOnlineIntentRole.artisan,
        roleAccountId: fixture.providerId,
      );
      final blockedWrite = Completer<void>();
      final writeStarted = Completer<void>();
      final intentStore = _FakeOnlineIntentStore()
        ..blockedFalseWrite = blockedWrite
        ..falseWriteStarted = writeStarted;
      final service = _FakeAvailabilityService()
        ..responseRole = fixture.role == 'driver'
            ? ProviderAvailabilityRole.driver
            : ProviderAvailabilityRole.artisan
        ..responseProviderId = fixture.providerId;
      final container = _recoveryContainer(
        service,
        authState: authState,
        intentIdentity: intentIdentity,
        intentStore: intentStore,
      );
      addTearDown(container.dispose);
      container.read(providerStatusProvider.notifier).goOnline();
      container
          .read(providerLocationSessionProvider.notifier)
          .install(_driverEpochA, 1);

      final resultFuture =
          container.read(availabilityControllerProvider).goOfflineIfCurrent(
                _recoveryAuthority(container, authA, _driverEpochA),
              );
      await writeStarted.future;
      expect(container.read(providerStatusProvider), DriverStatus.offline);
      expect(container.read(providerLocationSessionProvider), isNull);

      container.read(authState.notifier).state = authB;
      container.read(providerStatusProvider.notifier).setBusy();
      container
          .read(providerLocationSessionProvider.notifier)
          .install(_driverEpochB, 9);
      blockedWrite.complete();
      final result = await resultFuture;

      expect(
        result.disposition,
        ProviderRecoveryOfflineDisposition.authorityChanged,
      );
      expect(intentStore.writes, <bool>[false, true]);
      expect(intentStore.shouldBeOnline, isTrue);
      expect(container.read(providerStatusProvider), DriverStatus.busy);
      expect(
        container.read(providerLocationSessionProvider)?.onlineSessionId,
        _driverEpochB,
      );
      expect(
        container.read(providerLocationSessionProvider)?.lastSequence,
        9,
      );
    });
  }

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

  test('background transition replaces a stale cached fix before heartbeat',
      () async {
    clearOnlineLocationPostAt();
    final service = _FakeAvailabilityService();
    final location = _FakeLocationService();
    final fresh = _position(DateTime.now().toUtc());
    final container = ProviderContainer(
      overrides: [
        providerAvailabilityServiceProvider.overrideWithValue(service),
        currentProviderOnlineIntentIdentityProvider.overrideWith((_) => null),
        locationServiceProvider.overrideWithValue(location),
        onlinePositionLoaderProvider.overrideWithValue(() async => fresh),
      ],
    );
    addTearDown(() {
      clearOnlineLocationPostAt();
      container.dispose();
    });
    container.read(providerTypeProvider.notifier).state = ProviderType.driver;
    container.read(providerStatusProvider.notifier).goOnline();
    container.read(lastKnownPositionProvider.notifier).state =
        _position(fresh.timestamp.subtract(const Duration(minutes: 1)));
    container
        .read(providerLocationSessionProvider.notifier)
        .install('11111111-1111-4111-8111-111111111111', 0);

    await container.read(availabilityControllerProvider).refreshHeartbeat();

    expect(location.driverPosition?.timestamp, fresh.timestamp);
    expect(location.driverSampleSequence, 1);
    expect(container.read(lastKnownPositionProvider), same(fresh));
  });
}

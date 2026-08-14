import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/core/providers/availability_reconciliation_controller.dart';
import 'package:myshop_provider/src/core/providers/provider_status_provider.dart';
import 'package:myshop_provider/src/core/providers/location_degradation_provider.dart';
import 'package:myshop_provider/src/core/providers/provider_location_session_provider.dart';
import 'package:myshop_provider/src/core/providers/provider_online_intent.dart';
import 'package:myshop_provider/src/core/services/fcm_service.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';

const _intentIdentity = ProviderOnlineIntentIdentity(
  role: ProviderOnlineIntentRole.artisan,
  roleAccountId: 'provider-1',
);

class _FakeOnlineIntentStore implements ProviderOnlineIntentStore {
  _FakeOnlineIntentStore({this.shouldBeOnline = false});

  bool shouldBeOnline;
  final writes = <bool>[];
  final reads = <ProviderOnlineIntentIdentity>[];

  @override
  Future<bool> read(ProviderOnlineIntentIdentity identity) async {
    reads.add(identity);
    return shouldBeOnline;
  }

  @override
  Future<void> write(
    ProviderOnlineIntentIdentity identity, {
    required bool shouldBeOnline,
  }) async {
    this.shouldBeOnline = shouldBeOnline;
    writes.add(shouldBeOnline);
  }
}

class _FakeProviderAvailabilityService extends ProviderAvailabilityService {
  _FakeProviderAvailabilityService(this.snapshot) : super(Dio());

  ProviderAvailabilitySnapshot snapshot;
  int getCalls = 0;

  @override
  Future<ProviderAvailabilitySnapshot> getMyAvailability() async {
    getCalls += 1;
    return snapshot;
  }
}

class _DelayedProviderAvailabilityService extends ProviderAvailabilityService {
  _DelayedProviderAvailabilityService() : super(Dio());

  final completer = Completer<ProviderAvailabilitySnapshot>();

  @override
  Future<ProviderAvailabilitySnapshot> getMyAvailability() => completer.future;
}

ProviderAvailabilitySnapshot _snapshot({
  ProviderAvailabilityRole role = ProviderAvailabilityRole.artisan,
  String providerId = 'provider-1',
  ProviderAvailabilityStatus status = ProviderAvailabilityStatus.offline,
  String? activeRideId,
  String? activeJobId,
  ProviderLocationHealth locationHealth = ProviderLocationHealth.healthy,
  DateTime? locationDegradedAt,
  String? locationDegradedReason,
  DateTime? locationDegradedEscalatedAt,
  String? onlineSessionId,
  int? lastLocationSequence,
}) {
  return ProviderAvailabilitySnapshot(
    role: role,
    providerId: providerId,
    status: status,
    activeRideId: activeRideId,
    activeJobId: activeJobId,
    lastSeenAt: DateTime.utc(2026, 7, 17),
    selectedVehicleId: null,
    locationHealth: locationHealth,
    locationRecoveryRequired: locationHealth == ProviderLocationHealth.degraded,
    locationDegradedAt: locationDegradedAt,
    locationDegradedReason: locationDegradedReason,
    locationDegradedEscalatedAt: locationDegradedEscalatedAt,
    onlineSessionId: onlineSessionId,
    lastLocationSequence: lastLocationSequence,
  );
}

ProviderContainer _container(
  _FakeProviderAvailabilityService service, {
  _FakeOnlineIntentStore? intentStore,
  bool firebaseReady = true,
  AvailabilityReconciliationActions? actions,
  ProviderType providerType = ProviderType.artisan,
}) {
  final identity = providerType == ProviderType.driver
      ? const ProviderOnlineIntentIdentity(
          role: ProviderOnlineIntentRole.driver,
          roleAccountId: 'driver-1',
        )
      : _intentIdentity;
  return ProviderContainer(
    overrides: [
      providerAvailabilityServiceProvider.overrideWithValue(service),
      currentProviderOnlineIntentIdentityProvider.overrideWith(
        (_) => identity,
      ),
      providerTypeProvider.overrideWith((_) => providerType),
      providerOnlineIntentStoreProvider.overrideWithValue(
        intentStore ?? _FakeOnlineIntentStore(),
      ),
      firebaseReadyProvider.overrideWith((_) => firebaseReady),
      availabilityReconciliationActionsProvider.overrideWithValue(
        actions ??
            AvailabilityReconciliationActions(
              restoreOnline: (_) async => 'Unexpected restore attempt.',
              forceOffline: () async => null,
            ),
      ),
    ],
  );
}

void main() {
  test('authoritative offline demotes an idle local online state', () async {
    final service = _FakeProviderAvailabilityService(_snapshot());
    final container = _container(service);
    addTearDown(container.dispose);
    container.read(providerStatusProvider.notifier).goOnline();

    await container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');

    expect(container.read(providerStatusProvider), DriverStatus.offline);
  });

  test('never changes local busy state', () async {
    final service = _FakeProviderAvailabilityService(_snapshot());
    final container = _container(service);
    addTearDown(container.dispose);
    container.read(providerStatusProvider.notifier).setBusy();

    await container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');

    expect(container.read(providerStatusProvider), DriverStatus.busy);
  });

  test('records degraded active-work authority without demoting local busy',
      () async {
    final service = _FakeProviderAvailabilityService(
      _snapshot(
        activeJobId: 'job-1',
        locationHealth: ProviderLocationHealth.degraded,
        locationDegradedAt: DateTime.utc(2026, 7, 18, 12),
        locationDegradedReason: 'permission_lost',
        locationDegradedEscalatedAt: DateTime.utc(2026, 7, 18, 12, 2),
      ),
    );
    final container = _container(service);
    addTearDown(container.dispose);
    container.read(providerStatusProvider.notifier).setBusy();

    await container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');

    expect(container.read(providerStatusProvider), DriverStatus.busy);
    final degradation = container.read(providerLocationDegradationProvider);
    expect(degradation.isDegraded, isTrue);
    expect(degradation.hasActiveWork, isTrue);
    expect(degradation.isEscalated, isTrue);
  });

  test('server online without durable intent is forced offline', () async {
    final service = _FakeProviderAvailabilityService(
      _snapshot(status: ProviderAvailabilityStatus.online),
    );
    var forcedOffline = 0;
    final container = _container(
      service,
      actions: AvailabilityReconciliationActions(
        restoreOnline: (_) async => 'Unexpected restore attempt.',
        forceOffline: () async {
          forcedOffline += 1;
          return null;
        },
      ),
    );
    addTearDown(container.dispose);

    await container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');

    expect(container.read(providerStatusProvider), DriverStatus.offline);
    expect(forcedOffline, 1);
    expect(container.read(availabilityRestoreNoticeProvider),
        contains('no verified prior'));
  });

  test('cold-start reconciliation restores the exact server location epoch',
      () async {
    const onlineSessionId = '60000000-0000-4000-8000-000000000006';
    final service = _FakeProviderAvailabilityService(
      _snapshot(
        status: ProviderAvailabilityStatus.online,
        onlineSessionId: onlineSessionId,
        lastLocationSequence: 42,
      ),
    );
    final container = _container(
      service,
      intentStore: _FakeOnlineIntentStore(shouldBeOnline: true),
      firebaseReady: false,
    );
    addTearDown(container.dispose);

    await container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');

    expect(
      container.read(providerLocationSessionProvider)?.onlineSessionId,
      onlineSessionId,
    );
    expect(
      container.read(providerLocationSessionProvider)?.lastSequence,
      42,
    );
  });

  test('authoritative Offline reconciliation clears the prior location epoch',
      () async {
    final service = _FakeProviderAvailabilityService(_snapshot());
    final container = _container(service);
    addTearDown(container.dispose);
    container
        .read(providerLocationSessionProvider.notifier)
        .install('60000000-0000-4000-8000-000000000006', 42);
    container.read(providerStatusProvider.notifier).goOnline();

    await container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');

    expect(container.read(providerLocationSessionProvider), isNull);
    expect(container.read(providerStatusProvider), DriverStatus.offline);
  });

  test('active server work is deferred to ride/job recovery', () async {
    final service = _FakeProviderAvailabilityService(
      _snapshot(
        status: ProviderAvailabilityStatus.online,
        activeJobId: 'job-1',
      ),
    );
    final container = _container(service);
    addTearDown(container.dispose);

    await container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');

    expect(container.read(providerStatusProvider), DriverStatus.offline);
  });

  test('role mismatch is ignored without mutating either side', () async {
    final service = _FakeProviderAvailabilityService(
      _snapshot(
        role: ProviderAvailabilityRole.driver,
        status: ProviderAvailabilityStatus.online,
      ),
    );
    final container = _container(service);
    addTearDown(container.dispose);

    await container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');

    expect(container.read(providerStatusProvider), DriverStatus.offline);
  });

  test('exact role-account mismatch is rejected before session installation',
      () async {
    final service = _FakeProviderAvailabilityService(
      _snapshot(
        providerId: 'different-artisan-role',
        status: ProviderAvailabilityStatus.online,
        onlineSessionId: '60000000-0000-4000-8000-000000000006',
        lastLocationSequence: 4,
      ),
    );
    final container = _container(
      service,
      intentStore: _FakeOnlineIntentStore(shouldBeOnline: true),
    );
    addTearDown(container.dispose);

    await container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');

    expect(container.read(providerLocationSessionProvider), isNull);
    expect(container.read(providerStatusProvider), DriverStatus.offline);
    expect(
      container.read(availabilityRestoreNoticeProvider),
      contains('different provider account'),
    );
  });

  test('a newer local transition wins over an in-flight snapshot', () async {
    final service = _DelayedProviderAvailabilityService();
    final container = ProviderContainer(
      overrides: [
        providerAvailabilityServiceProvider.overrideWithValue(service),
        currentProviderOnlineIntentIdentityProvider.overrideWith(
          (_) => _intentIdentity,
        ),
        providerOnlineIntentStoreProvider.overrideWithValue(
          _FakeOnlineIntentStore(),
        ),
        firebaseReadyProvider.overrideWith((_) => true),
        availabilityReconciliationActionsProvider.overrideWithValue(
          AvailabilityReconciliationActions(
            restoreOnline: (_) async => 'Unexpected restore attempt.',
            forceOffline: () async => null,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final status = container.read(providerStatusProvider.notifier);
    status.goOnline();

    final reconciliation = container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');
    status.goOffline();
    status.goOnline();
    service.completer.complete(_snapshot());
    await reconciliation;

    expect(container.read(providerStatusProvider), DriverStatus.online);
  });

  test('durable intent restores only after notification startup', () async {
    final service = _FakeProviderAvailabilityService(
      _snapshot(status: ProviderAvailabilityStatus.online),
    );
    final store = _FakeOnlineIntentStore(shouldBeOnline: true);
    var restores = 0;
    final container = _container(
      service,
      intentStore: store,
      firebaseReady: false,
      actions: AvailabilityReconciliationActions(
        restoreOnline: (_) async {
          restores += 1;
          return null;
        },
        forceOffline: () async => null,
      ),
    );
    addTearDown(container.dispose);

    await container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');

    expect(restores, 0);
    expect(store.shouldBeOnline, isTrue);
    expect(container.read(providerStatusProvider), DriverStatus.offline);
  });

  test('durable intent restores through the selected driver vehicle', () async {
    final service = _FakeProviderAvailabilityService(
      ProviderAvailabilitySnapshot(
        role: ProviderAvailabilityRole.driver,
        providerId: 'driver-1',
        status: ProviderAvailabilityStatus.online,
        activeRideId: null,
        activeJobId: null,
        lastSeenAt: DateTime.utc(2026, 7, 19),
        selectedVehicleId: 'vehicle-1',
        locationHealth: ProviderLocationHealth.healthy,
        locationRecoveryRequired: false,
        locationDegradedAt: null,
        locationDegradedReason: null,
        locationDegradedEscalatedAt: null,
      ),
    );
    final store = _FakeOnlineIntentStore(shouldBeOnline: true);
    String? restoredVehicle;
    late ProviderContainer container;
    container = _container(
      service,
      intentStore: store,
      providerType: ProviderType.driver,
      actions: AvailabilityReconciliationActions(
        restoreOnline: (vehicleId) async {
          restoredVehicle = vehicleId;
          container.read(providerStatusProvider.notifier).goOnline();
          return null;
        },
        forceOffline: () async => null,
      ),
    );
    addTearDown(container.dispose);

    await container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');

    expect(restoredVehicle, 'vehicle-1');
    expect(container.read(providerStatusProvider), DriverStatus.online);
    expect(store.shouldBeOnline, isTrue);
    expect(container.read(availabilityRestoreNoticeProvider), isNull);
  });

  test('driver intent without selected vehicle is consumed and stays offline',
      () async {
    final service = _FakeProviderAvailabilityService(
      _snapshot(
        role: ProviderAvailabilityRole.driver,
        providerId: 'driver-1',
      ),
    );
    final store = _FakeOnlineIntentStore(shouldBeOnline: true);
    var restores = 0;
    var forcedOffline = 0;
    final container = _container(
      service,
      intentStore: store,
      providerType: ProviderType.driver,
      actions: AvailabilityReconciliationActions(
        restoreOnline: (_) async {
          restores += 1;
          return null;
        },
        forceOffline: () async {
          forcedOffline += 1;
          return null;
        },
      ),
    );
    addTearDown(container.dispose);

    await container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');

    expect(restores, 0);
    expect(forcedOffline, 1);
    expect(store.shouldBeOnline, isFalse);
    expect(container.read(providerStatusProvider), DriverStatus.offline);
    expect(
      container.read(availabilityRestoreNoticeProvider),
      'Your previous Online session ended. Tap Go Online and choose the '
      'vehicle you are using for this session.',
    );
  });

  test('failed revalidation consumes intent and confirms backend offline',
      () async {
    final service = _FakeProviderAvailabilityService(
      _snapshot(status: ProviderAvailabilityStatus.offline),
    );
    final store = _FakeOnlineIntentStore(shouldBeOnline: true);
    var forcedOffline = 0;
    final container = _container(
      service,
      intentStore: store,
      actions: AvailabilityReconciliationActions(
        restoreOnline: (_) async =>
            'Your documents need approval before you can go online.',
        forceOffline: () async {
          forcedOffline += 1;
          return null;
        },
      ),
    );
    addTearDown(container.dispose);

    await container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');

    expect(forcedOffline, 1);
    expect(store.shouldBeOnline, isFalse);
    expect(container.read(providerStatusProvider), DriverStatus.offline);
    expect(
      container.read(availabilityRestoreNoticeProvider),
      contains('documents need approval'),
    );
  });

  test('failed backend Offline confirmation is never presented as confirmed',
      () async {
    final service = _FakeProviderAvailabilityService(
      _snapshot(status: ProviderAvailabilityStatus.online),
    );
    final container = _container(
      service,
      actions: AvailabilityReconciliationActions(
        restoreOnline: (_) async => 'Unexpected restore attempt.',
        forceOffline: () async => 'No connection to MyShop.',
      ),
    );
    addTearDown(container.dispose);

    await container
        .read(availabilityReconciliationControllerProvider)
        .reconcile(trigger: 'test');

    expect(
      container.read(availabilityRestoreNoticeProvider),
      contains('could not confirm that you are offline'),
    );
  });
}

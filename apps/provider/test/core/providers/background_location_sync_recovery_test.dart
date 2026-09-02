import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import 'package:myshop_provider/src/core/di/providers.dart';
import 'package:myshop_provider/src/core/providers/availability_controller.dart';
import 'package:myshop_provider/src/core/providers/background_location_sync_provider.dart';
import 'package:myshop_provider/src/core/providers/provider_location_session_provider.dart';
import 'package:myshop_provider/src/core/providers/provider_location_sync_recovery.dart';
import 'package:myshop_provider/src/core/providers/provider_online_intent.dart';
import 'package:myshop_provider/src/core/providers/provider_status_provider.dart';
import 'package:myshop_provider/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_provider/src/features/auth/providers/current_user_provider.dart';
import 'package:myshop_provider/src/features/driver_home/providers/driver_location_provider.dart';
import 'package:myshop_provider/src/features/profile/providers/provider_type_provider.dart';

class _FakeLocationService extends LocationService {
  _FakeLocationService() : super(Dio());

  final outcomes = <Object?>[];
  final batches = <List<DriverLocationSample>>[];
  final sessionIds = <String>[];
  Completer<Map<String, dynamic>>? pending;

  @override
  Future<Map<String, dynamic>> updateDriverLocationBatch({
    required List<DriverLocationSample> samples,
    required String onlineSessionId,
  }) async {
    batches.add(List<DriverLocationSample>.unmodifiable(samples));
    sessionIds.add(onlineSessionId);
    final pendingResponse = pending;
    if (pendingResponse != null) {
      pending = null;
      return pendingResponse.future;
    }
    if (outcomes.isNotEmpty) {
      final outcome = outcomes.removeAt(0);
      if (outcome != null) throw outcome;
    }
    return <String, dynamic>{};
  }
}

class _FakeOnlineIntentStore implements ProviderOnlineIntentStore {
  _FakeOnlineIntentStore() : shouldBeOnline = true;

  bool shouldBeOnline;
  final writes = <bool>[];

  @override
  Future<bool> read(ProviderOnlineIntentIdentity identity) async =>
      shouldBeOnline;

  @override
  Future<void> write(
    ProviderOnlineIntentIdentity identity, {
    required bool shouldBeOnline,
  }) async {
    this.shouldBeOnline = shouldBeOnline;
    writes.add(shouldBeOnline);
  }
}

const _user = AuthUser(
  id: 'driver-1',
  phone: '+233240000001',
  fullName: 'Driver One',
  role: AuthRole.driver,
);

const _authSession = AuthSessionIdentity(
  subject: 'private-user-1',
  role: 'driver',
  roleAccountId: 'driver-1',
  sessionId: 'auth-session-a',
);

const _intentIdentity = ProviderOnlineIntentIdentity(
  role: ProviderOnlineIntentRole.driver,
  roleAccountId: 'driver-1',
);

const _epochA = '11111111-1111-4111-8111-111111111111';
const _epochB = '22222222-2222-4222-8222-222222222222';

ApiException _eligibility(List<String> reasonCodes) => ApiException(
      message: 'Provider is not eligible',
      statusCode: 403,
      errorCode: 'PROVIDER_NOT_ELIGIBLE',
      details: <String, dynamic>{'reasonCodes': reasonCodes},
    );

Position _position(DateTime timestamp, {double latitude = 6.6885}) => Position(
      latitude: latitude,
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

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ProviderContainer _container({
  required Stream<Position> positions,
  required _FakeLocationService location,
  required _FakeOnlineIntentStore intentStore,
  required ProviderLocationRecoveryActions recovery,
  DateTime Function()? now,
}) {
  return ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(_user),
      currentAuthSessionIdentityProvider.overrideWith((_) => _authSession),
      currentProviderOnlineIntentIdentityProvider.overrideWith(
        (_) => _intentIdentity,
      ),
      providerTypeProvider.overrideWith((_) => ProviderType.driver),
      providerOnlineIntentStoreProvider.overrideWithValue(intentStore),
      locationServiceProvider.overrideWithValue(location),
      providerLocationRecoveryActionsProvider.overrideWithValue(recovery),
      if (now != null) providerLocationSyncNowProvider.overrideWithValue(now),
      driverLocationStreamProvider.overrideWith((_) => positions),
    ],
  );
}

void main() {
  setUp(clearOnlineLocationPostAt);
  tearDown(clearOnlineLocationPostAt);

  test(
    'idle nested terminal rejection consumes intent and confirms Offline',
    () async {
      final positions = StreamController<Position>.broadcast();
      final location = _FakeLocationService()
        ..outcomes.add(
          _eligibility(<String>['DRIVER_ONLINE_SESSION_REQUIRED']),
        );
      final intentStore = _FakeOnlineIntentStore();
      late ProviderContainer container;
      var offlineCalls = 0;
      var reconcileCalls = 0;
      container = _container(
        positions: positions.stream,
        location: location,
        intentStore: intentStore,
        recovery: ProviderLocationRecoveryActions(
          forceOffline: (_) async {
            offlineCalls += 1;
            await intentStore.write(_intentIdentity, shouldBeOnline: false);
            container.read(providerStatusProvider.notifier).goOffline();
            container.read(providerLocationSessionProvider.notifier).clear();
            return const ProviderRecoveryOfflineResult.confirmed();
          },
          reconcile: (_) async => reconcileCalls += 1,
        ),
      );
      addTearDown(() async {
        await positions.close();
        container.dispose();
      });
      container.read(providerStatusProvider.notifier).goOnline();
      container
          .read(providerLocationSessionProvider.notifier)
          .install(_epochA, 0);
      container.read(backgroundLocationSyncProvider);

      final timestamp =
          DateTime.now().toUtc().subtract(const Duration(seconds: 8));
      positions.add(_position(timestamp));
      await _settle();
      positions.add(_position(timestamp.add(const Duration(seconds: 1))));
      await _settle();

      expect(location.batches, hasLength(1));
      expect(offlineCalls, 1);
      expect(reconcileCalls, 0);
      expect(intentStore.shouldBeOnline, isFalse);
      expect(intentStore.writes, contains(false));
      expect(container.read(providerStatusProvider), DriverStatus.offline);
      expect(container.read(providerLocationSessionProvider), isNull);
    },
  );

  test('request block retires visual Online state with the exact reason',
      () async {
    final positions = StreamController<Position>.broadcast();
    final location = _FakeLocationService()
      ..outcomes.add(
        const ApiException(
          message: 'raw backend restriction',
          statusCode: 429,
          errorCode: 'PROVIDER_REQUEST_BLOCK',
          details: <String, dynamic>{
            'policyKind': 'offer_response',
            'blockedUntil': '2099-09-02T22:15:00.000Z',
            'retryAfterSeconds': 900,
          },
        ),
      );
    final intentStore = _FakeOnlineIntentStore();
    late ProviderContainer container;
    var offlineCalls = 0;
    container = _container(
      positions: positions.stream,
      location: location,
      intentStore: intentStore,
      recovery: ProviderLocationRecoveryActions(
        forceOffline: (_) async {
          offlineCalls += 1;
          // Enforcement already fenced the server epoch, so the old exact
          // session can no longer be closed a second time.
          return const ProviderRecoveryOfflineResult.authorityChanged();
        },
        reconcile: (_) async {},
      ),
    );
    addTearDown(() async {
      await positions.close();
      container.dispose();
    });
    container.read(providerStatusProvider.notifier).goOnline();
    container
        .read(providerLocationSessionProvider.notifier)
        .install(_epochA, 0);
    container.read(backgroundLocationSyncProvider);

    final timestamp =
        DateTime.now().toUtc().subtract(const Duration(seconds: 8));
    positions.add(_position(timestamp));
    await _settle();

    expect(location.batches, hasLength(1));
    expect(offlineCalls, 1);
    expect(container.read(providerStatusProvider), DriverStatus.offline);
    expect(container.read(providerLocationSessionProvider), isNull);
    expect(
      container.read(availabilityRestoreNoticeProvider),
      contains('repeated declines or missed requests'),
    );
    expect(
      container.read(availabilityRestoreNoticeProvider),
      isNot(contains('raw backend')),
    );
  });

  test('failed Offline CAS keeps current authority and reports uncertainty',
      () async {
    final positions = StreamController<Position>.broadcast();
    final location = _FakeLocationService()
      ..outcomes.add(
        _eligibility(<String>['DRIVER_ONLINE_SESSION_REQUIRED']),
      );
    late ProviderContainer container;
    var offlineCalls = 0;
    var reconcileCalls = 0;
    container = _container(
      positions: positions.stream,
      location: location,
      intentStore: _FakeOnlineIntentStore(),
      recovery: ProviderLocationRecoveryActions(
        forceOffline: (_) async {
          offlineCalls += 1;
          return const ProviderRecoveryOfflineResult.failed('No connection');
        },
        reconcile: (_) async {
          reconcileCalls += 1;
        },
      ),
    );
    addTearDown(() async {
      await positions.close();
      container.dispose();
    });
    container.read(providerStatusProvider.notifier).goOnline();
    container
        .read(providerLocationSessionProvider.notifier)
        .install(_epochA, 0);
    container.read(backgroundLocationSyncProvider);

    final timestamp =
        DateTime.now().toUtc().subtract(const Duration(seconds: 8));
    positions.add(_position(timestamp));
    await _settle();

    expect(offlineCalls, 1);
    expect(reconcileCalls, 0);
    expect(container.read(providerStatusProvider), DriverStatus.online);
    expect(
      container.read(providerLocationSessionProvider)?.onlineSessionId,
      _epochA,
    );
    expect(
      container.read(availabilityRestoreNoticeProvider),
      contains('could not confirm'),
    );
  });

  test('Offline CAS mismatch retires only the unchanged stale local epoch',
      () async {
    final positions = StreamController<Position>.broadcast();
    final location = _FakeLocationService()
      ..outcomes.add(
        _eligibility(<String>['DRIVER_ONLINE_SESSION_REQUIRED']),
      );
    final intentStore = _FakeOnlineIntentStore();
    final container = _container(
      positions: positions.stream,
      location: location,
      intentStore: intentStore,
      recovery: ProviderLocationRecoveryActions(
        forceOffline: (_) async =>
            const ProviderRecoveryOfflineResult.authorityChanged(),
        reconcile: (_) async => fail('mismatch must not reconcile stale A'),
      ),
    );
    addTearDown(() async {
      await positions.close();
      container.dispose();
    });
    container.read(providerStatusProvider.notifier).goOnline();
    container
        .read(providerLocationSessionProvider.notifier)
        .install(_epochA, 0);
    container.read(backgroundLocationSyncProvider);

    final timestamp =
        DateTime.now().toUtc().subtract(const Duration(seconds: 8));
    positions.add(_position(timestamp));
    await _settle();

    expect(intentStore.writes, isEmpty);
    expect(intentStore.shouldBeOnline, isTrue);
    expect(container.read(providerStatusProvider), DriverStatus.offline);
    expect(container.read(providerLocationSessionProvider), isNull);
    expect(container.read(providerLocationSyncPauseProvider), isNull);
    expect(
      container.read(availabilityRestoreNoticeProvider),
      contains('no longer current'),
    );
  });

  test('terminal recovery coalesces while Offline confirmation is pending',
      () async {
    final positions = StreamController<Position>.broadcast();
    final location = _FakeLocationService()
      ..outcomes.add(_eligibility(<String>['RM_FINAL_APPROVAL_REQUIRED']));
    final offline = Completer<ProviderRecoveryOfflineResult>();
    var offlineCalls = 0;
    final container = _container(
      positions: positions.stream,
      location: location,
      intentStore: _FakeOnlineIntentStore(),
      recovery: ProviderLocationRecoveryActions(
        forceOffline: (_) {
          offlineCalls += 1;
          return offline.future;
        },
        reconcile: (_) async {},
      ),
    );
    addTearDown(() async {
      if (!offline.isCompleted) {
        offline.complete(
          const ProviderRecoveryOfflineResult.failed('No connection'),
        );
      }
      await positions.close();
      container.dispose();
    });
    container.read(providerStatusProvider.notifier).goOnline();
    container
        .read(providerLocationSessionProvider.notifier)
        .install(_epochA, 0);
    container.read(backgroundLocationSyncProvider);

    final timestamp =
        DateTime.now().toUtc().subtract(const Duration(seconds: 8));
    positions.add(_position(timestamp));
    await _settle();
    positions.add(
      _position(timestamp.add(const Duration(seconds: 1)), latitude: 6.6895),
    );
    positions.add(
      _position(timestamp.add(const Duration(seconds: 2)), latitude: 6.6905),
    );
    await _settle();

    expect(offlineCalls, 1);
    expect(location.batches, hasLength(1));
    offline.complete(
      const ProviderRecoveryOfflineResult.failed('No connection'),
    );
    await _settle();
  });

  test(
    'busy session rejection backs off, preserves trail, and success resets',
    () async {
      final positions = StreamController<Position>.broadcast();
      final location = _FakeLocationService()
        ..outcomes.add(_eligibility(<String>['DRIVER_ONLINE_SESSION_REQUIRED']))
        ..outcomes.add(null)
        ..outcomes.add(null);
      var retryNow = DateTime.utc(2026, 8, 12, 23);
      var reconcileCalls = 0;
      final container = _container(
        positions: positions.stream,
        location: location,
        intentStore: _FakeOnlineIntentStore(),
        recovery: ProviderLocationRecoveryActions(
          forceOffline: (_) async => fail('busy must not force Offline'),
          reconcile: (_) async => reconcileCalls += 1,
        ),
        now: () => retryNow,
      );
      addTearDown(() async {
        await positions.close();
        container.dispose();
      });
      container.read(providerStatusProvider.notifier).setBusy();
      container
          .read(providerLocationSessionProvider.notifier)
          .install(_epochA, 0);
      container.read(backgroundLocationSyncProvider);

      final timestamp =
          DateTime.now().toUtc().subtract(const Duration(seconds: 8));
      positions.add(_position(timestamp, latitude: 6.6885));
      await _settle();
      positions.add(
        _position(timestamp.add(const Duration(seconds: 1)), latitude: 6.6887),
      );
      await _settle();
      expect(location.batches, hasLength(1));
      expect(reconcileCalls, 1);
      expect(container.read(providerStatusProvider), DriverStatus.busy);

      retryNow = retryNow.add(const Duration(seconds: 5));
      positions.add(
        _position(timestamp.add(const Duration(seconds: 5)), latitude: 6.6889),
      );
      await _settle();
      expect(location.batches, hasLength(2));
      expect(
        location.batches.last.map((sample) => sample.sampleSequence),
        <int>[1, 2, 3],
      );

      // The successful retry resets the gate, so a sufficiently moved sample is
      // allowed immediately rather than inheriting the old failure delay.
      positions.add(
        _position(timestamp.add(const Duration(seconds: 6)), latitude: 6.6891),
      );
      await _settle();
      expect(location.batches, hasLength(3));
    },
  );

  test('capability-only rejection backs off then recovers after registration',
      () async {
    final positions = StreamController<Position>.broadcast();
    final location = _FakeLocationService()
      ..outcomes.add(
        _eligibility(<String>['OFFER_RECEIPT_CAPABILITY_REQUIRED']),
      )
      ..outcomes.add(null);
    var retryNow = DateTime.utc(2026, 8, 12, 23);
    final container = _container(
      positions: positions.stream,
      location: location,
      intentStore: _FakeOnlineIntentStore(),
      recovery: ProviderLocationRecoveryActions(
        forceOffline: (_) async => fail('capability race remains retryable'),
        reconcile: (_) async => fail('capability race remains retryable'),
      ),
      now: () => retryNow,
    );
    addTearDown(() async {
      await positions.close();
      container.dispose();
    });
    container.read(providerStatusProvider.notifier).setBusy();
    container
        .read(providerLocationSessionProvider.notifier)
        .install(_epochA, 0);
    container.read(backgroundLocationSyncProvider);

    final timestamp =
        DateTime.now().toUtc().subtract(const Duration(seconds: 8));
    positions.add(_position(timestamp));
    await _settle();
    positions.add(
      _position(timestamp.add(const Duration(seconds: 1)), latitude: 6.6887),
    );
    await _settle();
    expect(location.batches, hasLength(1));
    expect(container.read(providerLocationSyncPauseProvider), isNull);

    retryNow = retryNow.add(const Duration(seconds: 5));
    positions.add(
      _position(timestamp.add(const Duration(seconds: 5)), latitude: 6.6889),
    );
    await _settle();
    expect(location.batches, hasLength(2));
    expect(container.read(providerStatusProvider), DriverStatus.busy);
  });

  test('capability startup grace terminates after three rejected attempts',
      () async {
    final positions = StreamController<Position>.broadcast();
    final capabilityError =
        _eligibility(<String>['OFFER_RECEIPT_CAPABILITY_REQUIRED']);
    final location = _FakeLocationService()
      ..outcomes.add(capabilityError)
      ..outcomes.add(capabilityError)
      ..outcomes.add(capabilityError);
    final intentStore = _FakeOnlineIntentStore();
    var retryNow = DateTime.utc(2026, 8, 12, 23);
    late ProviderContainer container;
    var offlineCalls = 0;
    container = _container(
      positions: positions.stream,
      location: location,
      intentStore: intentStore,
      recovery: ProviderLocationRecoveryActions(
        forceOffline: (_) async {
          offlineCalls += 1;
          await intentStore.write(_intentIdentity, shouldBeOnline: false);
          container.read(providerStatusProvider.notifier).goOffline();
          container.read(providerLocationSessionProvider.notifier).clear();
          return const ProviderRecoveryOfflineResult.confirmed();
        },
        reconcile: (_) async {},
      ),
      now: () => retryNow,
    );
    addTearDown(() async {
      await positions.close();
      container.dispose();
    });
    container.read(providerStatusProvider.notifier).goOnline();
    container
        .read(providerLocationSessionProvider.notifier)
        .install(_epochA, 0);
    container.read(backgroundLocationSyncProvider);

    final timestamp =
        DateTime.now().toUtc().subtract(const Duration(seconds: 8));
    positions.add(_position(timestamp));
    await _settle();
    retryNow = retryNow.add(const Duration(seconds: 5));
    positions.add(
      _position(timestamp.add(const Duration(seconds: 1)), latitude: 6.6895),
    );
    await _settle();
    retryNow = retryNow.add(const Duration(seconds: 10));
    positions.add(
      _position(timestamp.add(const Duration(seconds: 2)), latitude: 6.6905),
    );
    await _settle();

    expect(location.batches, hasLength(3));
    expect(offlineCalls, 1);
    expect(intentStore.shouldBeOnline, isFalse);
    expect(container.read(providerStatusProvider), DriverStatus.offline);
  });

  test(
    'persistent busy rejection pauses only its epoch and a new epoch resets',
    () async {
      final positions = StreamController<Position>.broadcast();
      final location = _FakeLocationService()
        ..outcomes.add(_eligibility(<String>['RM_FINAL_APPROVAL_REQUIRED']))
        ..outcomes.add(null);
      final container = _container(
        positions: positions.stream,
        location: location,
        intentStore: _FakeOnlineIntentStore(),
        recovery: ProviderLocationRecoveryActions(
          forceOffline: (_) async => fail('busy must not force Offline'),
          reconcile: (_) async {},
        ),
      );
      addTearDown(() async {
        await positions.close();
        container.dispose();
      });
      container.read(providerStatusProvider.notifier).setBusy();
      container
          .read(providerLocationSessionProvider.notifier)
          .install(_epochA, 0);
      container.read(backgroundLocationSyncProvider);

      final timestamp =
          DateTime.now().toUtc().subtract(const Duration(seconds: 8));
      positions.add(_position(timestamp));
      await _settle();
      positions.add(
        _position(timestamp.add(const Duration(seconds: 1)), latitude: 6.6887),
      );
      await _settle();
      expect(location.batches, hasLength(1));
      expect(container.read(providerStatusProvider), DriverStatus.busy);
      expect(
        container.read(providerLocationSyncPauseProvider)?.onlineSessionId,
        _epochA,
      );

      container
          .read(providerLocationSessionProvider.notifier)
          .install(_epochB, 0);
      positions.add(
        _position(timestamp.add(const Duration(seconds: 2)), latitude: 6.6889),
      );
      await _settle();

      expect(location.batches, hasLength(2));
      expect(location.sessionIds, <String>[_epochA, _epochB]);
      expect(container.read(providerLocationSyncPauseProvider), isNull);
      expect(container.read(providerStatusProvider), DriverStatus.busy);
    },
  );

  test('persistent busy fence converges Offline after active work settles',
      () async {
    final positions = StreamController<Position>.broadcast();
    final location = _FakeLocationService()
      ..outcomes.add(_eligibility(<String>['RM_FINAL_APPROVAL_REQUIRED']));
    final intentStore = _FakeOnlineIntentStore();
    late ProviderContainer container;
    var offlineCalls = 0;
    container = _container(
      positions: positions.stream,
      location: location,
      intentStore: intentStore,
      recovery: ProviderLocationRecoveryActions(
        forceOffline: (_) async {
          offlineCalls += 1;
          await intentStore.write(_intentIdentity, shouldBeOnline: false);
          container.read(providerStatusProvider.notifier).goOffline();
          container.read(providerLocationSessionProvider.notifier).clear();
          return const ProviderRecoveryOfflineResult.confirmed();
        },
        reconcile: (_) async {},
      ),
    );
    addTearDown(() async {
      await positions.close();
      container.dispose();
    });
    container.read(providerStatusProvider.notifier).setBusy();
    container
        .read(providerLocationSessionProvider.notifier)
        .install(_epochA, 0);
    container.read(backgroundLocationSyncProvider);

    final timestamp =
        DateTime.now().toUtc().subtract(const Duration(seconds: 8));
    positions.add(_position(timestamp));
    await _settle();

    expect(container.read(providerStatusProvider), DriverStatus.busy);
    expect(intentStore.shouldBeOnline, isTrue);
    expect(offlineCalls, 0);

    container.read(providerStatusProvider.notifier).resumeAfterJob();
    container.read(backgroundLocationSyncProvider);
    await _settle();

    expect(offlineCalls, 1);
    expect(container.read(providerStatusProvider), DriverStatus.offline);
    expect(container.read(providerLocationSessionProvider), isNull);
    expect(intentStore.shouldBeOnline, isFalse);
    expect(location.batches, hasLength(1));
  });

  test('late epoch-A success cannot consume replacement epoch-B samples',
      () async {
    final positions = StreamController<Position>.broadcast();
    final pending = Completer<Map<String, dynamic>>();
    final location = _FakeLocationService()
      ..pending = pending
      ..outcomes.add(null);
    final container = _container(
      positions: positions.stream,
      location: location,
      intentStore: _FakeOnlineIntentStore(),
      recovery: ProviderLocationRecoveryActions(
        forceOffline: (_) async => fail('success must not force Offline'),
        reconcile: (_) async => fail('success must not reconcile'),
      ),
    );
    addTearDown(() async {
      await positions.close();
      container.dispose();
    });
    container.read(providerStatusProvider.notifier).setBusy();
    container
        .read(providerLocationSessionProvider.notifier)
        .install(_epochA, 0);
    container.read(backgroundLocationSyncProvider);

    final timestamp =
        DateTime.now().toUtc().subtract(const Duration(seconds: 8));
    positions.add(_position(timestamp));
    await _settle();
    expect(location.sessionIds, <String>[_epochA]);

    final noticeBefore = container.read(availabilityRestoreNoticeProvider);
    container
        .read(providerLocationSessionProvider.notifier)
        .install(_epochB, 0);
    positions.add(
      _position(timestamp.add(const Duration(seconds: 1)), latitude: 6.6887),
    );
    await _settle();
    expect(container.read(providerLocationSessionProvider)?.lastSequence, 1);

    pending.complete(<String, dynamic>{});
    await _settle();

    expect(container.read(providerStatusProvider), DriverStatus.busy);
    expect(
      container.read(providerLocationSessionProvider)?.onlineSessionId,
      _epochB,
    );
    expect(container.read(providerLocationSessionProvider)?.lastSequence, 1);
    expect(container.read(providerLocationSyncPauseProvider), isNull);
    expect(container.read(availabilityRestoreNoticeProvider), noticeBefore);

    // The B sample staged while A was in flight remains queued and can be sent
    // immediately with the next B fix. A's success must not reset or consume
    // any replacement-epoch state.
    positions.add(
      _position(timestamp.add(const Duration(seconds: 2)), latitude: 6.6889),
    );
    await _settle();

    expect(location.sessionIds, <String>[_epochA, _epochB]);
    expect(
      location.batches.last.map((sample) => sample.sampleSequence),
      <int>[1, 2],
    );
  });

  test('late epoch-A rejection cannot pause replacement epoch B', () async {
    final positions = StreamController<Position>.broadcast();
    final pending = Completer<Map<String, dynamic>>();
    final location = _FakeLocationService()
      ..pending = pending
      ..outcomes.add(null);
    final container = _container(
      positions: positions.stream,
      location: location,
      intentStore: _FakeOnlineIntentStore(),
      recovery: ProviderLocationRecoveryActions(
        forceOffline: (_) async => fail('late failure must be ignored'),
        reconcile: (_) async => fail('late failure must be ignored'),
      ),
    );
    addTearDown(() async {
      await positions.close();
      container.dispose();
    });
    container.read(providerStatusProvider.notifier).setBusy();
    container
        .read(providerLocationSessionProvider.notifier)
        .install(_epochA, 0);
    container.read(backgroundLocationSyncProvider);

    final timestamp =
        DateTime.now().toUtc().subtract(const Duration(seconds: 8));
    positions.add(_position(timestamp));
    await _settle();
    expect(location.batches, hasLength(1));

    container
        .read(providerLocationSessionProvider.notifier)
        .install(_epochB, 0);
    pending.completeError(_eligibility(<String>['RM_FINAL_APPROVAL_REQUIRED']));
    await _settle();
    expect(container.read(providerLocationSyncPauseProvider), isNull);

    positions.add(
      _position(timestamp.add(const Duration(seconds: 1)), latitude: 6.6887),
    );
    await _settle();
    expect(location.sessionIds, <String>[_epochA, _epochB]);
  });

  test('late disposed account and SID cannot mutate replacement authority',
      () async {
    final user = StateProvider<AuthUser?>((_) => _user);
    final session = StateProvider<AuthSessionIdentity?>((_) => _authSession);
    final intent = StateProvider<ProviderOnlineIntentIdentity?>(
      (_) => _intentIdentity,
    );
    final positions = StreamController<Position>.broadcast();
    final pending = Completer<Map<String, dynamic>>();
    final location = _FakeLocationService()..pending = pending;
    var recoveryCalls = 0;
    final container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWith((ref) => ref.watch(user)),
        currentAuthSessionIdentityProvider.overrideWith(
          (ref) => ref.watch(session),
        ),
        currentProviderOnlineIntentIdentityProvider.overrideWith(
          (ref) => ref.watch(intent),
        ),
        providerTypeProvider.overrideWith((_) => ProviderType.driver),
        providerOnlineIntentStoreProvider.overrideWithValue(
          _FakeOnlineIntentStore(),
        ),
        locationServiceProvider.overrideWithValue(location),
        providerLocationRecoveryActionsProvider.overrideWithValue(
          ProviderLocationRecoveryActions(
            forceOffline: (_) async {
              recoveryCalls += 1;
              return const ProviderRecoveryOfflineResult.confirmed();
            },
            reconcile: (_) async => recoveryCalls += 1,
          ),
        ),
        driverLocationStreamProvider.overrideWith((_) => positions.stream),
      ],
    );
    addTearDown(() async {
      await positions.close();
      container.dispose();
    });
    container.read(providerStatusProvider.notifier).setBusy();
    container
        .read(providerLocationSessionProvider.notifier)
        .install(_epochA, 0);
    container.read(backgroundLocationSyncProvider);

    final timestamp =
        DateTime.now().toUtc().subtract(const Duration(seconds: 8));
    positions.add(_position(timestamp));
    await _settle();
    final originalLastKnown = container.read(lastKnownPositionProvider);
    container
        .read(providerLocationSessionProvider.notifier)
        .install(_epochB, 0);
    container.read(user.notifier).state = const AuthUser(
      id: 'driver-2',
      phone: '+233240000002',
      fullName: 'Driver Two',
      role: AuthRole.driver,
    );
    container.read(intent.notifier).state = const ProviderOnlineIntentIdentity(
      role: ProviderOnlineIntentRole.driver,
      roleAccountId: 'driver-2',
    );
    container.read(session.notifier).state = const AuthSessionIdentity(
      subject: 'private-user-2',
      role: 'driver',
      roleAccountId: 'driver-2',
      sessionId: 'auth-session-b',
    );
    positions.add(
      _position(timestamp.add(const Duration(seconds: 1)), latitude: 6.6999),
    );
    pending.completeError(
      _eligibility(<String>['RM_FINAL_APPROVAL_REQUIRED']),
    );
    await _settle();

    expect(recoveryCalls, 0);
    expect(container.read(providerLocationSyncPauseProvider), isNull);
    expect(container.read(providerStatusProvider), DriverStatus.busy);
    expect(container.read(lastKnownPositionProvider), originalLastKnown);
    expect(
      container.read(providerLocationSessionProvider)?.onlineSessionId,
      _epochB,
    );
    expect(container.read(providerLocationSessionProvider)?.lastSequence, 0);
  });
}

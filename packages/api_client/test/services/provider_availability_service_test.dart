import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  late Dio dio;
  late RequestOptions capturedRequest;
  late Map<String, dynamic> responseData;

  setUp(() {
    responseData = {
      'success': true,
      'data': {
        'role': 'driver',
        'providerId': 'driver-1',
        'status': 'offline',
        'activeRideId': null,
        'activeJobId': null,
        'lastSeenAt': '2026-07-17T10:30:00.000Z',
        'locationHealth': 'healthy',
        'locationRecoveryRequired': false,
        'locationDegradedAt': null,
        'locationDegradedReason': null,
        'locationDegradedEscalatedAt': null,
      },
    };
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: responseData,
            ),
          );
        },
      ),
    );
  });

  test('gets and strictly parses the authoritative snapshot', () async {
    final snapshot = await ProviderAvailabilityService(dio).getMyAvailability();

    expect(capturedRequest.method, 'GET');
    expect(capturedRequest.path, '/providers/me/availability');
    expect(snapshot.role, ProviderAvailabilityRole.driver);
    expect(snapshot.providerId, 'driver-1');
    expect(snapshot.status, ProviderAvailabilityStatus.offline);
    expect(snapshot.hasActiveWork, isFalse);
    expect(snapshot.lastSeenAt, DateTime.utc(2026, 7, 17, 10, 30));
    expect(snapshot.locationHealth, ProviderLocationHealth.healthy);
    expect(snapshot.locationRecoveryRequired, isFalse);
  });

  test('strictly parses a server-owned location epoch and sequence', () {
    final snapshot = ProviderAvailabilitySnapshot.fromJson({
      'role': 'driver',
      'providerId': 'driver-1',
      'status': 'online',
      'activeRideId': null,
      'activeJobId': null,
      'lastSeenAt': '2026-07-18T12:30:00.000Z',
      'onlineSessionId': '60000000-0000-4000-8000-000000000006',
      'lastLocationSequence': 42,
    });

    expect(snapshot.onlineSessionId, '60000000-0000-4000-8000-000000000006');
    expect(snapshot.lastLocationSequence, 42);
  });

  test('rejects a partial or invalid location session instead of guessing', () {
    for (final payload in <Map<String, dynamic>>[
      {
        'role': 'driver',
        'providerId': 'driver-1',
        'status': 'online',
        'activeRideId': null,
        'activeJobId': null,
        'lastSeenAt': null,
        'onlineSessionId': '60000000-0000-4000-8000-000000000006',
      },
      {
        'role': 'driver',
        'providerId': 'driver-1',
        'status': 'online',
        'activeRideId': null,
        'activeJobId': null,
        'lastSeenAt': null,
        'onlineSessionId': '60000000-0000-4000-8000-000000000006',
        'lastLocationSequence': -1,
      },
      {
        'role': 'driver',
        'providerId': 'driver-1',
        'status': 'online',
        'activeRideId': null,
        'activeJobId': null,
        'lastSeenAt': null,
        'lastLocationSequence': 1,
      },
    ]) {
      expect(
        () => ProviderAvailabilitySnapshot.fromJson(payload),
        throwsFormatException,
      );
    }
  });

  test(
    'posts no-GPS offline intent so the server clears session vehicle authority',
    () async {
      final snapshot = await ProviderAvailabilityService(
        dio,
      ).setMyAvailability(status: ProviderAvailabilityStatus.offline);

      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.path, '/providers/availability');
      expect(capturedRequest.data, {'status': 'offline'});
      expect(snapshot.status, ProviderAvailabilityStatus.offline);
    },
  );

  test(
    'posts exact provider and session authority for recovery Offline',
    () async {
      await ProviderAvailabilityService(dio).setMyAvailability(
        status: ProviderAvailabilityStatus.offline,
        expectedProviderId: '60000000-0000-4000-8000-000000000006',
        expectedOnlineSessionId: '70000000-0000-4000-8000-000000000007',
      );

      expect(capturedRequest.data, {
        'status': 'offline',
        'expectedProviderId': '60000000-0000-4000-8000-000000000006',
        'expectedOnlineSessionId': '70000000-0000-4000-8000-000000000007',
      });
    },
  );

  test('rejects partial or Online recovery authority locally', () async {
    final service = ProviderAvailabilityService(dio);

    expect(
      service.setMyAvailability(
        status: ProviderAvailabilityStatus.offline,
        expectedProviderId: '60000000-0000-4000-8000-000000000006',
      ),
      throwsArgumentError,
    );
    expect(
      service.setMyAvailability(
        status: ProviderAvailabilityStatus.online,
        expectedProviderId: '60000000-0000-4000-8000-000000000006',
        expectedOnlineSessionId: '70000000-0000-4000-8000-000000000007',
      ),
      throwsArgumentError,
    );
  });

  test('rejects an unknown status instead of guessing', () async {
    (responseData['data'] as Map<String, dynamic>)['status'] = 'busy';

    expect(
      ProviderAvailabilityService(dio).getMyAvailability(),
      throwsA(isA<FormatException>()),
    );
  });

  test('reports active work from either role-specific id', () {
    final snapshot = ProviderAvailabilitySnapshot.fromJson({
      'role': 'artisan',
      'providerId': 'artisan-1',
      'status': 'online',
      'activeRideId': null,
      'activeJobId': 'job-1',
      'lastSeenAt': null,
    });

    expect(snapshot.hasActiveWork, isTrue);
    expect(snapshot.activeJobId, 'job-1');
  });

  test('strictly parses a durable degraded and escalated location state', () {
    final snapshot = ProviderAvailabilitySnapshot.fromJson({
      'role': 'driver',
      'providerId': 'driver-1',
      'status': 'offline',
      'activeRideId': 'ride-1',
      'activeJobId': null,
      'lastSeenAt': null,
      'locationHealth': 'degraded',
      'locationRecoveryRequired': true,
      'locationDegradedAt': '2026-07-18T12:00:00.000Z',
      'locationDegradedReason': 'permission_lost',
      'locationDegradedEscalatedAt': '2026-07-18T12:02:00.000Z',
    });

    expect(snapshot.locationHealth, ProviderLocationHealth.degraded);
    expect(snapshot.locationRecoveryRequired, isTrue);
    expect(snapshot.locationDegradedReason, 'permission_lost');
    expect(snapshot.locationDegradedEscalatedAt, isNotNull);
  });

  test('rejects contradictory location health instead of guessing', () {
    expect(
      () => ProviderAvailabilitySnapshot.fromJson({
        'role': 'driver',
        'providerId': 'driver-1',
        'status': 'online',
        'activeRideId': null,
        'activeJobId': null,
        'lastSeenAt': null,
        'locationHealth': 'healthy',
        'locationRecoveryRequired': true,
      }),
      throwsFormatException,
    );
  });

  test('strictly parses vehicle preflight eligibility', () async {
    responseData = {
      'success': true,
      'data': {
        'activeVehicleId': null,
        'onlineStatus': 'offline',
        'legacy': {'backfillRequired': false},
        'vehicles': [
          {
            'id': 'vehicle-1',
            'make': 'Toyota',
            'model': 'Corolla',
            'year': 2022,
            'plate': 'AS 1234-26',
            'color': 'Black',
            'isActive': true,
            'eligible': true,
            'reasonCodes': <String>[],
          },
        ],
      },
    };

    final preflight = await ProviderAvailabilityService(dio).getMyVehicles();

    expect(capturedRequest.path, '/providers/me/vehicles');
    expect(preflight.onlineStatus, 'offline');
    expect(preflight.legacyBackfillRequired, isFalse);
    expect(preflight.vehicles.single.displayName, 'Toyota Corolla');
    expect(preflight.vehicles.single.eligible, isTrue);
  });

  test('rejects malformed vehicle eligibility instead of guessing', () {
    expect(
      () => ProviderVehiclePreflight.fromJson({
        'activeVehicleId': null,
        'onlineStatus': 'offline',
        'legacy': {'backfillRequired': false},
        'vehicles': [
          {
            'id': 'vehicle-1',
            'isActive': true,
            'eligible': 'yes',
            'reasonCodes': <String>[],
          },
        ],
      }),
      throwsFormatException,
    );
  });
}

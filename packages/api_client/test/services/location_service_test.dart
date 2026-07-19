import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  late Dio dio;
  late RequestOptions capturedRequest;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          capturedRequest = options;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'data': <String, dynamic>{},
              },
            ),
          );
        },
      ),
    );
  });

  test('online driver location includes authoritative fix age and accuracy',
      () async {
    final recordedAt = DateTime.utc(2026, 7, 18, 12, 30, 15);

    await LocationService(dio).updateDriverLocation(
      latitude: 6.6885,
      longitude: -1.6244,
      accuracyMeters: 12.5,
      recordedAt: recordedAt,
      vehicleId: 'vehicle-1',
      onlineSessionId: '60000000-0000-4000-8000-000000000006',
      sampleSequence: 42,
    );

    expect(capturedRequest.path, '/location/update');
    expect(capturedRequest.data, {
      'latitude': 6.6885,
      'longitude': -1.6244,
      'accuracyMeters': 12.5,
      'recordedAt': '2026-07-18T12:30:15.000Z',
      'vehicleId': 'vehicle-1',
      'onlineSessionId': '60000000-0000-4000-8000-000000000006',
      'sampleSequence': 42,
      'status': 'online',
    });
  });

  test('artisan location carries the exact online epoch and sequence',
      () async {
    final recordedAt = DateTime.utc(2026, 7, 18, 12, 30, 16);

    await LocationService(dio).updateArtisanLocation(
      latitude: 6.6885,
      longitude: -1.6244,
      accuracyMeters: 9,
      recordedAt: recordedAt,
      onlineSessionId: '70000000-0000-4000-8000-000000000007',
      sampleSequence: 13,
    );

    expect(capturedRequest.path, '/location/artisan/update');
    expect(capturedRequest.data, {
      'latitude': 6.6885,
      'longitude': -1.6244,
      'accuracyMeters': 9.0,
      'recordedAt': '2026-07-18T12:30:16.000Z',
      'onlineSessionId': '70000000-0000-4000-8000-000000000007',
      'sampleSequence': 13,
      'status': 'online',
    });
  });

  test('driver batch preserves reported accuracy for every GPS sample',
      () async {
    await LocationService(dio).updateDriverLocationBatch(
      samples: [
        DriverLocationSample(
          latitude: 6.6885,
          longitude: -1.6244,
          accuracyMeters: 8,
          sampleSequence: 1,
          recordedAt: DateTime.utc(2026, 7, 18, 12, 31),
        ),
      ],
      onlineSessionId: '60000000-0000-4000-8000-000000000006',
    );

    expect(capturedRequest.path, '/location/driver/batch');
    expect(capturedRequest.data, {
      'onlineSessionId': '60000000-0000-4000-8000-000000000006',
      'samples': [
        {
          'latitude': 6.6885,
          'longitude': -1.6244,
          'accuracyMeters': 8.0,
          'sampleSequence': 1,
          'recordedAt': '2026-07-18T12:31:00.000Z',
        },
      ],
    });
  });

  test('reports a stable device-authoritative location-loss reason', () async {
    await LocationService(dio).reportUnavailable(
      LocationUnavailableReason.backgroundPermissionLost,
    );

    expect(capturedRequest.path, '/location/unavailable');
    expect(capturedRequest.data, {
      'reason': 'background_permission_lost',
    });
  });
}

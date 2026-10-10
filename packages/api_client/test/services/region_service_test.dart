import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

void main() {
  late Dio dio;
  late RequestOptions captured;
  late Object responseData;

  setUp(() {
    responseData = {
      'success': true,
      'data': {
        'regions': [
          {
            'id': 'bono-region',
            'name': 'Bono Region',
            'code': 'BON',
            'ridesEnabled': true,
            'jobsEnabled': false,
            'serviceAreaName': 'Sunyani launch v1',
          },
        ],
      },
    };
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          captured = options;
          handler.resolve(
            Response<Object>(
              requestOptions: options,
              statusCode: 200,
              data: responseData,
            ),
          );
        },
      ),
    );
  });

  test('lists regional service availability for registration', () async {
    final regions = await RegionService(dio).getRegions();

    expect(captured.method, 'GET');
    expect(captured.path, '/regions');
    expect(regions.single.code, 'BON');
    expect(regions.single.ridesEnabled, isTrue);
    expect(regions.single.jobsEnabled, isFalse);
    expect(regions.single.serviceAreaName, 'Sunyani launch v1');
  });

  test('resolves the signed-in account region from trusted GPS', () async {
    responseData = {
      'success': true,
      'data': {
        'region': {
          'id': 'ashanti-region',
          'name': 'Ashanti Region',
          'code': 'ASH',
          'ridesEnabled': true,
          'jobsEnabled': true,
          'serviceAreaName': 'Ashanti Region',
        },
      },
    };

    final region = await RegionService(dio).resolveCurrentRegion(
      latitude: 6.6885,
      longitude: -1.6244,
      service: 'rides',
    );

    expect(captured.method, 'POST');
    expect(captured.path, '/regions/resolve');
    expect(captured.data, {
      'latitude': 6.6885,
      'longitude': -1.6244,
      'service': 'rides',
    });
    expect(region?.code, 'ASH');
  });
}

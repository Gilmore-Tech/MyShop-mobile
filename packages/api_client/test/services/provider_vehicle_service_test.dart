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
        'activeVehicleId': null,
        'onlineStatus': 'offline',
        'legacy': {
          'backfillRequired': false,
          'reasonCode': null,
        },
        'vehicles': [
          {
            'id': 'vehicle-1',
            'make': 'Toyota',
            'model': 'Corolla',
            'year': 2024,
            'plate': 'GR-1234-24',
            'color': 'Silver',
            'isActive': true,
            'approvalStatus': 'pending_coordinator',
            'version': 3,
            'rejectionReason': null,
            'coordinatorReviewedAt': null,
            'regionalManagerReviewedAt': null,
            'retirementRequestedAt': null,
            'retirementRequestReason': null,
            'rideCategories': [
              {
                'id': 'category-1',
                'name': 'Regular',
                'slug': 'regular',
                'isActive': true,
                'status': 'pending',
                'rejectionReason': null,
                'reviewedAt': null,
              },
            ],
            'pendingRevision': null,
            'eligible': false,
            'reasonCodes': ['VEHICLE_NOT_AVAILABLE'],
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

  test('strictly parses vehicle lifecycle and per-vehicle categories',
      () async {
    final result = await ProviderVehicleService(dio).listMyVehicles();

    expect(captured.path, '/providers/me/vehicles');
    expect(result.vehicles.single.version, 3);
    expect(
      result.vehicles.single.approvalStatus,
      ProviderVehicleApprovalStatus.pendingCoordinator,
    );
    expect(
      result.vehicles.single.rideCategories.single.status,
      ProviderVehicleCategoryStatus.pending,
    );
  });

  test('fails closed on an unknown lifecycle status', () async {
    final body = responseData as Map<String, dynamic>;
    final data = body['data'] as Map<String, dynamic>;
    final vehicles = data['vehicles'] as List<dynamic>;
    (vehicles.single as Map<String, dynamic>)['approvalStatus'] = 'active';

    expect(
      ProviderVehicleService(dio).listMyVehicles(),
      throwsA(isA<FormatException>()),
    );
  });

  test('update sends expectedVersion in the JSON body', () async {
    responseData = {
      'success': true,
      'data': {
        'vehicle': {'id': 'vehicle-1', 'version': 4},
      },
    };
    const input = ProviderVehicleInput(
      make: 'Toyota',
      model: 'Corolla',
      year: 2024,
      plate: 'GR-1234-24',
      color: 'Silver',
      rideCategoryIds: ['category-1'],
    );

    final result = await ProviderVehicleService(dio).updateVehicle(
      vehicleId: 'vehicle-1',
      expectedVersion: 3,
      input: input,
    );

    expect(captured.method, 'PATCH');
    expect(captured.path, '/providers/me/vehicles/vehicle-1');
    expect(captured.data, containsPair('expectedVersion', 3));
    expect(captured.headers.containsKey('If-Match'), isFalse);
    expect(result.version, 4);
  });
}

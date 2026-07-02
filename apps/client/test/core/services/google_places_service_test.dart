import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/services/google_places_service.dart';

void main() {
  late Dio dio;
  late List<RequestOptions> requests;
  late GooglePlacesService service;

  setUp(() {
    requests = [];
    dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/v1'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options);
          if (options.path == '/location/places/autocomplete') {
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    'suggestions': [
                      {
                        'placeId': 'place-123',
                        'mainText': 'Kumasi City Mall',
                        'secondaryText': 'Kumasi, Ghana',
                        'fullText': 'Kumasi City Mall, Kumasi, Ghana',
                      },
                    ],
                  },
                },
              ),
            );
          }
          if (options.path == '/location/places/details') {
            final body = options.data as Map<String, dynamic>;
            final isArea = body['placeId'] == 'area-123';
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    'placeId': isArea ? 'area-123' : 'place-123',
                    'name': isArea ? 'Tema' : 'Kumasi City Mall',
                    'address': isArea
                        ? 'Tema, Ghana'
                        : 'Kumasi City Mall, Kumasi, Ghana',
                    'latitude': isArea ? 5.6698 : 6.61,
                    'longitude': isArea ? -0.0166 : -1.59,
                    'precision': isArea ? 'area' : 'point',
                    'types': isArea
                        ? ['locality', 'political']
                        : ['shopping_mall', 'point_of_interest'],
                  },
                },
              ),
            );
          }
          if (options.path == '/location/reverse-geocode') {
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'success': true,
                  'data': {
                    'name': 'Prempeh II Street',
                    'address': 'Prempeh II Street, Adum, Kumasi, Ghana',
                  },
                },
              ),
            );
          }
          return handler.reject(
            DioException(
              requestOptions: options,
              message: 'Unexpected test request: ${options.path}',
            ),
          );
        },
      ),
    );
    service = GooglePlacesService(dio: dio);
  });

  test('autocomplete and place details reuse one billing session token',
      () async {
    final suggestions = await service.autocomplete('Kumasi Mall');
    final detail = await service.getPlaceDetail(suggestions.single.placeId);

    expect(suggestions.single.mainText, 'Kumasi City Mall');
    expect(suggestions.single.fullText, 'Kumasi City Mall, Kumasi, Ghana');
    expect(detail?.address, 'Kumasi City Mall, Kumasi, Ghana');
    expect(detail?.name, 'Kumasi City Mall');
    expect(detail?.latitude, 6.61);
    expect(detail?.requiresExactPin, isFalse);
    expect(requests, hasLength(2));

    final autocompleteBody = requests[0].data as Map<String, dynamic>;
    final detailsBody = requests[1].data as Map<String, dynamic>;
    final autocompleteToken = autocompleteBody['sessionToken'];
    final detailsToken = detailsBody['sessionToken'];
    expect(autocompleteToken, isA<String>());
    expect((autocompleteToken as String).length, greaterThanOrEqualTo(20));
    expect(detailsToken, autocompleteToken);
    expect(autocompleteBody, isNot(contains('key')));
  });

  test('broad areas are marked as requiring an exact map pin', () async {
    final detail = await service.getPlaceDetail('area-123');

    expect(detail?.name, 'Tema');
    expect(detail?.precision, PlacePrecision.area);
    expect(detail?.requiresExactPin, isTrue);
  });

  test('reverse geocoding uses the authenticated backend endpoint', () async {
    final address = await service.reverseGeocode(6.6885, -1.6244);

    expect(address, 'Prempeh II Street, Adum, Kumasi, Ghana');
    expect(requests.single.path, '/location/reverse-geocode');
    expect(requests.single.data, {
      'latitude': 6.6885,
      'longitude': -1.6244,
    });
  });

  test('structured reverse geocoding keeps road name separate', () async {
    final place = await service.reverseGeocodePlace(6.6885, -1.6244);

    expect(place?.name, 'Prempeh II Street');
    expect(place?.address, 'Prempeh II Street, Adum, Kumasi, Ghana');
  });
}

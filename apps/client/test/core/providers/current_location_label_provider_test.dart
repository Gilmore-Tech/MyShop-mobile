import 'dart:async';

import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/core/providers/current_location_label_provider.dart';
import 'package:myshop_client/src/core/providers/current_location_provider.dart';
import 'package:myshop_client/src/core/services/google_places_service.dart';

class _MockCurrentLocationService extends Mock
    implements CurrentLocationService {}

class _MockGooglePlacesService extends Mock implements GooglePlacesService {}

class _MockDio extends Mock implements Dio {}

Position _position({
  double latitude = 6.6885,
  double longitude = -1.6244,
  DateTime? timestamp,
}) =>
    Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp ?? DateTime.utc(2026, 7, 26),
      accuracy: 8,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );

void main() {
  test('falls back instead of leaving the UI on Locating when GPS fails',
      () async {
    final location = _MockCurrentLocationService();
    when(() => location.ensure()).thenThrow(StateError('plugin unavailable'));
    final container = ProviderContainer(
      overrides: [
        currentLocationServiceProvider.overrideWithValue(location),
      ],
    );
    addTearDown(container.dispose);

    final place = await container.read(currentLocationPlaceProvider.future);

    expect(place.name, 'Current location');
    expect(place.address, 'Waiting for GPS signal');
  });

  test('shows the full human-readable reverse-geocoded address', () async {
    final places = _MockGooglePlacesService();
    when(() => places.reverseGeocodePlace(6.6885, -1.6244)).thenAnswer(
      (_) async => const ReverseGeocodePlace(
        name: 'Prempeh II Street',
        address: 'Prempeh II Street, Adum, Kumasi, Ghana',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        currentDevicePositionProvider.overrideWith((_) => _position()),
        reverseGeocodingServiceProvider.overrideWithValue(places),
      ],
    );
    addTearDown(container.dispose);

    final label = await container.read(currentLocationLabelProvider.future);

    expect(label, 'Prempeh II Street, Adum, Kumasi, Ghana');
    verify(() => places.reverseGeocodePlace(6.6885, -1.6244)).called(1);
  });

  test('falls back after one failed reverse-geocode request', () async {
    final places = _MockGooglePlacesService();
    when(() => places.reverseGeocodePlace(6.6885, -1.6244))
        .thenThrow(StateError('proxy unavailable'));
    final container = ProviderContainer(
      overrides: [
        currentDevicePositionProvider.overrideWith((_) => _position()),
        reverseGeocodingServiceProvider.overrideWithValue(places),
      ],
    );
    addTearDown(container.dispose);

    final label = await container.read(currentLocationLabelProvider.future);

    expect(label, 'Current location');
    verify(() => places.reverseGeocodePlace(6.6885, -1.6244)).called(1);
  });

  test('shares one coordinate lookup across sequential booking consumers',
      () async {
    final places = _MockGooglePlacesService();
    when(() => places.reverseGeocodePlace(6.6885, -1.6244)).thenAnswer(
      (_) async => const ReverseGeocodePlace(
        name: 'Adum',
        address: 'Adum, Kumasi, Ghana',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        currentDevicePositionProvider.overrideWith((_) => _position()),
        reverseGeocodingServiceProvider.overrideWithValue(places),
      ],
    );
    addTearDown(container.dispose);

    final current = await container.read(currentLocationPlaceProvider.future);
    final booking = await container.read(
      reverseGeocodedPlaceProvider((
        latitude: 6.6885,
        longitude: -1.6244,
      )).future,
    );

    expect(current.address, 'Adum, Kumasi, Ghana');
    expect(booking.address, current.address);
    verify(() => places.reverseGeocodePlace(6.6885, -1.6244)).called(1);
  });

  test('reverse-geocode client stays stable when autocomplete bias changes',
      () {
    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(_MockDio()),
      ],
    );
    addTearDown(container.dispose);

    final reverseBefore = container.read(reverseGeocodingServiceProvider);
    final autocompleteBefore = container.read(googlePlacesServiceProvider);

    container.read(currentDevicePositionProvider.notifier).state = _position(
      latitude: 6.7042,
      longitude: -1.6349,
      timestamp: DateTime.utc(2026, 8, 22),
    );

    final reverseAfter = container.read(reverseGeocodingServiceProvider);
    final autocompleteAfter = container.read(googlePlacesServiceProvider);
    expect(identical(reverseAfter, reverseBefore), isTrue);
    expect(identical(autocompleteAfter, autocompleteBefore), isFalse);
  });

  test('position metadata cannot restart an in-flight coordinate lookup',
      () async {
    final places = _MockGooglePlacesService();
    final response = Completer<ReverseGeocodePlace?>();
    when(() => places.reverseGeocodePlace(6.6885, -1.6244))
        .thenAnswer((_) => response.future);
    final container = ProviderContainer(
      overrides: [
        currentDevicePositionProvider.overrideWith((_) => _position()),
        reverseGeocodingServiceProvider.overrideWithValue(places),
      ],
    );
    addTearDown(container.dispose);
    const coordinates = (latitude: 6.6885, longitude: -1.6244);

    final first = container.read(
      reverseGeocodedPlaceProvider(coordinates).future,
    );
    await pumpEventQueue();
    container.read(currentDevicePositionProvider.notifier).state = _position(
      timestamp: DateTime.utc(2026, 8, 22),
    );
    final joined = container.read(
      reverseGeocodedPlaceProvider(coordinates).future,
    );
    response.complete(
      const ReverseGeocodePlace(
        name: 'Adum',
        address: 'Adum, Kumasi, Ghana',
      ),
    );

    final results = await Future.wait([first, joined]);
    expect(results.map((place) => place.address).toSet(), {
      'Adum, Kumasi, Ghana',
    });
    verify(() => places.reverseGeocodePlace(6.6885, -1.6244)).called(1);
  });

  test('keeps exact coordinates but never exposes the GPS fallback as a label',
      () async {
    final places = _MockGooglePlacesService();
    when(() => places.reverseGeocodePlace(6.6885, -1.6244))
        .thenAnswer((_) async => null);
    final container = ProviderContainer(
      overrides: [
        currentDevicePositionProvider.overrideWith((_) => _position()),
        reverseGeocodingServiceProvider.overrideWithValue(places),
      ],
    );
    addTearDown(container.dispose);

    final place = await container.read(currentLocationPlaceProvider.future);
    final label = await container.read(currentLocationLabelProvider.future);

    expect(place.name, 'Current location');
    expect(place.address, '6.68850, -1.62440');
    expect(label, 'Current location');
    expect(label, isNot('Using GPS location'));
    verify(() => places.reverseGeocodePlace(6.6885, -1.6244)).called(1);
  });
}

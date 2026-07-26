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

Position _position() => Position(
      latitude: 6.6885,
      longitude: -1.6244,
      timestamp: DateTime.utc(2026, 7, 26),
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
        googlePlacesServiceProvider.overrideWithValue(places),
      ],
    );
    addTearDown(container.dispose);

    final label = await container.read(currentLocationLabelProvider.future);

    expect(label, 'Prempeh II Street, Adum, Kumasi, Ghana');
    verify(() => places.reverseGeocodePlace(6.6885, -1.6244)).called(1);
  });

  test('retries transient reverse-geocode failures before falling back',
      () async {
    final places = _MockGooglePlacesService();
    var attempts = 0;
    when(() => places.reverseGeocodePlace(6.6885, -1.6244)).thenAnswer(
      (_) async {
        attempts += 1;
        if (attempts == 1) return null;
        if (attempts == 2) throw StateError('temporary proxy failure');
        return const ReverseGeocodePlace(
          name: 'Adum',
          address: 'Adum, Kumasi, Ghana',
        );
      },
    );
    final container = ProviderContainer(
      overrides: [
        currentDevicePositionProvider.overrideWith((_) => _position()),
        googlePlacesServiceProvider.overrideWithValue(places),
      ],
    );
    addTearDown(container.dispose);

    final label = await container.read(currentLocationLabelProvider.future);

    expect(label, 'Adum, Kumasi, Ghana');
    expect(attempts, 3);
  });

  test('keeps exact coordinates but never exposes the GPS fallback as a label',
      () async {
    final places = _MockGooglePlacesService();
    when(() => places.reverseGeocodePlace(6.6885, -1.6244))
        .thenAnswer((_) async => null);
    final container = ProviderContainer(
      overrides: [
        currentDevicePositionProvider.overrideWith((_) => _position()),
        googlePlacesServiceProvider.overrideWithValue(places),
      ],
    );
    addTearDown(container.dispose);

    final place = await container.read(currentLocationPlaceProvider.future);
    final label = await container.read(currentLocationLabelProvider.future);

    expect(place.name, 'Current location');
    expect(place.address, '6.68850, -1.62440');
    expect(label, 'Current location');
    expect(label, isNot('Using GPS location'));
    verify(() => places.reverseGeocodePlace(6.6885, -1.6244)).called(3);
  });
}

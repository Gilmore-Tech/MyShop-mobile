import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/core/providers/current_location_provider.dart';
import 'package:myshop_client/src/core/providers/current_operational_region_provider.dart';

class _MockRegionService extends Mock implements RegionService {}

Position _position({
  required DateTime timestamp,
  double accuracy = 8,
}) {
  return Position(
    latitude: 6.6885,
    longitude: -1.6244,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  test('does not resolve a region from the OS last-known cache', () async {
    final regions = _MockRegionService();
    final cached = _position(
      timestamp: DateTime.now().subtract(const Duration(seconds: 10)),
    );
    final container = ProviderContainer(
      overrides: [
        regionServiceProvider.overrideWithValue(regions),
        currentDevicePositionProvider.overrideWith((_) => cached),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(currentOperationalRegionProvider.future), null);
    verifyNever(
      () => regions.resolveCurrentRegion(
        latitude: any(named: 'latitude'),
        longitude: any(named: 'longitude'),
        service: any(named: 'service'),
      ),
    );
  });

  test('resolves a region from a reliable live fix', () async {
    final regions = _MockRegionService();
    final fresh = _position(
      timestamp: DateTime.now().subtract(const Duration(seconds: 10)),
    );
    const ashanti = Region(
      id: 'region-ashanti',
      name: 'Ashanti Region',
      code: 'ASH',
      ridesEnabled: true,
      jobsEnabled: true,
    );
    when(
      () => regions.resolveCurrentRegion(
        latitude: 6.6885,
        longitude: -1.6244,
        service: 'rides',
      ),
    ).thenAnswer((_) async => ashanti);
    final container = ProviderContainer(
      overrides: [
        regionServiceProvider.overrideWithValue(regions),
        freshCurrentDevicePositionProvider.overrideWith((_) => fresh),
      ],
    );
    addTearDown(container.dispose);

    expect(
      await container.read(currentOperationalRegionProvider.future),
      ashanti,
    );
    verify(
      () => regions.resolveCurrentRegion(
        latitude: 6.6885,
        longitude: -1.6244,
        service: 'rides',
      ),
    ).called(1);
  });

  test('does not classify a very broad live fix', () async {
    final regions = _MockRegionService();
    final broad = _position(
      timestamp: DateTime.now().subtract(const Duration(seconds: 10)),
      accuracy: 800,
    );
    final container = ProviderContainer(
      overrides: [
        regionServiceProvider.overrideWithValue(regions),
        freshCurrentDevicePositionProvider.overrideWith((_) => broad),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(currentOperationalRegionProvider.future), null);
    verifyNever(
      () => regions.resolveCurrentRegion(
        latitude: any(named: 'latitude'),
        longitude: any(named: 'longitude'),
        service: any(named: 'service'),
      ),
    );
  });
}

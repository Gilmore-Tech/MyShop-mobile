import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/core/providers/current_location_label_provider.dart';
import 'package:myshop_client/src/core/providers/current_location_provider.dart';

class _MockCurrentLocationService extends Mock
    implements CurrentLocationService {}

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
}

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/utils/ride_service_area.dart';

void main() {
  test('treats central Kumasi as inside the ride service area', () {
    expect(
      isLikelyInsideRideServiceArea(latitude: 6.6884, longitude: -1.6244),
      isTrue,
    );
  });

  test('treats the rejected production coordinates as outside service area',
      () {
    expect(
      isLikelyOutsideRideServiceArea(
        latitude: 6.0875466,
        longitude: -0.2694868,
      ),
      isTrue,
    );
  });
}

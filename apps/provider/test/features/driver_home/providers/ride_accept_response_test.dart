import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/driver_home/providers/ride_request_provider.dart';

void main() {
  test('accept requires an explicit matching authoritative response', () {
    expect(
      isConfirmedRideAcceptResponse(
        const {'rideId': 'ride-1', 'status': 'accepted'},
        'ride-1',
      ),
      isTrue,
    );
    expect(isConfirmedRideAcceptResponse(null, 'ride-1'), isFalse);
    expect(isConfirmedRideAcceptResponse(const {}, 'ride-1'), isFalse);
    expect(
      isConfirmedRideAcceptResponse(
        const {'rideId': 'ride-2', 'status': 'accepted'},
        'ride-1',
      ),
      isFalse,
    );
    expect(
      isConfirmedRideAcceptResponse(
        const {'rideId': 'ride-1', 'status': 'requested'},
        'ride-1',
      ),
      isFalse,
    );
  });
}

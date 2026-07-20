import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart';

VehicleOption option(String id, {required bool available}) {
  return VehicleOption(
    id: id,
    name: id,
    description: '',
    capacityPersons: 4,
    farePesewas: 1000,
    estimatedTime: '3 min',
    isMotorcycle: false,
    driversAvailable: available,
  );
}

void main() {
  test('one available category keeps the route bookable', () {
    final options = [
      option('regular', available: false),
      option('comfort', available: true),
    ];

    expect(hasAvailableRideOption(options), isTrue);
    expect(firstAvailableRideOption(options)?.id, 'comfort');
    expect(availableRideOptionById(options, 'regular'), isNull);
    expect(availableRideOptionById(options, 'comfort')?.id, 'comfort');
  });

  test('all unavailable categories block the route', () {
    final options = [
      option('regular', available: false),
      option('comfort', available: false),
    ];

    expect(hasAvailableRideOption(options), isFalse);
    expect(firstAvailableRideOption(options), isNull);
  });
}

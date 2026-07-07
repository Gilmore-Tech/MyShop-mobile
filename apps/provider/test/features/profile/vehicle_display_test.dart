import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/profile/utils/vehicle_display.dart';

DriverProfile _driver({
  String? make,
  String? model,
  String? year,
  String? plate,
  String? color,
}) {
  return DriverProfile(
    id: 'driver_1',
    legalName: 'Driver One',
    displayName: 'Driver One',
    ghanaCardVerified: false,
    verificationStatus: 'pending',
    kycStatus: 'not_started',
    policeCheckStatus: 'not_started',
    onlineStatus: 'offline',
    serviceRadiusKm: 5,
    payoutPreference: 'standard',
    cancellationCount30d: 0,
    languagePref: 'en',
    vehicleMake: make,
    vehicleModel: model,
    vehicleYear: year,
    vehiclePlate: plate,
    vehicleColor: color,
  );
}

void main() {
  test('shows partial vehicle details instead of hiding them behind plate', () {
    final profile = _driver(make: 'Toyota', model: 'Vitz', year: '2021');

    expect(driverVehicleSubtitle(profile), 'Toyota Vitz 2021');
    expect(driverVehicleName(profile), 'Toyota Vitz');
    expect(hasDriverVehicleDetails(profile), isTrue);
    expect(hasCompleteDriverVehicleDetails(profile), isFalse);
  });

  test('includes plate when present', () {
    final profile = _driver(
      make: 'Toyota',
      model: 'Vitz',
      year: '2021',
      plate: 'GR-1234-26',
    );

    expect(driverVehicleSubtitle(profile), 'Toyota Vitz 2021 (GR-1234-26)');
  });

  test('requires the full signup vehicle record for online eligibility', () {
    final profile = _driver(
      make: 'Toyota',
      model: 'Vitz',
      year: '2021',
      plate: 'GR-1234-26',
      color: 'White',
    );

    expect(hasDriverVehicleDetails(profile), isTrue);
    expect(hasCompleteDriverVehicleDetails(profile), isTrue);
  });

  test('falls back only when no vehicle fields exist', () {
    final profile = _driver();

    expect(driverVehicleSubtitle(profile), 'Not set up yet');
    expect(driverVehicleName(profile), 'No vehicle added');
    expect(hasDriverVehicleDetails(profile), isFalse);
    expect(hasCompleteDriverVehicleDetails(profile), isFalse);
  });
}

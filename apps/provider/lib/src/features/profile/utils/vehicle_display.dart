import 'package:api_client/api_client.dart';

bool _hasText(String? value) => value != null && value.trim().isNotEmpty;

/// Compact vehicle summary used on the account hub.
///
/// New provider profiles can temporarily have a partial vehicle record while
/// admin/back-office verification catches up. Do not hide make/model/year just
/// because the plate is missing.
String driverVehicleSubtitle(DriverProfile? profile) {
  if (profile == null) return 'Not set up yet';

  final vehicleName = [
    profile.vehicleMake,
    profile.vehicleModel,
    profile.vehicleYear,
  ].where(_hasText).map((v) => v!.trim()).join(' ');
  final plate = profile.vehiclePlate?.trim();

  if (vehicleName.isEmpty && !_hasText(plate)) return 'Not set up yet';
  if (_hasText(plate)) {
    return vehicleName.isEmpty ? plate! : '$vehicleName ($plate)';
  }
  return vehicleName;
}

/// Full vehicle title used by the driver vehicle-information screen.
String driverVehicleName(DriverProfile? profile) {
  final name = [
    profile?.vehicleMake,
    profile?.vehicleModel,
  ].where(_hasText).map((v) => v!.trim()).join(' ');
  return name.isEmpty ? 'No vehicle added' : name;
}

bool hasDriverVehicleDetails(DriverProfile? profile) {
  return _hasText(profile?.vehicleMake) ||
      _hasText(profile?.vehicleModel) ||
      _hasText(profile?.vehicleYear) ||
      _hasText(profile?.vehiclePlate) ||
      _hasText(profile?.vehicleColor);
}

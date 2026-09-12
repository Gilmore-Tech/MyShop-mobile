const String regularRideCategoryIcon =
    'assets/images/ride_categories/regular.png';
const String comfortRideCategoryIcon =
    'assets/images/ride_categories/comfort.png';
const String carDeliveryRideCategoryIcon =
    'assets/images/ride_categories/car_delivery.png';
const String akwaabaCargoRideCategoryIcon =
    'assets/images/ride_categories/akwaaba_cargo.png';
const String motorcycleDeliveryRideCategoryIcon =
    'assets/images/ride_categories/motorcycle_delivery.png';

String _normaliseRideCategoryKey(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

/// Resolves both the backend slug and the admin-controlled display name.
///
/// Production categories beyond Regular and Comfort can be created in the
/// dashboard, so relying on one guessed slug would make their icons brittle.
/// Unknown future categories intentionally return null and retain the generic
/// vehicle icon in the estimate card.
String? rideCategoryIconAsset({required String id, required String name}) {
  final keys = {_normaliseRideCategoryKey(id), _normaliseRideCategoryKey(name)};

  if (keys.contains('regular')) return regularRideCategoryIcon;
  if (keys.contains('comfort') || keys.contains('ridecomfort')) {
    return comfortRideCategoryIcon;
  }
  if (keys.contains('cardelivery')) return carDeliveryRideCategoryIcon;
  if (keys.contains('akwaabakiacargo') ||
      keys.contains('akwaabakiyacargo') ||
      keys.contains('akwaabacargo') ||
      keys.contains('kiacargo')) {
    return akwaabaCargoRideCategoryIcon;
  }
  if (keys.contains('motorcycledelivery') ||
      keys.contains('motordelivery') ||
      keys.contains('motodelivery')) {
    return motorcycleDeliveryRideCategoryIcon;
  }

  return null;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/features/ride/utils/ride_category_icon.dart';

void main() {
  test('maps every requested production category name to its vehicle icon', () {
    expect(
      rideCategoryIconAsset(id: 'regular', name: 'Regular'),
      regularRideCategoryIcon,
    );
    expect(
      rideCategoryIconAsset(id: 'comfort', name: 'Comfort'),
      comfortRideCategoryIcon,
    );
    expect(
      rideCategoryIconAsset(id: 'custom-1', name: 'Car Delivery'),
      carDeliveryRideCategoryIcon,
    );
    expect(
      rideCategoryIconAsset(id: 'custom-2', name: 'Akwaaba Kia/Cargo'),
      akwaabaCargoRideCategoryIcon,
    );
    expect(
      rideCategoryIconAsset(id: 'custom-3', name: 'Motorcycle Delivery'),
      motorcycleDeliveryRideCategoryIcon,
    );
  });

  test('maps likely kebab-case production slugs when names change', () {
    expect(
      rideCategoryIconAsset(id: 'car-delivery', name: 'Delivery'),
      carDeliveryRideCategoryIcon,
    );
    expect(
      rideCategoryIconAsset(id: 'akwaaba-kia-cargo', name: 'Cargo'),
      akwaabaCargoRideCategoryIcon,
    );
    expect(
      rideCategoryIconAsset(id: 'motorcycle-delivery', name: 'Delivery'),
      motorcycleDeliveryRideCategoryIcon,
    );
  });

  test('keeps the generic fallback for an unknown future category', () {
    expect(
      rideCategoryIconAsset(id: 'future-tier', name: 'Future Tier'),
      isNull,
    );
  });
}

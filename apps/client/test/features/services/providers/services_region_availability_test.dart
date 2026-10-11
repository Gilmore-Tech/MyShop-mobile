import 'package:api_client/api_client.dart' as api;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/core/providers/current_operational_region_provider.dart';
import 'package:myshop_client/src/features/services/providers/services_provider.dart';

class _MockCategoryService extends Mock implements api.CategoryService {}

void main() {
  test('loads the public catalogue outside an operational region', () async {
    final categoryService = _MockCategoryService();
    when(() => categoryService.getCategories()).thenAnswer(
      (_) async => const [
        api.ServiceCategory(
          id: 'plumbing',
          name: 'Plumbing',
          slug: 'plumbing',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        currentOperationalRegionProvider.overrideWith((_) async => null),
        categoryServiceProvider.overrideWithValue(categoryService),
      ],
    );
    addTearDown(container.dispose);

    final categories = await container.read(serviceCategoriesProvider.future);

    expect(categories, hasLength(1));
    expect(categories.single.name, 'Plumbing');
    verify(() => categoryService.getCategories()).called(1);
  });

  test('keeps artisan categories hidden in a resolved ride-only region',
      () async {
    final categoryService = _MockCategoryService();
    final container = ProviderContainer(
      overrides: [
        currentOperationalRegionProvider.overrideWith(
          (_) async => const api.Region(
            id: 'bono',
            name: 'Bono Region',
            code: 'bono',
            ridesEnabled: true,
            jobsEnabled: false,
            serviceAreaName: 'Sunyani',
          ),
        ),
        categoryServiceProvider.overrideWithValue(categoryService),
      ],
    );
    addTearDown(container.dispose);

    final categories = await container.read(serviceCategoriesProvider.future);

    expect(categories, isEmpty);
    verifyNever(() => categoryService.getCategories());
  });
}

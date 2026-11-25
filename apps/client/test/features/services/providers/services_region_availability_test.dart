import 'package:api_client/api_client.dart' as api;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/core/providers/current_operational_region_provider.dart';
import 'package:myshop_client/src/features/services/providers/services_provider.dart';

class _MockCategoryService extends Mock implements api.CategoryService {}

void main() {
  test('loads only the selected jobs township when booking from elsewhere',
      () async {
    final service = _MockCategoryService();
    final container = ProviderContainer(overrides: [
      currentOperationalRegionProvider.overrideWith((_) async => null),
      categoryServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    expect(await container.read(serviceCategoriesProvider.future), isEmpty);
    verifyZeroInteractions(service);
    for (final id in ['accra', 'cape-coast']) {
      when(() => service.getCategories(regionId: id)).thenAnswer(
        (_) async =>
            [api.ServiceCategory(id: id, name: 'Plumber', slug: 'plumber')],
      );
      container.read(selectedJobTownshipProvider.notifier).state = id;
      final categories = await container.read(serviceCategoriesProvider.future);
      expect(categories.single.id, id);
      verify(() => service.getCategories(regionId: id)).called(1);
    }
    verifyNever(() => service.getCategories());
  });

  test('defaults the catalogue to the current jobs township', () async {
    final service = _MockCategoryService();
    when(() => service.getCategories(regionId: 'takoradi'))
        .thenAnswer((_) async => []);
    final container = ProviderContainer(overrides: [
      currentOperationalRegionProvider.overrideWith((_) async =>
          const api.Region(id: 'takoradi', name: 'Takoradi', code: 'TAK')),
      categoryServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    await container.read(serviceCategoriesProvider.future);
    verify(() => service.getCategories(regionId: 'takoradi')).called(1);
  });
}

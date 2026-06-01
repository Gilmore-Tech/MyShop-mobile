import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

/// Provides [CategoryService] backed by the app's Dio client.
final categoryServiceProvider = Provider<CategoryService>((ref) {
  return CategoryService(ref.watch(dioProvider));
});

/// Fetches the full service category tree from GET /v1/categories.
/// Cached for the lifetime of the provider — call `ref.invalidate` to refresh.
final categoriesProvider = FutureProvider<List<ServiceCategory>>((ref) async {
  return ref.watch(categoryServiceProvider).getCategories();
});

/// Flattened list of selectable (leaf) categories.
///
/// Top-level categories without children are selectable directly.
/// For categories with children (e.g. "Repairs"), only the children
/// are selectable — the parent is used as a group header.
final selectableCategoriesProvider =
    Provider<AsyncValue<List<ServiceCategory>>>((ref) {
  return ref.watch(categoriesProvider).whenData((categories) {
    final result = <ServiceCategory>[];
    for (final cat in categories) {
      if (cat.hasChildren) {
        result.addAll(cat.children);
      } else {
        result.add(cat);
      }
    }
    return result;
  });
});

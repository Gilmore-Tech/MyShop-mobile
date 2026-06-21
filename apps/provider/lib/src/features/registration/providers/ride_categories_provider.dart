import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

/// A selectable ride category in driver signup.
class RideCategoryOption {
  const RideCategoryOption({
    required this.slug,
    required this.name,
    required this.description,
  });

  final String slug;
  final String name;
  final String description;
}

/// Fetches the active ride categories (GET /ride-categories) the driver can opt
/// into at signup. Each selection is admin-verified before it becomes matchable.
final rideCategoryOptionsProvider =
    FutureProvider<List<RideCategoryOption>>((ref) async {
  final rideService = ref.read(rideServiceProvider);
  final raw = await rideService.listRideCategories();
  return raw
      .map((c) => RideCategoryOption(
            slug: c['slug'] as String,
            name: c['name'] as String? ?? c['slug'] as String,
            description: c['description'] as String? ?? '',
          ))
      .toList();
});

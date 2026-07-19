import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

final providerVehicleServiceProvider = Provider<ProviderVehicleService>((ref) {
  return ProviderVehicleService(ref.watch(dioProvider));
});

final providerVehiclesProvider =
    FutureProvider.autoDispose<ProviderVehiclesResponse>((ref) {
  return ref.watch(providerVehicleServiceProvider).listMyVehicles();
});

final providerVehicleRideCategoriesProvider =
    FutureProvider.autoDispose<List<ProviderRideCategoryChoice>>((ref) {
  return ref.watch(providerVehicleServiceProvider).listActiveRideCategories();
});

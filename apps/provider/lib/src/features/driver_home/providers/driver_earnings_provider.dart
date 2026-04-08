import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

/// Provides the driver's earnings summary for today.
///
/// In production this would fetch from the API; currently uses mock data
/// so the UI can be built and verified.
final driverEarningsProvider = FutureProvider<DriverEarnings>((ref) async {
  // TODO: Replace with actual API call via repository
  // final repository = ref.watch(driverRepositoryProvider);
  // return repository.getTodayEarnings();

  // Mock data for UI development
  await Future<void>.delayed(const Duration(milliseconds: 400));
  return const DriverEarnings(
    todayAmountPesewas: 14750,
    todayTrips: 8,
    weekAmountPesewas: 82300,
    hoursOnline: 6.5,
    acceptanceRate: 0.92,
  );
});

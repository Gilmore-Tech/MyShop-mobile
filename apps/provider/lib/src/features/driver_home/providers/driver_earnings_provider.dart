import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';
import '../data/earnings_service.dart';

/// Provides [EarningsService] backed by the app's Dio client.
final earningsServiceProvider = Provider<EarningsService>((ref) {
  return EarningsService(ref.watch(dioProvider));
});

/// Provides the driver's earnings summary for today.
///
/// Calls GET /payments/earnings?period=today. Falls back to
/// [DriverEarnings.empty] if the endpoint is unavailable or returns no data.
final driverEarningsProvider = FutureProvider<DriverEarnings>((ref) async {
  try {
    return await ref.watch(earningsServiceProvider).getEarnings();
  } catch (_) {
    return DriverEarnings.empty;
  }
});

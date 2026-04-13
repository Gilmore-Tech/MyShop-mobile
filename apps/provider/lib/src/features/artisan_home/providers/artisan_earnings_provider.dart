import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../../driver_home/providers/driver_earnings_provider.dart';

/// Provides the artisan's earnings summary for today.
///
/// Reuses the same [EarningsService] as the driver — the backend
/// differentiates by the authenticated user's role.
final artisanEarningsProvider = FutureProvider<DriverEarnings>((ref) async {
  try {
    return await ref.watch(earningsServiceProvider).getEarnings();
  } catch (_) {
    return DriverEarnings.empty;
  }
});

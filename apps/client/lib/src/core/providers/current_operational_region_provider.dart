import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../di/providers.dart';
import 'current_location_provider.dart';

/// Resolves the client's physical operational region from the shared device
/// fix. Service availability comes from the returned region flags; the
/// resolution itself is deliberately service-neutral so a ride-only region is
/// not mistaken for being outside the platform when jobs are disabled there.
final currentOperationalRegionProvider = FutureProvider<Region?>((ref) async {
  final position = ref.watch(currentDevicePositionProvider);
  if (position == null) return null;

  return ref.watch(regionServiceProvider).resolveCurrentRegion(
        latitude: position.latitude,
        longitude: position.longitude,
        // Kept for compatibility with older API deployments. Current servers
        // resolve the physical region first and return both service flags.
        service: 'rides',
      );
});

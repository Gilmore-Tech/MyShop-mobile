import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

/// Fetches the active platform regions (GET /v1/regions) a provider can pick
/// as their home region at signup. Public — no auth header. Cached for the
/// signup session; invalidate to force a re-fetch (e.g. after INVALID_REGION).
///
/// During the Ashanti pilot this returns exactly one region, which the region
/// step pre-selects. Returns an empty list if the endpoint is unavailable, in
/// which case signup proceeds with no `regionId` and the backend defaults to
/// the active pilot region.
final regionsProvider = FutureProvider<List<Region>>((ref) async {
  return ref.read(regionServiceProvider).getRegions();
});

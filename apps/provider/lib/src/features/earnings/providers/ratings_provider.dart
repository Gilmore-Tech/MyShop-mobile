import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../profile/providers/provider_type_provider.dart';
import '../data/ratings_service.dart';

/// Provides [RatingsService] backed by the app's Dio client.
final ratingsServiceProvider = Provider<RatingsService>((ref) {
  return RatingsService(ref.watch(dioProvider));
});

/// Aggregated ratings summary for the authenticated provider, scoped to
/// the **active role**.
///
/// A user holding both a driver and an artisan profile has one row per
/// rating in the `ratings` table tagged with `booking_type='ride'` or
/// `'artisan_job'`. Without passing the active role to the backend,
/// `GET /providers/me/ratings` returns the combined average — which
/// surfaced as "the driver's rating shows on the artisan dashboard" on
/// 14 May.
///
/// `providerTypeProvider` is the dashboard's source of truth for the
/// active role; watching it here means the rating chip auto-refreshes
/// when the user switches roles in-session.
final providerRatingsProvider =
    FutureProvider<ProviderRatingsSummary>((ref) async {
  final role = ref.watch(providerTypeProvider);
  return ref
      .watch(ratingsServiceProvider)
      .getProviderRatings(role: role.isDriver ? 'driver' : 'artisan');
});

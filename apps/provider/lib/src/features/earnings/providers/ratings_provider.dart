import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../data/ratings_service.dart';

/// Provides [RatingsService] backed by the app's Dio client.
final ratingsServiceProvider = Provider<RatingsService>((ref) {
  return RatingsService(ref.watch(dioProvider));
});

/// Aggregated ratings summary for the authenticated provider.
///
/// Used by the driver and artisan earnings dashboards to populate the
/// rating stat tile. Returns [ProviderRatingsSummary.empty] when the
/// endpoint is unreachable, so the UI renders a calm placeholder rather
/// than an error.
final providerRatingsProvider =
    FutureProvider<ProviderRatingsSummary>((ref) async {
  return ref.watch(ratingsServiceProvider).getProviderRatings();
});

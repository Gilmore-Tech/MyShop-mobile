import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

/// Active provider-audience promo campaigns (commission relief).
///
/// The backend filters `GET /promos/active` by the caller's token role,
/// so a driver/artisan only ever receives their role's commission-relief
/// campaigns. Promo failures must never break home or earnings: any
/// error (network, auth, malformed payload) collapses to an empty list
/// and every promo surface renders nothing. The backend serves
/// `{ campaigns: [] }` when the feature flag is off, which lands here as
/// the same empty list.
final activePromoCampaignsProvider =
    FutureProvider<List<ActivePromoCampaign>>((ref) async {
  try {
    return await ref.watch(promoServiceProvider).getActiveCampaigns();
  } catch (_) {
    return const [];
  }
});

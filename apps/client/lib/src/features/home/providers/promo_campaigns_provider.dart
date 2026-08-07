import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

/// Active promotional campaigns for the home banner carousel.
///
/// Promo failures must never break home: any error (network, auth,
/// malformed payload) collapses to an empty list, and the carousel
/// renders nothing. The backend serves `{ campaigns: [] }` when the
/// feature is off, which lands here as the same empty list.
final activePromoCampaignsProvider =
    FutureProvider<List<ActivePromoCampaign>>((ref) async {
  try {
    return await ref.watch(promoServiceProvider).getActiveCampaigns();
  } catch (_) {
    return const [];
  }
});

import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

/// Active and recently completed provider incentive campaigns.
///
/// The backend filters `GET /promos/active` by the caller's token role,
/// so a driver/artisan only ever receives their role's provider incentive
/// campaigns. Promo failures must never break home or earnings: any
/// error (network, auth, malformed payload) collapses to an empty list
/// and every promo surface renders nothing. The backend serves
/// `{ campaigns: [] }` when the feature flag is off, which lands here as
/// the same empty list.
final activePromoCampaignsProvider =
    FutureProvider.autoDispose<List<ActivePromoCampaign>>((ref) async {
  // Refresh only while a promo surface is visible. This keeps target
  // checkmarks reasonably fresh without background polling or Redis/map
  // traffic; the endpoint performs no map reads.
  final refresh = Timer(const Duration(minutes: 2), ref.invalidateSelf);
  ref.onDispose(refresh.cancel);
  try {
    return await ref.watch(promoServiceProvider).getActiveCampaigns();
  } catch (_) {
    return const [];
  }
});

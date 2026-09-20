import 'dart:async';

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
  var refresh = Timer(const Duration(minutes: 1), ref.invalidateSelf);
  ref.onDispose(() => refresh.cancel());
  try {
    final campaigns =
        await ref.watch(promoServiceProvider).getActiveCampaigns();
    refresh.cancel();
    refresh = Timer(_nextPromoRefresh(campaigns), ref.invalidateSelf);
    return campaigns;
  } catch (_) {
    return const [];
  }
});

Duration _nextPromoRefresh(List<ActivePromoCampaign> campaigns) {
  const maximum = Duration(minutes: 1);
  final now = DateTime.now();
  Duration delay = maximum;
  for (final campaign in campaigns) {
    final end = campaign.endsAt;
    if (end == null || !now.isBefore(end)) continue;
    final untilEnd = end.difference(now) + const Duration(milliseconds: 100);
    if (untilEnd < delay) delay = untilEnd;
  }
  return delay;
}

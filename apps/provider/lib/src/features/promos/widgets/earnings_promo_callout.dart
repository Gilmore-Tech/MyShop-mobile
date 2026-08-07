import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/promo_campaigns_provider.dart';
import 'promo_details_sheet.dart';

/// Compact gold-light callout on the earnings dashboard advertising the
/// active commission-relief campaign with the highest relief percentage.
///
/// "Active promo: 50% commission relief until 31 Aug 2026" — tapping it
/// opens the same campaign details sheet as the home banner carousel.
/// Renders nothing (zero height) when no relief campaign is active,
/// while loading, or on any promo fetch failure.
class EarningsPromoCallout extends ConsumerWidget {
  const EarningsPromoCallout({super.key});

  /// Highest-relief active campaign, or null when none qualifies.
  /// Stable on ties — the server's ordering wins.
  static ActivePromoCampaign? bestReliefCampaign(
    List<ActivePromoCampaign> campaigns,
  ) {
    ActivePromoCampaign? best;
    for (final c in campaigns) {
      if (!c.isCommissionRelief || c.discountValue <= 0) continue;
      if (best == null || c.discountValue > best.discountValue) best = c;
    }
    return best;
  }

  static String calloutText(ActivePromoCampaign c) {
    final pct = c.discountValue.toDouble() ==
            c.discountValue.toDouble().truncateToDouble()
        ? c.discountValue.toDouble().toStringAsFixed(0)
        : c.discountValue.toDouble().toStringAsFixed(1);
    final ends = c.endsAt;
    if (ends == null) return 'Active promo: $pct% commission relief';
    final until = DateFormat('d MMM yyyy').format(ends.toLocal());
    return 'Active promo: $pct% commission relief until $until';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaigns = ref.watch(activePromoCampaignsProvider).valueOrNull ??
        const <ActivePromoCampaign>[];
    final best = bestReliefCampaign(campaigns);
    if (best == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        0,
        MyShopSpacing.md,
        MyShopSpacing.sm,
      ),
      child: GestureDetector(
        key: const Key('earnings-promo-callout'),
        behavior: HitTestBehavior.opaque,
        onTap: () => showPromoDetailsSheet(context, best),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: MyShopSpacing.md,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: MyShopColors.primaryGoldLight,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.local_offer_rounded,
                size: 16,
                color: MyShopColors.primaryGoldDark,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  calloutText(best),
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: MyShopColors.primaryGoldDark,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

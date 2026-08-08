import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/promo_campaigns_provider.dart';
import 'promo_details_sheet.dart';

/// PROMOS section — header + horizontally scrollable banner carousel of
/// active provider-audience (commission relief) campaigns.
///
/// Rendered on both the driver and artisan home dashboards. Collapses to
/// zero height when there are no active campaigns with a banner image —
/// loading, error, feature-off, and image-load-failure states are all
/// silent. The server orders by `bannerPriority` desc; we re-sort
/// defensively (stable, so server order is preserved for ties).
class PromosSection extends ConsumerWidget {
  const PromosSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaigns = ref.watch(activePromoCampaignsProvider).valueOrNull ??
        const <ActivePromoCampaign>[];
    final banners = campaigns.where((c) => c.hasBanner).toList()
      ..sort((a, b) => b.bannerPriority.compareTo(a.bannerPriority));

    if (banners.isEmpty) return const SizedBox.shrink();

    final h = MediaQuery.sizeOf(context).height;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Section header — matches the home dashboards' section idiom
        // (LIVE JOB FEED / Recent Activity): md padding, overline type.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_offer_rounded,
                size: 16,
                color: MyShopColors.primaryGold,
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Text(
                'PROMOS',
                style: MyShopTypography.overline.copyWith(
                  color: MyShopColors.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: MyShopSpacing.md),
        SizedBox(
          height: h * 0.155,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
            itemCount: banners.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: MyShopSpacing.sm + 4),
            itemBuilder: (_, i) => _PromoBanner(campaign: banners[i]),
          ),
        ),
        const SizedBox(height: MyShopSpacing.lg),
      ],
    );
  }
}

class _PromoBanner extends StatelessWidget {
  const _PromoBanner({required this.campaign});

  final ActivePromoCampaign campaign;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return GestureDetector(
      key: Key('promo-banner-${campaign.id}'),
      onTap: () => showPromoDetailsSheet(context, campaign),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          campaign.bannerUrl!,
          width: w * 0.78,
          fit: BoxFit.cover,
          // A broken banner image hides itself entirely rather than
          // rendering a broken-image placeholder in the carousel.
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: w * 0.78,
              decoration: BoxDecoration(
                color: MyShopColors.shimmerBase,
                borderRadius: BorderRadius.circular(14),
              ),
            );
          },
        ),
      ),
    );
  }
}

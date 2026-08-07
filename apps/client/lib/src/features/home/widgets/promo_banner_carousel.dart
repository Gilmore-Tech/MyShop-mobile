import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/promo_campaigns_provider.dart';
import 'promo_details_sheet.dart';

/// Horizontally scrollable promo banner carousel shown at the top of the
/// home screen.
///
/// Renders nothing at all (zero height) when there are no active
/// campaigns with a banner image — loading, error, feature-off, and
/// image-load-failure states are all silent. The server orders by
/// `bannerPriority` desc; we re-sort defensively (stable, so server
/// order is preserved for ties).
class PromoBannerCarousel extends ConsumerWidget {
  const PromoBannerCarousel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final campaignsAsync = ref.watch(activePromoCampaignsProvider);
    final banners = (campaignsAsync.valueOrNull ?? const <ActivePromoCampaign>[])
        .where((c) => c.hasBanner)
        .toList()
      ..sort((a, b) => b.bannerPriority.compareTo(a.bannerPriority));

    if (banners.isEmpty) return const SizedBox.shrink();

    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: h * 0.155,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: w * 0.041),
            itemCount: banners.length,
            separatorBuilder: (_, __) => SizedBox(width: w * 0.031),
            itemBuilder: (_, i) => _PromoBanner(campaign: banners[i]),
          ),
        ),
        SizedBox(height: h * 0.02),
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

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/promo_campaigns_provider.dart';
import 'promo_details_sheet.dart';

/// PROMOS section for active/recent provider incentives.
///
/// Rendered on both the driver and artisan home dashboards. Collapses to
/// zero height when there are no campaigns —
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
    final progressCampaigns = campaigns
        .where((campaign) => campaign.providerPromo != null)
        .toList(growable: false);

    if (banners.isEmpty && progressCampaigns.isEmpty) {
      return const SizedBox.shrink();
    }

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
        if (progressCampaigns.isNotEmpty) ...[
          const SizedBox(height: MyShopSpacing.md),
          SizedBox(
            height: 218,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              itemCount: progressCampaigns.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: MyShopSpacing.sm + 4),
              itemBuilder: (_, i) =>
                  _ProviderPromoProgressCard(campaign: progressCampaigns[i]),
            ),
          ),
        ],
        if (banners.isNotEmpty) ...[
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
        ],
        const SizedBox(height: MyShopSpacing.lg),
      ],
    );
  }
}

class _ProviderPromoProgressCard extends StatelessWidget {
  const _ProviderPromoProgressCard({required this.campaign});

  final ActivePromoCampaign campaign;

  static String _money(int pesewas) => (pesewas / 100).toStringAsFixed(2);

  String _reward(ProviderPromoProgress progress) {
    if (progress.isCommissionRelief) {
      return '${progress.rewardValue}% commission relief';
    }
    if (progress.isGuaranteedEarnings) {
      return 'GHS ${_money(progress.rewardValue)} guaranteed earnings';
    }
    return 'GHS ${_money(progress.rewardValue)} reward';
  }

  @override
  Widget build(BuildContext context) {
    final progress = campaign.providerPromo!;
    final width = MediaQuery.sizeOf(context).width * 0.84;
    return InkWell(
      key: Key('promo-progress-${campaign.id}'),
      borderRadius: BorderRadius.circular(14),
      onTap: () => showPromoDetailsSheet(context, campaign),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MyShopColors.primaryGoldLight),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    campaign.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: MyShopColors.primaryGoldDark,
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              _reward(progress),
              style: const TextStyle(
                color: MyShopColors.primaryGoldDark,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress.overallProgress,
                minHeight: 6,
                backgroundColor: MyShopColors.surfaceGrey,
                color: progress.qualified
                    ? MyShopColors.success
                    : MyShopColors.primaryGold,
              ),
            ),
            const SizedBox(height: 9),
            if (progress.completedBookingsTarget != null)
              _ProgressLine(
                complete: progress.bookingsComplete,
                text: '${progress.completedBookings} / '
                    '${progress.completedBookingsTarget} trips or jobs',
              ),
            if (progress.verifiedOnlineMinutesTarget != null)
              _ProgressLine(
                complete: progress.onlineTimeComplete,
                text:
                    '${(progress.verifiedOnlineSeconds / 3600).toStringAsFixed(1)} / '
                    '${(progress.verifiedOnlineMinutesTarget! / 60).toStringAsFixed(1)} hours online',
              ),
            if (progress.generatedRevenueTargetPesewas != null)
              _ProgressLine(
                complete: progress.revenueComplete,
                text: 'GHS ${_money(progress.generatedRevenuePesewas)} / '
                    'GHS ${_money(progress.generatedRevenueTargetPesewas!)} revenue',
              ),
            const Spacer(),
            Text(
              progress.qualified
                  ? 'Requirements complete'
                  : 'Complete every selected target',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: progress.qualified
                    ? MyShopColors.success
                    : MyShopColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.complete, required this.text});

  final bool complete;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(
            complete
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked,
            size: 15,
            color: complete ? MyShopColors.success : MyShopColors.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: MyShopColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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

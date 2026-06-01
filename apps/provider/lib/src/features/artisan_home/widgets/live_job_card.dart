import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Live job feed card.
///
/// Top row: client avatar, name + verified badge, location, "URGENT" pill.
/// Middle: job title + posted-time row.
/// Footer (after dotted divider): "LAST SPOTS!" + bid count + progress bar +
/// dark "Quick Bid" CTA.
class LiveJobCard extends StatelessWidget {
  const LiveJobCard({
    super.key,
    required this.clientName,
    required this.locationLabel,
    required this.distanceKm,
    required this.jobTitle,
    required this.postedAgo,
    required this.bidsTaken,
    required this.bidsTotal,
    this.isUrgent = false,
    this.isVerified = false,
    this.avatarUrl,
    this.onQuickBid,
    this.onTap,
  });

  final String clientName;
  final String locationLabel;
  final double distanceKm;
  final String jobTitle;
  final String postedAgo;
  final int bidsTaken;
  final int bidsTotal;
  final bool isUrgent;
  final bool isVerified;
  final String? avatarUrl;
  final VoidCallback? onQuickBid;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final progress = bidsTotal == 0 ? 0.0 : bidsTaken / bidsTotal;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row: avatar + name + urgent pill ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: MyShopColors.avatarPlaceholder,
                    shape: BoxShape.circle,
                    image: avatarUrl != null
                        ? DecorationImage(
                            image: NetworkImage(avatarUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: avatarUrl == null
                      ? const Icon(Icons.person,
                          color: MyShopColors.textSecondary)
                      : null,
                ),
                const SizedBox(width: MyShopSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              clientName,
                              style: MyShopTypography.h3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.verified,
                              size: 16,
                              color: MyShopColors.info,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 14,
                            color: MyShopColors.primaryGold,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$locationLabel  •  ${distanceKm.toStringAsFixed(1)} km',
                            style: MyShopTypography.body2.copyWith(
                              color: MyShopColors.primaryGold,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isUrgent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: MyShopColors.error,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'URGENT',
                      style: MyShopTypography.caption.copyWith(
                        color: MyShopColors.textOnPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── Job title ──
            Text(
              jobTitle,
              style: MyShopTypography.h3.copyWith(fontSize: 17),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(
                  Icons.access_time,
                  size: 14,
                  color: MyShopColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  postedAgo,
                  style: MyShopTypography.body2,
                ),
              ],
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── Dotted divider ──
            const _DottedDivider(),
            const SizedBox(height: MyShopSpacing.md),

            // ── Footer: last spots + progress + quick bid ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'LAST SPOTS!',
                            style: MyShopTypography.overline.copyWith(
                              color: MyShopColors.error,
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: MyShopSpacing.sm),
                          Text(
                            '$bidsTaken/$bidsTotal',
                            style: MyShopTypography.body1,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: MyShopColors.surfaceGrey,
                          valueColor: const AlwaysStoppedAnimation(
                            MyShopColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: MyShopSpacing.md),
                GestureDetector(
                  onTap: onQuickBid,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: MyShopSpacing.md,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: MyShopColors.darkSlate,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      'Quick Bid',
                      style: MyShopTypography.button.copyWith(
                        color: MyShopColors.textOnDarkSlate,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DottedDivider extends StatelessWidget {
  const _DottedDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 4.0;
        const dashGap = 4.0;
        final count = (constraints.maxWidth / (dashWidth + dashGap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => Container(
              width: dashWidth,
              height: 1,
              color: MyShopColors.divider,
            ),
          ),
        );
      },
    );
  }
}

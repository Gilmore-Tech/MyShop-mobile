import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../widgets/artisan_home_header.dart';
import '../widgets/artisan_online_banner.dart';
import '../widgets/artisan_quick_actions.dart';
import '../widgets/emergency_request_modal.dart';
import '../widgets/live_job_card.dart';
import '../widgets/performance_summary_section.dart';
import '../widgets/special_offer_banner.dart';

/// Artisan Home — card-first dashboard for artisan providers.
///
/// PRD Reference: PRD 5.3 (Provider — Artisan View)
/// Layout (top to bottom):
///   1. Header (business name + region, notifications, avatar)
///   2. Online/Offline status banner
///   3. Performance Summary (Earnings, Avg Rating, Jobs Done)
///   4. Quick actions row (Schedule, Inbox, Payout)
///   5. Live Job Feed (cards)
///   6. Special offer banner
class ArtisanHomeScreen extends ConsumerStatefulWidget {
  const ArtisanHomeScreen({super.key});

  @override
  ConsumerState<ArtisanHomeScreen> createState() => _ArtisanHomeScreenState();
}

class _ArtisanHomeScreenState extends ConsumerState<ArtisanHomeScreen> {
  bool _isOnline = true;

  Future<void> _showEmergencyRequest(BuildContext context) {
    return EmergencyRequestModal.show(
      context,
      clientName: 'Ekow Taylor',
      clientRating: 5.0,
      jobTitle: 'AC Unit Leakage & Electrical Sparking',
      locationLabel: 'Asokwa, Kumasi',
      distanceKm: 0.8,
      countdown: const Duration(minutes: 5),
      onViewDetails: () => context.push('/job-request'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // 1. Header
            ArtisanHomeHeader(
              businessName: 'Jayso Ent.',
              region: 'Ashanti Region',
              hasUnreadNotifications: true,
              onNotificationsTap: () => _showEmergencyRequest(context),
              onAvatarTap: () {},
            ),

            // 2. Online status banner
            ArtisanOnlineBanner(
              isOnline: _isOnline,
              onToggle: () => setState(() => _isOnline = !_isOnline),
            ),

            const SizedBox(height: MyShopSpacing.lg),

            // 3. Performance summary
            PerformanceSummarySection(
              earnings: '450',
              earningsTrend: '5%',
              rating: '4.92',
              ratingPercentile: 'Top 5%',
              jobsDone: 25,
              onDetailsTap: () {},
            ),

            const SizedBox(height: MyShopSpacing.lg),

            // 4. Quick actions
            const ArtisanQuickActions(),

            const SizedBox(height: MyShopSpacing.lg),

            // 5. Live job feed header
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MyShopSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: MyShopColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: MyShopSpacing.sm),
                  Expanded(
                    child: Text(
                      'LIVE JOB FEED',
                      style: MyShopTypography.overline.copyWith(
                        color: MyShopColors.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: MyShopColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: MyShopColors.divider),
                    ),
                    child: Text(
                      '24 Nearby',
                      style: MyShopTypography.body2.copyWith(
                        color: MyShopColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // Live job card
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MyShopSpacing.md,
              ),
              child: LiveJobCard(
                clientName: 'Ama Serwaa',
                isVerified: true,
                locationLabel: 'Adum',
                distanceKm: 1.2,
                jobTitle: 'Burst Pipe in Kitchen - Emergency',
                postedAgo: '2 mins ago',
                bidsTaken: 2,
                bidsTotal: 3,
                isUrgent: true,
                onQuickBid: () {},
                onTap: () {},
              ),
            ),

            const SizedBox(height: MyShopSpacing.lg),

            // 6. Special offer banner
            const SpecialOfferBanner(
              title: 'GHS 50 Off Electrical Fix',
              code: 'VOLT50',
            ),

            const SizedBox(height: MyShopSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

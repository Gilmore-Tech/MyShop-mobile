import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/providers/availability_controller.dart';
import '../../../core/providers/provider_status_provider.dart';
import '../../auth/providers/auth_controller.dart';
import '../../auth/providers/current_user_provider.dart';
import '../../earnings/providers/earnings_providers.dart';
import '../../earnings/providers/ratings_provider.dart';
import '../../profile/providers/verification_provider.dart';
import '../../profile/widgets/incomplete_profile_sheet.dart';
import 'package:shared_models/shared_models.dart' show EarningsRole;
import '../providers/live_job_feed_provider.dart';
import '../widgets/artisan_home_header.dart';
import '../widgets/artisan_online_banner.dart';
import '../widgets/live_job_feed_carousel.dart';
import '../widgets/performance_summary_section.dart';

/// Artisan Home — card-first dashboard for artisan providers.
///
/// PRD Reference: PRD 5.3 (Provider — Artisan View)
/// Layout (top to bottom):
///   1. Header (business name + region, notifications, avatar)
///   2. Online/Offline status banner
///   3. Performance Summary (Earnings, Avg Rating, Jobs Done)
///   4. Quick actions row (Schedule, Inbox, Payout)
///   5. Live Job Feed (empty state — no endpoint yet)
class ArtisanHomeScreen extends ConsumerStatefulWidget {
  const ArtisanHomeScreen({super.key});

  @override
  ConsumerState<ArtisanHomeScreen> createState() => _ArtisanHomeScreenState();
}

class _ArtisanHomeScreenState extends ConsumerState<ArtisanHomeScreen> {
  bool _isGoingOnline = false;

  Future<void> _handleToggle() async {
    final status = ref.read(providerStatusProvider);
    final availability = ref.read(availabilityControllerProvider);

    // Busy (active job) — toggle locked server-side and client-side.
    // Matches PRD 5.3: artisan can't go offline during an active job.
    if (status.isBusy) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("You can't go offline during an active job."),
        ),
      );
      return;
    }

    // Going offline: flip local state + fire backend offline POST so the
    // matcher stops dispatching.
    if (status.isOnline) {
      availability.goOffline();
      return;
    }

    setState(() => _isGoingOnline = true);
    try {
      // Force a fresh read of both the verification docs and the user
      // profile before deciding completeness — mid-session approvals
      // would otherwise be missed because Riverpod caches the verification
      // provider for the lifetime of the screen.
      ref.invalidate(verificationStatusProvider);
      await Future.wait<void>([
        ref
            .read(verificationStatusProvider.future)
            .then<void>((_) {})
            .catchError((_) {}),
        ref
            .read(authControllerProvider.notifier)
            .refreshProfile()
            .then<void>((_) {}),
      ]);

      if (!mounted) return;
      final completion = ref.read(profileCompletionProvider);

      if (!completion.isComplete) {
        showIncompleteProfileSheet(context, completion: completion);
        return;
      }

      final error = await availability.goOnline();
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoingOnline = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final cardAsync = ref.watch(todayCardProvider(EarningsRole.artisan));

    // Eagerly load verification status so profileCompletionProvider has data
    // ready when the user taps "Go Online" (avoids false incomplete state).
    ref.watch(verificationStatusProvider);

    // Derive service categories for the subtitle
    final categories = user?.artisanProfile?.serviceCategories
        ?.map((c) => c.category.name)
        .join(', ');

    // Today's effective earnings drives the headline. We use the
    // gross-minus-commission helper rather than `netEarningsPesewas`
    // because the latter is 0 for cash bookings (the artisan already
    // pocketed the gross; the commission lives in a Clawback row, not
    // a payout). Without the swap a cash-only day reads "GHS 0" even
    // though the artisan earned money — which is exactly the bug the
    // user reported.
    final earningsDisplay = cardAsync.when(
      data: (c) => _formatGhs(c.effectiveEarningsPesewas),
      loading: () => '...',
      error: (_, __) => '0',
    );
    final earningsTrend = cardAsync.when(
      data: (c) => c.tipsEarnedPesewas > 0
          ? '+${_formatGhs(c.tipsEarnedPesewas)} tips'
          : '--',
      loading: () => '--',
      error: (_, __) => '--',
    );

    // Driver/artisan ratings summary — drives the Rating tile in the
    // performance row. Distinct branches for loading / error / empty / data
    // so a brand-new provider, a backend hiccup, and a real value are each
    // visually distinguishable instead of all collapsing to "--".
    final ratingsAsync = ref.watch(providerRatingsProvider);
    final (String ratingDisplay, String ratingSubtitle) = ratingsAsync.when(
      loading: () => ('—', 'Loading…'),
      error: (_, __) => ('!', "Couldn't load ratings"),
      data: (r) => r.hasRatings
          ? (
              r.averageDisplay,
              '${r.count} ${r.count == 1 ? 'review' : 'reviews'}',
            )
          : ('--', 'No ratings yet'),
    );

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // 1. Header — real user data
            ArtisanHomeHeader(
              businessName:
                  user?.businessName ?? user?.displayName ?? 'My Business',
              region: categories != null && categories.isNotEmpty
                  ? categories
                  : 'Ghana',
              hasUnreadNotifications: false,
              avatarUrl: user?.profilePhotoUrl ??
                  ref.watch(localProfilePhotoProvider).cloudinaryUrl,
              localAvatarFile: ref.watch(localProfilePhotoProvider).localFile,
              onNotificationsTap: () => context.push('/notifications'),
              onAvatarTap: () {},
            ),

            // 2. Online status banner
            ArtisanOnlineBanner(
              isOnline: ref.watch(providerStatusProvider).isOnline,
              isWorking: _isGoingOnline,
              onToggle: _handleToggle,
            ),

            const SizedBox(height: MyShopSpacing.lg),

            // 3. Today's performance — all three tiles scoped to today
            // (UTC), refreshed live by `_bustEarningsCaches` whenever a
            // job lands as `completed`. The Rating tile carries an
            // all-time count because that's the only number the backend
            // surfaces for ratings — relabelling avoids implying it
            // resets at midnight.
            PerformanceSummarySection(
              earnings: earningsDisplay,
              earningsTrend: earningsTrend,
              rating: ratingDisplay,
              ratingPercentile: ratingSubtitle,
              jobsDone: cardAsync.when(
                data: (c) => c.bookingsCount,
                loading: () => 0,
                error: (_, __) => 0,
              ),
              onDetailsTap: () {},
            ),

            const SizedBox(height: MyShopSpacing.lg),

            // Live job feed header + body — counts and indicator dot turn live
            // when at least one snapshot has arrived via REST seed or the
            // `job:feed:new` socket event.
            _LiveJobFeedSection(),

            const SizedBox(height: MyShopSpacing.xxl),
          ],
        ),
      ),
    );
  }

  String _formatGhs(int pesewas) {
    final ghs = pesewas / 100;
    if (ghs == ghs.truncateToDouble()) {
      return ghs.toStringAsFixed(0);
    }
    return ghs.toStringAsFixed(2);
  }
}

/// Live job feed section: header (with data-driven count badge and indicator
/// dot) + body that switches between the existing empty-state placeholder
/// and the auto-scrolling [LiveJobFeedCarousel] as soon as the feed has at
/// least one snapshot.
class _LiveJobFeedSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(liveJobFeedProvider);
    final isLive = feed.isNotEmpty;
    final badgeText = isLive ? '${feed.length} live' : '0 Nearby';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isLive
                      ? MyShopColors.success
                      : MyShopColors.textSecondary.withValues(alpha: 0.4),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: MyShopColors.divider),
                ),
                child: Text(
                  badgeText,
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: MyShopSpacing.md),
        if (isLive)
          const LiveJobFeedCarousel()
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 40),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: MyShopColors.divider.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: MyShopColors.surfaceGrey,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.work_outline,
                      size: 24,
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  Text(
                    'No jobs nearby',
                    style: MyShopTypography.body1.copyWith(
                      color: MyShopColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: MyShopSpacing.xs),
                  Text(
                    'New job requests will appear here',
                    style: MyShopTypography.body2.copyWith(
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

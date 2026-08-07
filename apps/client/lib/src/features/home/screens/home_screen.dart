import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../../core/providers/current_location_label_provider.dart';
import '../../../core/providers/current_location_provider.dart';
import '../../../core/services/google_places_service.dart';
import '../../../core/utils/ride_service_area.dart';
import '../../profile/providers/profile_provider.dart';
import '../../ride/providers/ride_search_provider.dart';
import '../providers/home_provider.dart';
import '../providers/promo_campaigns_provider.dart';
import '../widgets/location_search_card.dart';
import '../widgets/promo_banner_carousel.dart';
import '../widgets/safety_banner.dart';
import '../widgets/service_card.dart';
import '../widgets/special_offer_card.dart';

/// PRD 4.2 — Client Home Screen
/// Card-based entry point for ride booking and artisan services.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(rideSearchProvider);
    final currentLabel = ref.watch(currentLocationLabelProvider).value;
    final currentPosition = ref.watch(currentDevicePositionProvider);
    final String pickupName =
        search.pickup?.name ?? currentLabel ?? 'Current location';
    final showRideAreaBanner = currentPosition != null &&
        isLikelyOutsideRideServiceArea(
          latitude: currentPosition.latitude,
          longitude: currentPosition.longitude,
        );

    final h = MediaQuery.sizeOf(context).height;
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: SafeArea(
        child: Column(
          children: [
            const _HomeGreeting(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: h * 0.03),
                    if (showRideAreaBanner) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: _RideServiceAreaBanner(),
                      ),
                      SizedBox(height: h * 0.02),
                    ] else
                      SizedBox(height: h * 0.02),
                    LocationSearchCard(
                      pickupLabel: pickupName,
                      onPickupTap: () =>
                          context.push(AppRoutes.rideSearchPath('pickup')),
                      onPickupPinTap: () =>
                          context.push(AppRoutes.ridePinPickerPath('pickup')),
                    ),
                    SizedBox(height: h * 0.05),
                    _ServiceCardsRow(),
                    SizedBox(height: h * 0.028),
                    // Promos live right under the booking cards, above recent
                    // activity. The whole section (header included) renders
                    // nothing when no active campaign carries a banner —
                    // promo failures must never break home.
                    const _PromosSection(),
                    _SpecialOffersSection(),
                    const _RecentActivitySection(),
                    SizedBox(height: h * 0.03),
                    const SafetyBanner(),
                    SizedBox(height: h * 0.028),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RideServiceAreaBanner extends StatelessWidget {
  const _RideServiceAreaBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MyShopColors.warningLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: MyShopColors.warning.withValues(alpha: 0.35),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: MyShopColors.warning,
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Rides may not be available here yet',
                  style: TextStyle(
                    color: MyShopColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Ride booking currently operates in $rideServiceAreaName. '
                  'If your pickup or destination is outside the service area, '
                  'fare estimates will not be available.',
                  style: TextStyle(
                    color: MyShopColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Greeting header ───────────────────────────────────────────────────────────

class _HomeGreeting extends ConsumerWidget {
  const _HomeGreeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(accountScreenProvider);
    final profile = accountAsync.value?.profile;
    final firstName = profile?.displayName.trim().split(' ').first ?? '';
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;

    return Padding(
      padding: EdgeInsets.fromLTRB(w * 0.041, h * 0.024, w * 0.041, h * 0.01),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Akwaaba',
                  style: TextStyle(
                    fontSize: w * 0.034,
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                  ),
                ),
                SizedBox(height: h * 0.0025),
                Text(
                  firstName.isEmpty ? '\u00A0' : firstName,
                  style: TextStyle(
                    fontSize: w * 0.057,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => context.go(AppRoutes.profile),
            child: _Avatar(
              avatarUrl: profile?.avatarUrl,
              initials: profile?.initials ?? '',
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;

  const _Avatar({required this.avatarUrl, required this.initials});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFE6EAF0),
        border: Border.all(color: MyShopColors.primaryGold, width: 2),
        image: avatarUrl != null
            ? DecorationImage(
                image: NetworkImage(avatarUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      alignment: Alignment.center,
      child: avatarUrl == null
          ? Text(
              initials.isEmpty ? '?' : initials,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: MyShopColors.darkSlate,
              ),
            )
          : null,
    );
  }
}

// ── Service cards ─────────────────────────────────────────────────────────────

class _ServiceCardsRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Row(
        children: [
          Expanded(
            child: ServiceCard(
              type: ServiceCardType.ride,
              onTap: () async {
                await _seedPickupFromCurrentLocation(ref);
                if (!context.mounted) return;
                context.push(AppRoutes.rideEstimate);
              },
            ),
          ),
          SizedBox(width: w * 0.031),
          Expanded(
            child: ServiceCard(
              type: ServiceCardType.artisan,
              onTap: () => context.go(AppRoutes.services),
            ),
          ),
        ],
      ),
    );
  }

  /// Carries the home-screen current location into the ride flow so the user
  /// doesn't have to pick it again. If GPS is ready but reverse-geocoding is
  /// still resolving, seed the precise coordinates immediately and refresh the
  /// human-readable label as soon as the backend returns it. This prevents the
  /// pickup from getting permanently stuck as the generic "Current location".
  Future<void> _seedPickupFromCurrentLocation(WidgetRef ref) async {
    if (ref.read(rideSearchProvider).pickup != null) return;
    var pos = ref.read(currentDevicePositionProvider);
    pos ??= await ref
        .read(currentLocationServiceProvider)
        .ensure()
        .timeout(const Duration(seconds: 8), onTimeout: () => null);
    if (pos == null) return;

    // Await the place tied to the provider's current GPS dependency rather
    // than reading `valueOrNull`: Riverpod retains the previous value while a
    // FutureProvider refreshes, which could pair an old address with these new
    // exact coordinates.
    ReverseGeocodePlace? place;
    try {
      place = await ref
          .read(currentLocationPlaceProvider.future)
          .timeout(const Duration(seconds: 2));
    } on TimeoutException {
      place = null;
    }

    _writePickup(ref, pos, place);

    if (_isGenericCurrentPlace(place)) {
      unawaited(_refreshPickupLabel(ref, pos));
    }
  }

  Future<ReverseGeocodePlace?> _reverseGeocodePosition(
    WidgetRef ref,
    Position pos,
  ) {
    return ref.read(googlePlacesServiceProvider).reverseGeocodePlace(
          pos.latitude,
          pos.longitude,
        );
  }

  Future<void> _refreshPickupLabel(WidgetRef ref, Position pos) async {
    final place = await _reverseGeocodePosition(ref, pos);
    if (_isGenericCurrentPlace(place)) return;
    final current = ref.read(rideSearchProvider).pickup;
    if (current == null) return;
    if (!_sameCoordinate(current.lat, pos.latitude) ||
        !_sameCoordinate(current.lng, pos.longitude)) {
      return;
    }
    _writePickup(ref, pos, place);
  }

  void _writePickup(
    WidgetRef ref,
    Position pos,
    ReverseGeocodePlace? place,
  ) {
    final label = _isGenericCurrentPlace(place)
        ? 'Pickup selected from GPS'
        : place!.name;
    ref.read(rideSearchProvider.notifier).setLocation(
          RideSearchField.pickup,
          RideLocation(
            name: label,
            address: _isGenericCurrentPlace(place) ? label : place!.address,
            lat: pos.latitude,
            lng: pos.longitude,
          ),
        );
  }

  bool _isGenericCurrentPlace(ReverseGeocodePlace? place) {
    final name = place?.name.trim().toLowerCase();
    return name == null ||
        name.isEmpty ||
        name == 'current location' ||
        name == 'using gps location';
  }

  bool _sameCoordinate(double? a, double b) {
    if (a == null) return false;
    return (a - b).abs() < 0.00001;
  }
}

// ── Special offers ────────────────────────────────────────────────────────────

class _PromosSection extends ConsumerWidget {
  const _PromosSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = MediaQuery.sizeOf(context).height;
    final campaigns = ref.watch(activePromoCampaignsProvider).valueOrNull ??
        const <ActivePromoCampaign>[];
    final hasBanners = campaigns.any((c) => c.hasBanner);
    if (!hasBanners) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionHeader(
          title: 'PROMOS',
          leadingIcon: Icons.local_offer_rounded,
        ),
        SizedBox(height: h * 0.014),
        const PromoBannerCarousel(),
        SizedBox(height: h * 0.028),
      ],
    );
  }
}

class _SpecialOffersSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offersAsync = ref.watch(specialOffersProvider);

    return offersAsync.when(
      // Offers are intentionally unavailable in this release. Do not flash a
      // temporary promo skeleton that immediately disappears into empty data.
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (offers) {
        if (offers.isEmpty) return const SizedBox.shrink();
        return _content(
          context,
          ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.sizeOf(context).width * 0.041,
            ),
            itemCount: offers.length,
            separatorBuilder: (_, __) =>
                SizedBox(width: MediaQuery.sizeOf(context).width * 0.031),
            itemBuilder: (_, i) => SpecialOfferCard(offer: offers[i]),
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context, Widget child) {
    final h = MediaQuery.sizeOf(context).height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionHeader(
          title: 'SPECIAL OFFERS',
          leadingIcon: Icons.local_offer_rounded,
        ),
        SizedBox(height: h * 0.014),
        SizedBox(
          height: h * 0.175,
          child: child,
        ),
        SizedBox(height: h * 0.028),
      ],
    );
  }
}

// ── Recent activity ───────────────────────────────────────────────────────────

class _RecentActivitySection extends ConsumerWidget {
  const _RecentActivitySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(homeRecentActivityProvider);
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: w * 0.042,
                color: MyShopColors.primaryGold,
              ),
              SizedBox(width: w * 0.015),
              Expanded(
                child: Text(
                  'RECENT ACTIVITY',
                  style: TextStyle(
                    fontSize: w * 0.026,
                    fontWeight: FontWeight.w900,
                    color: MyShopColors.textSecondary,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.go(AppRoutes.activity),
                style: TextButton.styleFrom(
                  minimumSize: const Size(44, 36),
                  padding: EdgeInsets.symmetric(horizontal: w * 0.012),
                  foregroundColor: MyShopColors.darkSlate,
                  textStyle: TextStyle(
                    fontSize: w * 0.031,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('View all'),
              ),
            ],
          ),
          SizedBox(height: h * 0.012),
          activity.when(
            loading: () => const _RecentActivitySkeleton(),
            error: (_, __) => _RecentActivityError(
              onRetry: () =>
                  ref.read(homeRecentActivityProvider.notifier).refresh(),
            ),
            data: (items) => items.isEmpty
                ? const _RecentActivityEmpty()
                : Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        _RecentActivityCard(item: items[i]),
                        if (i != items.length - 1) SizedBox(height: h * 0.01),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RecentActivityCard extends StatelessWidget {
  final HomeRecentActivityItem item;

  const _RecentActivityCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final route = item.type == HomeActivityType.ride
        ? AppRoutes.activityRidePath(item.id)
        : AppRoutes.activityJobPath(item.id);
    final icon = item.type == HomeActivityType.ride
        ? Icons.directions_car_rounded
        : Icons.home_repair_service_rounded;
    final (badgeBackground, badgeForeground) = switch (item.status) {
      HomeActivityStatus.completed => (
          MyShopColors.successLight,
          MyShopColors.success,
        ),
      HomeActivityStatus.cancelled => (
          MyShopColors.errorLight,
          MyShopColors.error,
        ),
      HomeActivityStatus.inProgress => (
          MyShopColors.warningLight,
          MyShopColors.warning,
        ),
      HomeActivityStatus.pending => (
          MyShopColors.infoLight,
          MyShopColors.info,
        ),
    };

    return Material(
      color: MyShopColors.surfaceWhite,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => context.push(route),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MyShopColors.divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: MyShopColors.primaryGoldLight,
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(icon, color: MyShopColors.primaryGoldDark, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: w * 0.036,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: w * 0.029,
                        height: 1.3,
                        color: MyShopColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _activityTimeLabel(item.createdAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: w * 0.028,
                              color: MyShopColors.textSecondary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: badgeBackground,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            item.status.label,
                            style: TextStyle(
                              fontSize: w * 0.025,
                              fontWeight: FontWeight.w700,
                              color: badgeForeground,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: MyShopColors.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentActivityEmpty extends StatelessWidget {
  const _RecentActivityEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: const Column(
        children: [
          _RecentActivityEmptyIcon(),
          SizedBox(height: 12),
          Text(
            'Your activity will appear here',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
          SizedBox(height: 5),
          Text(
            'Your latest rides and service jobs will be easy to revisit after you book.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: MyShopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentActivityEmptyIcon extends StatelessWidget {
  const _RecentActivityEmptyIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: const BoxDecoration(
        color: MyShopColors.primaryGoldLight,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.route_rounded,
        color: MyShopColors.primaryGoldDark,
        size: 24,
      ),
    );
  }
}

class _RecentActivityError extends StatelessWidget {
  final VoidCallback onRetry;

  const _RecentActivityError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_rounded,
            color: MyShopColors.textSecondary,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              "We couldn't load your recent activity.",
              style: TextStyle(
                fontSize: 12,
                color: MyShopColors.textSecondary,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _RecentActivitySkeleton extends StatelessWidget {
  const _RecentActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        2,
        (index) => Padding(
          padding: EdgeInsets.only(bottom: index == 0 ? 8 : 0),
          child: Container(
            height: 94,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MyShopColors.divider),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                const _SkeletonBlock(width: 42, height: 42, radius: 21),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      _SkeletonBlock(width: 130, height: 12, radius: 6),
                      SizedBox(height: 9),
                      _SkeletonBlock(
                        width: double.infinity,
                        height: 10,
                        radius: 5,
                      ),
                      SizedBox(height: 9),
                      _SkeletonBlock(width: 85, height: 9, radius: 5),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonBlock extends StatelessWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBlock({
    required this.width,
    required this.height,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: MyShopColors.shimmerBase,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

String _activityTimeLabel(DateTime createdAt) {
  final local = createdAt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(local.year, local.month, local.day);
  final dayLabel = date == today
      ? 'Today'
      : date == today.subtract(const Duration(days: 1))
          ? 'Yesterday'
          : DateFormat.MMMd().format(local);
  return '$dayLabel · ${DateFormat.jm().format(local)}';
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData? leadingIcon;

  const _SectionHeader({
    required this.title,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: w * 0.036, color: MyShopColors.primaryGold),
            SizedBox(width: w * 0.015),
          ],
          Text(
            title,
            style: TextStyle(
              fontSize: w * 0.026,
              fontWeight: FontWeight.w900,
              color: MyShopColors.textSecondary,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

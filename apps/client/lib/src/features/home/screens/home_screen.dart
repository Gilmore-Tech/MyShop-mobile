import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/providers/current_location_label_provider.dart';
import '../../../core/providers/current_location_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../../ride/providers/ride_search_provider.dart';
import '../providers/home_provider.dart';
import '../widgets/location_search_card.dart';
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
    final String pickupName =
        search.pickup?.name ?? currentLabel ?? 'Locating...';

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
                    SizedBox(height: h * 0.05),
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
                    _SpecialOffersSection(),
                    SizedBox(height: h * 0.028),
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
                  'Welcome',
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
              onTap: () {
                _seedPickupFromCurrentLocation(ref);
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
  /// doesn't have to pick it again. No-ops when pickup is already set (preserves
  /// a prior selection) or when the GPS fix isn't ready yet (falls through to
  /// the existing "Choose pickup" prompt).
  void _seedPickupFromCurrentLocation(WidgetRef ref) {
    if (ref.read(rideSearchProvider).pickup != null) return;
    final pos = ref.read(currentDevicePositionProvider);
    if (pos == null) return;
    final label = ref.read(currentLocationLabelProvider).valueOrNull ??
        'Current location';
    ref.read(rideSearchProvider.notifier).setLocation(
          RideSearchField.pickup,
          RideLocation(
            name: label,
            address: label,
            lat: pos.latitude,
            lng: pos.longitude,
          ),
        );
  }
}

// ── Special offers ────────────────────────────────────────────────────────────

class _SpecialOffersSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offersAsync = ref.watch(specialOffersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SectionHeader(
          title: 'SPECIAL OFFERS',
          leadingIcon: Icons.local_offer_rounded,
        ),
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.014),
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.175,
          child: offersAsync.when(
            loading: () => _OffersSkeletonList(),
            error: (_, __) => const SizedBox.shrink(),
            data: (offers) => ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(
                  horizontal: MediaQuery.sizeOf(context).width * 0.041),
              itemCount: offers.length,
              separatorBuilder: (_, __) =>
                  SizedBox(width: MediaQuery.sizeOf(context).width * 0.031),
              itemBuilder: (_, i) => SpecialOfferCard(offer: offers[i]),
            ),
          ),
        ),
      ],
    );
  }
}

class _OffersSkeletonList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      itemCount: 2,
      separatorBuilder: (_, __) => SizedBox(width: w * 0.031),
      itemBuilder: (_, __) => const SpecialOfferCardSkeleton(),
    );
  }
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
            Icon(leadingIcon,
                size: w * 0.036, color: MyShopColors.primaryGold),
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

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/providers/current_location_label_provider.dart';
import '../../profile/providers/profile_provider.dart';
import '../../ride/providers/ride_search_provider.dart';
import '../providers/home_provider.dart';
import '../widgets/location_search_card.dart';
import '../widgets/recent_place_tile.dart';
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
    final destinationName = search.destination?.name;

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
                      destinationLabel: destinationName,
                      onPickupTap: () => context.push(
                          AppRoutes.rideSearchPath('pickup')),
                      onDestinationTap: () => context.push(
                          AppRoutes.rideSearchPath('destination')),
                      onPickupPinTap: () => context.push(
                          AppRoutes.ridePinPickerPath('pickup')),
                      onDestinationPinTap: () => context.push(
                          AppRoutes.ridePinPickerPath('destination')),
                    ),
                    SizedBox(height: h * 0.05),
                    _ServiceCardsRow(),
                    SizedBox(height: h * 0.028),
                    _SpecialOffersSection(),
                    SizedBox(height: h * 0.028),
                    _RecentPlacesSection(),
                    SizedBox(height: h * 0.019),
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

class _ServiceCardsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Row(
        children: [
          Expanded(
            child: ServiceCard(
              type: ServiceCardType.ride,
              onTap: () => context.push(AppRoutes.rideEstimate),
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
        _SectionHeader(
          title: 'SPECIAL OFFERS',
          leadingIcon: Icons.local_offer_rounded,
          actionLabel: 'View All',
          onActionTap: () {},
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
              separatorBuilder: (_, __) => SizedBox(
                  width: MediaQuery.sizeOf(context).width * 0.031),
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

// ── Recent places ─────────────────────────────────────────────────────────────

class _RecentPlacesSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final placesAsync = ref.watch(recentPlacesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionHeader(title: 'RECENT PLACES'),
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.005),
        Container(
          color: Colors.white,
          child: placesAsync.when(
            loading: () => const _RecentPlacesSkeleton(),
            error: (_, __) => const SizedBox.shrink(),
            data: (places) => Column(
              mainAxisSize: MainAxisSize.min,
              children: places
                  .map((p) => RecentPlaceTile(
                        place: p,
                        onTap: () {
                          // TODO: Navigate to destination with this place
                        },
                      ))
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentPlacesSkeleton extends StatelessWidget {
  const _RecentPlacesSkeleton();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (_) => Container(
          height: h * 0.071,
          padding: EdgeInsets.symmetric(horizontal: w * 0.041, vertical: h * 0.012),
          child: Row(
            children: [
              Container(
                width:  w * 0.056,
                height: w * 0.056,
                decoration: const BoxDecoration(
                  color: MyShopColors.divider,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: w * 0.036),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      height: h * 0.014,
                      width:  w * 0.308,
                      decoration: BoxDecoration(
                        color: MyShopColors.divider,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    SizedBox(height: h * 0.007),
                    Container(
                      height: h * 0.012,
                      width:  w * 0.462,
                      decoration: BoxDecoration(
                        color: MyShopColors.divider,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData? leadingIcon;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  const _SectionHeader({
    required this.title,
    this.leadingIcon,
    this.actionLabel,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
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
          if (actionLabel != null)
            GestureDetector(
              onTap: onActionTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: TextStyle(
                      fontSize: w * 0.031,
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.primaryGold,
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: w * 0.041, color: MyShopColors.primaryGold),
                ],
              ),
            ),
        ],
      ),
    );
  }
}


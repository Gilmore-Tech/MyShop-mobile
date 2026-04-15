import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../profile/providers/profile_provider.dart';
import '../../ride/providers/ride_search_provider.dart';
import '../providers/home_provider.dart';
import '../widgets/location_search_card.dart';
import '../widgets/recent_place_tile.dart';
import '../widgets/safety_banner.dart';
import '../widgets/service_card.dart';
import '../widgets/special_offer_card.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _darkSlate = Color(0xFF46535D);
const _offWhite = Color(0xFFF6F7F8);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);

/// PRD 4.2 — Client Home Screen
/// Card-based entry point for ride booking and artisan services.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final search = ref.watch(rideSearchProvider);
    final String pickupName =
        search.pickup?.name ?? ref.watch(currentLocationProvider);
    final destinationName = search.destination?.name;

    return Scaffold(
      backgroundColor: _offWhite,
      body: SafeArea(
        child: Column(
          children: [
            const _HomeGreeting(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),
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
                    const SizedBox(height: 40),
                    _ServiceCardsRow(),
                    const SizedBox(height: 24),
                    _SpecialOffersSection(),
                    const SizedBox(height: 24),
                    _RecentPlacesSection(),
                    const SizedBox(height: 16),
                    const SafetyBanner(),
                    const SizedBox(height: 24),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Welcome',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: _textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  firstName.isEmpty ? '\u00A0' : firstName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
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
        border: Border.all(color: _gold, width: 2),
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
                color: _darkSlate,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: ServiceCard(
              type: ServiceCardType.ride,
              onTap: () => context.push(AppRoutes.rideEstimate),
            ),
          ),
          const SizedBox(width: 12),
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
        const SizedBox(height: 12),
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
        const SizedBox(height: 4),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        3,
        (_) => Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFFE0E0E0),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      height: 12,
                      width: 120,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 10,
                      width: 180,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0E0E0),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leadingIcon != null) ...[
                Icon(leadingIcon, size: 14, color: _gold),
                const SizedBox(width: 6),
              ],
              Text(
                title,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: _textSecondary,
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
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _gold,
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 16, color: _gold),
                ],
              ),
            ),
        ],
      ),
    );
  }
}



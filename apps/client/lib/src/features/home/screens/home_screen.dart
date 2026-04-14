import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
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
const _textSecondary = Color(0xFF555E68);

/// PRD 4.2 — Client Home Screen
/// Card-based entry point for ride booking and artisan services.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocation = ref.watch(currentLocationProvider);

    final h = MediaQuery.sizeOf(context).height;
    return Scaffold(
      backgroundColor: _offWhite,
      body: SafeArea(
        child: Column(
          children: [
            _HomeAppBar(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: h * 0.019),
                    LocationSearchCard(
                      currentLocation: currentLocation,
                      onSearchTap: () {
                        // TODO: Navigate to destination_search_screen
                      },
                    ),
                    SizedBox(height: h * 0.019),
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

// ── App Bar ───────────────────────────────────────────────────────────────────

class _HomeAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: w * 0.041, vertical: h * 0.015),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () {},
            icon: Icon(Icons.menu_rounded, color: const Color(0xFF161A1D), size: w * 0.062),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints(minWidth: w * 0.123, minHeight: w * 0.123),
          ),
          GestureDetector(
            onTap: () {
              // TODO: Navigate to profile
            },
            child: Container(
              width: w * 0.103,
              height: w * 0.103,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE0E6FF),
                border: Border.all(color: _gold, width: 2),
              ),
              child: Icon(
                Icons.person_rounded,
                color: _darkSlate,
                size: w * 0.056,
              ),
            ),
          ),
        ],
      ),
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
              onTap: () => context.go(AppRoutes.rideEstimate),
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
                  color: Color(0xFFE0E0E0),
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
                        color: const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    SizedBox(height: h * 0.007),
                    Container(
                      height: h * 0.012,
                      width:  w * 0.462,
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
  final String? actionLabel;
  final VoidCallback? onActionTap;

  const _SectionHeader({
    required this.title,
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
          Text(
            title,
            style: TextStyle(
              fontSize: w * 0.026,
              fontWeight: FontWeight.w900,
              color: _textSecondary,
              letterSpacing: 1.4,
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onActionTap,
              child: Text(
                actionLabel!,
                style: TextStyle(
                  fontSize: w * 0.031,
                  fontWeight: FontWeight.w600,
                  color: _gold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}



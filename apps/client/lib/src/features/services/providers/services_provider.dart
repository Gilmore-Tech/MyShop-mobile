import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

// ── Service Category (UI model) ─────────────────────────────────────────────
// PRD 4.5: 10 categories seeded in DB. min_bid_pesewas configurable by admin.

class ServiceCategory {
  final String id;
  final String name;
  final IconData icon;
  final List<ServiceCategory>? children;

  const ServiceCategory({
    required this.id,
    required this.name,
    required this.icon,
    this.children,
  });

  bool get hasChildren => children != null && children!.isNotEmpty;
}

// ── Featured Artisan ──────────────────────────────────────────────────────────

class FeaturedArtisan {
  final String id;
  final String name;
  final String tradeTitle;
  final double rating;
  final int reviewCount;
  final int minPricePesewas;
  final bool isVerified;
  final Color cardColor;

  const FeaturedArtisan({
    required this.id,
    required this.name,
    required this.tradeTitle,
    required this.rating,
    required this.reviewCount,
    required this.minPricePesewas,
    required this.isVerified,
    required this.cardColor,
  });

  String get minPriceDisplay =>
      'From GHS ${(minPricePesewas / 100).toStringAsFixed(0)}';
}

// ── Recently Viewed Artisan ───────────────────────────────────────────────────

class RecentArtisan {
  final String id;
  final String name;
  final String trade;
  final double rating;
  final int reviewCount;
  final int? unreadCount;

  const RecentArtisan({
    required this.id,
    required this.name,
    required this.trade,
    required this.rating,
    required this.reviewCount,
    this.unreadCount,
  });
}

// ── Icon mapping for category slugs ──────────────────────────────────────────

IconData _iconForSlug(String slug) {
  return switch (slug) {
    'towing'       => Icons.car_repair,
    'electrician'  => Icons.electrical_services,
    'mechanic'     => Icons.build_outlined,
    'seamstress' || 'fashion' => Icons.content_cut,
    'painter'      => Icons.format_paint,
    'masonry'      => Icons.home_repair_service_outlined,
    'carpenter'    => Icons.carpenter,
    'plumber'      => Icons.plumbing,
    'satellite' || 'satellite-tv' => Icons.satellite_alt,
    'repairs'      => Icons.handyman,
    'repair-laptop' || 'laptop-repair' => Icons.laptop_mac,
    'repair-fridge' || 'fridge-repair' => Icons.kitchen,
    'repair-tv' || 'tv-repair'        => Icons.tv,
    'repair-phone' || 'phone-repair'  => Icons.phone_android,
    'repair-ac' || 'ac-repair'        => Icons.ac_unit,
    _              => Icons.miscellaneous_services,
  };
}

// ── Providers ─────────────────────────────────────────────────────────────────

final serviceCategoriesProvider =
    AsyncNotifierProvider<_CategoriesNotifier, List<ServiceCategory>>(
  _CategoriesNotifier.new,
);

class _CategoriesNotifier extends AsyncNotifier<List<ServiceCategory>> {
  @override
  Future<List<ServiceCategory>> build() async {
    try {
      final categoryService = ref.watch(categoryServiceProvider);
      final apiCategories = await categoryService.getCategories();

      return apiCategories.map((cat) {
        return ServiceCategory(
          id: cat.id,
          name: cat.name,
          icon: _iconForSlug(cat.slug),
          children: cat.hasChildren
              ? cat.children
                  .map((child) => ServiceCategory(
                        id: child.id,
                        name: child.name,
                        icon: _iconForSlug(child.slug),
                      ))
                  .toList()
              : null,
        );
      }).toList();
    } catch (_) {
      // Fallback to static categories if API fails (offline-graceful)
      return _fallbackCategories;
    }
  }
}

final featuredArtisansProvider =
    AsyncNotifierProvider<_FeaturedNotifier, List<FeaturedArtisan>>(
  _FeaturedNotifier.new,
);

class _FeaturedNotifier extends AsyncNotifier<List<FeaturedArtisan>> {
  @override
  Future<List<FeaturedArtisan>> build() async {
    // TODO: Replace with GET /artisans?featured=true&region=ashanti
    // when backend supports a featured artisan endpoint.
    // For pilot launch, return empty — the UI handles empty state gracefully.
    return const [];
  }
}

final recentArtisansProvider =
    AsyncNotifierProvider<_RecentNotifier, List<RecentArtisan>>(
  _RecentNotifier.new,
);

class _RecentNotifier extends AsyncNotifier<List<RecentArtisan>> {
  @override
  Future<List<RecentArtisan>> build() async {
    // Hydrated from local SharedPreferences cache in production.
    // Empty on first launch — populated as user interacts with artisans.
    return const [];
  }
}

// ── Fallback categories (used when API is unreachable) ──────────────────────

const _fallbackCategories = [
  ServiceCategory(id: 'towing', name: 'Towing Car', icon: Icons.car_repair),
  ServiceCategory(id: 'electrician', name: 'Electrician', icon: Icons.electrical_services),
  ServiceCategory(id: 'mechanic', name: 'Mechanic', icon: Icons.build_outlined),
  ServiceCategory(id: 'seamstress', name: 'Seamstress', icon: Icons.content_cut),
  ServiceCategory(id: 'painter', name: 'Painter', icon: Icons.format_paint),
  ServiceCategory(id: 'masonry', name: 'Masonry', icon: Icons.home_repair_service_outlined),
  ServiceCategory(id: 'carpenter', name: 'Carpenter', icon: Icons.carpenter),
  ServiceCategory(id: 'plumber', name: 'Plumber', icon: Icons.plumbing),
  ServiceCategory(id: 'satellite', name: 'Satellite TV', icon: Icons.satellite_alt),
  ServiceCategory(
    id: 'repairs',
    name: 'Repairs',
    icon: Icons.handyman,
    children: [
      ServiceCategory(id: 'repair-laptop', name: 'Laptop Repair', icon: Icons.laptop_mac),
      ServiceCategory(id: 'repair-fridge', name: 'Fridge Repair', icon: Icons.kitchen),
      ServiceCategory(id: 'repair-tv', name: 'Television Repair', icon: Icons.tv),
      ServiceCategory(id: 'repair-phone', name: 'Phone Repair', icon: Icons.phone_android),
    ],
  ),
];

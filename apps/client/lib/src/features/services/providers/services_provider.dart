import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Service Category ──────────────────────────────────────────────────────────
// 10 categories seeded in DB (EDD § Seed data, PRD 4.5).
// min_bid_pesewas is configurable by Super Admin per category.

class ServiceCategory {
  final String id;
  final String name;
  final IconData icon;

  const ServiceCategory({
    required this.id,
    required this.name,
    required this.icon,
  });
}

// ── Featured Artisan ──────────────────────────────────────────────────────────
// Displayed on the portfolio horizontal scroll.
// In production: GET /v1/artisans?featured=true&limit=6

class FeaturedArtisan {
  final String id;
  final String name;

  /// Display trade title, e.g. "Master Electrician"
  final String tradeTitle;

  final double rating;
  final int reviewCount;

  /// Lowest bid this artisan has accepted, in pesewas.
  final int minPricePesewas;
  final bool isVerified;

  /// Placeholder card colour until real network images are wired up.
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
// Pulled from local cache (SharedPreferences) — hydrated on screen mount.

class RecentArtisan {
  final String id;
  final String name;
  final String trade;
  final double rating;
  final int reviewCount;

  /// Unread message count for an active job with this artisan (null if none).
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

// ── Mock data ─────────────────────────────────────────────────────────────────

const _mockCategories = [
  ServiceCategory(id: 'towing',      name: 'Towing Car',   icon: Icons.car_repair),
  ServiceCategory(id: 'electrician', name: 'Electrician',  icon: Icons.electrical_services),
  ServiceCategory(id: 'mechanic',    name: 'Mechanic',     icon: Icons.build_outlined),
  ServiceCategory(id: 'seamstress',  name: 'Seamstress',   icon: Icons.content_cut),
  ServiceCategory(id: 'painter',     name: 'Painter',      icon: Icons.format_paint),
  ServiceCategory(id: 'masonry',     name: 'Masonry',      icon: Icons.home_repair_service_outlined),
  ServiceCategory(id: 'carpenter',   name: 'Carpenter',    icon: Icons.carpenter),
  ServiceCategory(id: 'plumber',     name: 'Plumber',      icon: Icons.plumbing),
  ServiceCategory(id: 'satellite',   name: 'Satellite TV', icon: Icons.satellite_alt),
  ServiceCategory(id: 'repairs',     name: 'Repairs',      icon: Icons.handyman),
];

const _mockFeatured = [
  FeaturedArtisan(
    id: 'a1',
    name: 'Kofi Mensah',
    tradeTitle: 'Master Electrician',
    rating: 4.8,
    reviewCount: 124,
    minPricePesewas: 15000,
    isVerified: true,
    cardColor: Color(0xFF6D4C3D), // warm brown placeholder
  ),
  FeaturedArtisan(
    id: 'a2',
    name: 'Ama Serwaa',
    tradeTitle: 'Expert Painter',
    rating: 4.9,
    reviewCount: 87,
    minPricePesewas: 12000,
    isVerified: true,
    cardColor: Color(0xFF607D8B), // blue-grey placeholder
  ),
  FeaturedArtisan(
    id: 'a3',
    name: 'Kwame Asante',
    tradeTitle: 'Senior Plumber',
    rating: 4.7,
    reviewCount: 65,
    minPricePesewas: 18000,
    isVerified: true,
    cardColor: Color(0xFF37474F),
  ),
];

const _mockRecentArtisans = [
  RecentArtisan(
    id: 'r1',
    name: 'Samuel Kwaku',
    trade: 'Carpenter',
    rating: 4.8,
    reviewCount: 24,
    unreadCount: 12,
  ),
  RecentArtisan(
    id: 'r2',
    name: 'Efua Antwi',
    trade: 'Painter',
    rating: 4.8,
    reviewCount: 24,
  ),
];

// ── Providers ─────────────────────────────────────────────────────────────────

final serviceCategoriesProvider =
    AsyncNotifierProvider<_CategoriesNotifier, List<ServiceCategory>>(
  _CategoriesNotifier.new,
);

class _CategoriesNotifier extends AsyncNotifier<List<ServiceCategory>> {
  @override
  Future<List<ServiceCategory>> build() async {
    // TODO: replace with GET /v1/service-categories
    await Future.delayed(const Duration(milliseconds: 250));
    return _mockCategories;
  }
}

final featuredArtisansProvider =
    AsyncNotifierProvider<_FeaturedNotifier, List<FeaturedArtisan>>(
  _FeaturedNotifier.new,
);

class _FeaturedNotifier extends AsyncNotifier<List<FeaturedArtisan>> {
  @override
  Future<List<FeaturedArtisan>> build() async {
    // TODO: replace with GET /v1/artisans?featured=true&region=ashanti
    await Future.delayed(const Duration(milliseconds: 350));
    return _mockFeatured;
  }
}

final recentArtisansProvider =
    AsyncNotifierProvider<_RecentNotifier, List<RecentArtisan>>(
  _RecentNotifier.new,
);

class _RecentNotifier extends AsyncNotifier<List<RecentArtisan>> {
  @override
  Future<List<RecentArtisan>> build() async {
    // TODO: hydrate from local SharedPreferences cache
    await Future.delayed(const Duration(milliseconds: 150));
    return _mockRecentArtisans;
  }
}

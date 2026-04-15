import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class SpecialOffer {
  final String id;
  final String tag;
  final String title;
  final String subtitle;
  final String? promoCode;
  final Color backgroundColor;

  const SpecialOffer({
    required this.id,
    required this.tag,
    required this.title,
    required this.subtitle,
    this.promoCode,
    required this.backgroundColor,
  });
}

class RecentPlace {
  final String id;
  final String name;
  final String address;

  const RecentPlace({
    required this.id,
    required this.name,
    required this.address,
  });
}

// ── Mock data ─────────────────────────────────────────────────────────────────

const _mockOffers = [
  SpecialOffer(
    id: '1',
    tag: 'SPECIAL OFFER',
    title: '20% Off Your First Ride',
    subtitle: 'Use code: AKWAABA',
    promoCode: 'AKWAABA',
    backgroundColor: Color(0xFF8B1E1E), // deep brick red
  ),
  SpecialOffer(
    id: '2',
    tag: 'LIMITED TIME',
    title: 'GHS 10 Off Artisan Services',
    subtitle: 'Use code: CRAFT10',
    promoCode: 'CRAFT10',
    backgroundColor: Color(0xFF1F4E3D), // deep forest green
  ),
];

const _mockRecentPlaces = [
  RecentPlace(
    id: '1',
    name: 'Accra Mall',
    address: 'Tetteh Quarshie Interchange, Accra',
  ),
  RecentPlace(
    id: '2',
    name: 'Home',
    address: '12 Garden Street, Kumasi',
  ),
  RecentPlace(
    id: '3',
    name: 'University of Ghana',
    address: 'Legon Road Boundary, Accra',
  ),
];

// ── Providers ─────────────────────────────────────────────────────────────────

final specialOffersProvider =
    AsyncNotifierProvider<SpecialOffersNotifier, List<SpecialOffer>>(
  SpecialOffersNotifier.new,
);

class SpecialOffersNotifier extends AsyncNotifier<List<SpecialOffer>> {
  @override
  Future<List<SpecialOffer>> build() async {
    // TODO: Replace with real API call via api_client
    await Future.delayed(const Duration(milliseconds: 400));
    return _mockOffers;
  }
}

final recentPlacesProvider =
    AsyncNotifierProvider<RecentPlacesNotifier, List<RecentPlace>>(
  RecentPlacesNotifier.new,
);

class RecentPlacesNotifier extends AsyncNotifier<List<RecentPlace>> {
  @override
  Future<List<RecentPlace>> build() async {
    // TODO: Replace with real API call / local cache
    await Future.delayed(const Duration(milliseconds: 200));
    return _mockRecentPlaces;
  }
}

/// Current location display string — in production, resolve via geolocator + reverse geocoding.
final currentLocationProvider = Provider<String>((_) => 'Kumasi Central Market');

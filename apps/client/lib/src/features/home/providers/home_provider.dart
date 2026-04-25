import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../auth/providers/auth_controller.dart';

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

// ── Providers ─────────────────────────────────────────────────────────────────

/// Special offers — in production these come from a config/promo endpoint.
/// For pilot, we keep a small static set that can be updated via platform config.
final specialOffersProvider =
    AsyncNotifierProvider<SpecialOffersNotifier, List<SpecialOffer>>(
  SpecialOffersNotifier.new,
);

class SpecialOffersNotifier extends AsyncNotifier<List<SpecialOffer>> {
  @override
  Future<List<SpecialOffer>> build() async {
    // TODO: Replace with GET /config/promos when backend supports it.
    // For pilot, static offers are fine per PRD §13.3 (no ads/listings).
    return const [
      SpecialOffer(
        id: '1',
        tag: 'SPECIAL OFFER',
        title: '20% Off Your First Ride',
        subtitle: 'Use code: AKWAABA',
        promoCode: 'AKWAABA',
        backgroundColor: Color(0xFF8B1E1E),
      ),
      SpecialOffer(
        id: '2',
        tag: 'LIMITED TIME',
        title: 'GHS 10 Off Artisan Services',
        subtitle: 'Use code: CRAFT10',
        promoCode: 'CRAFT10',
        backgroundColor: Color(0xFF1F4E3D),
      ),
    ];
  }
}

/// Recent/saved places — fetched from GET /users/me/saved-locations.
final recentPlacesProvider =
    AsyncNotifierProvider<RecentPlacesNotifier, List<RecentPlace>>(
  RecentPlacesNotifier.new,
);

class RecentPlacesNotifier extends AsyncNotifier<List<RecentPlace>> {
  @override
  Future<List<RecentPlace>> build() async {
    try {
      final userService = ref.watch(userServiceProvider);
      final locations = await userService.getSavedLocations();
      return locations.map((loc) {
        final map = loc as Map<String, dynamic>;
        return RecentPlace(
          id: map['id']?.toString() ?? '',
          name: map['label'] as String? ?? 'Saved Place',
          address: map['address'] as String? ?? '',
        );
      }).toList();
    } catch (_) {
      // Fallback: return empty list on error (offline-graceful per PRD).
      return const [];
    }
  }
}

/// User's display name from auth state — used in the greeting.
final userDisplayNameProvider = Provider<String>((ref) {
  final authState = ref.watch(clientAuthControllerProvider);
  if (authState is AuthAuthenticated) {
    final client = authState.profile.client;
    return client?.displayName ?? authState.profile.fullName;
  }
  return 'there';
});

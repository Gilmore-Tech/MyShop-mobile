import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

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

enum HomeActivityType { ride, job }

enum HomeActivityStatus { completed, cancelled, inProgress, pending }

extension HomeActivityStatusX on HomeActivityStatus {
  String get label => switch (this) {
        HomeActivityStatus.completed => 'Completed',
        HomeActivityStatus.cancelled => 'Cancelled',
        HomeActivityStatus.inProgress => 'In progress',
        HomeActivityStatus.pending => 'Pending',
      };
}

class HomeRecentActivityItem {
  final String id;
  final HomeActivityType type;
  final String title;
  final String subtitle;
  final HomeActivityStatus status;
  final DateTime createdAt;

  const HomeRecentActivityItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.createdAt,
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
    // Emergency release containment: do not advertise static codes while the
    // server-side promo redemption path is suspended. Re-enable from an
    // authoritative runtime endpoint only after atomic reservation is proven.
    return const [];
  }
}

/// Lightweight home preview of the signed-in client's latest activity.
///
/// This intentionally does not reuse the full Activity screen provider: that
/// provider loads up to 100 records and polls every 15 seconds. Home fetches
/// three rides and three jobs once per signed-in session, merges them, then
/// keeps only the newest three. Socket/creation paths invalidate this provider
/// when a booking changes, and logout always clears it.
final homeRecentActivityProvider = AsyncNotifierProvider<
    HomeRecentActivityNotifier, List<HomeRecentActivityItem>>(
  HomeRecentActivityNotifier.new,
);

class HomeRecentActivityNotifier
    extends AsyncNotifier<List<HomeRecentActivityItem>> {
  @override
  Future<List<HomeRecentActivityItem>> build() => _load();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }

  Future<List<HomeRecentActivityItem>> _load() async {
    final results = await Future.wait<List<dynamic>>([
      ref.read(rideServiceProvider).listRides(page: 1, limit: 3),
      ref.read(jobServiceProvider).listJobs(page: 1, limit: 3),
    ]);

    final items = <HomeRecentActivityItem>[];
    for (final raw in results[0]) {
      if (raw is! Map<String, dynamic>) continue;
      final item = _rideActivity(raw);
      if (item != null) items.add(item);
    }
    for (final raw in results[1]) {
      if (raw is! Map<String, dynamic>) continue;
      final item = _jobActivity(raw);
      if (item != null) items.add(item);
    }

    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<HomeRecentActivityItem>.unmodifiable(items.take(3));
  }

  HomeRecentActivityItem? _rideActivity(Map<String, dynamic> json) {
    try {
      final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
      if (createdAt == null) return null;
      final ride = Ride.fromJson(json);
      final destination = _shortAddress(ride.dropoffAddress);
      final route = _routeLabel(
        pickup: ride.pickupAddress,
        destination: ride.dropoffAddress,
      );
      return HomeRecentActivityItem(
        id: ride.id,
        type: HomeActivityType.ride,
        title: destination.isEmpty ? 'Ride' : 'Ride to $destination',
        subtitle: route.isEmpty ? 'Ride request' : route,
        status: switch (ride.status) {
          RideStatus.completed => HomeActivityStatus.completed,
          RideStatus.cancelled => HomeActivityStatus.cancelled,
          RideStatus.accepted ||
          RideStatus.driverEnRoute ||
          RideStatus.arrived ||
          RideStatus.inProgress =>
            HomeActivityStatus.inProgress,
          RideStatus.requested => HomeActivityStatus.pending,
        },
        createdAt: createdAt,
      );
    } catch (error) {
      debugPrint(
        '[Home] rejected malformed recent ride: ${error.runtimeType}',
      );
      return null;
    }
  }

  HomeRecentActivityItem? _jobActivity(Map<String, dynamic> json) {
    try {
      final id = (json['id'] ?? json['jobId'])?.toString().trim() ?? '';
      final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
      if (id.isEmpty || createdAt == null) return null;

      final category = json['category'];
      final categoryName = category is Map
          ? category['name']?.toString().trim() ?? ''
          : json['categoryName']?.toString().trim() ?? '';
      final description = json['description']?.toString().trim() ?? '';
      final address =
          (json['addressText'] ?? json['address'])?.toString().trim() ?? '';
      final status = json['status']?.toString() ?? '';

      return HomeRecentActivityItem(
        id: id,
        type: HomeActivityType.job,
        title: categoryName.isNotEmpty
            ? categoryName
            : description.isNotEmpty
                ? description
                : 'Service job',
        subtitle: address.isNotEmpty
            ? address
            : description.isNotEmpty && description != categoryName
                ? description
                : 'Service request',
        status: switch (status) {
          'completed' => HomeActivityStatus.completed,
          'cancelled' => HomeActivityStatus.cancelled,
          'in_progress' ||
          'arrived' ||
          'artisan_en_route' ||
          'en_route' ||
          'artisan_marked_complete' =>
            HomeActivityStatus.inProgress,
          _ => HomeActivityStatus.pending,
        },
        createdAt: createdAt,
      );
    } catch (error) {
      debugPrint(
        '[Home] rejected malformed recent job: ${error.runtimeType}',
      );
      return null;
    }
  }

  String _routeLabel({
    required String pickup,
    required String destination,
  }) {
    final from = pickup.trim();
    final to = destination.trim();
    if (from.isEmpty) return to;
    if (to.isEmpty) return from;
    return '$from → $to';
  }

  String _shortAddress(String address) {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(',').first.trim();
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

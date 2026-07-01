import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';

// ── Ride Detail Data ──────────────────────────────────────────────────────────

class RideDetailData {
  final String rideId;
  final String title;
  final String dateTimeLabel;
  final String status;

  // Route
  final String pickupAddress;
  final String dropoffAddress;
  final String? pickupTime;
  final String? dropoffTime;

  // Driver
  final String driverName;
  final String vehicleDisplay;
  final double driverRating;
  final String? driverPhotoUrl;

  /// Driver's real number — shown as read-only text (no call button) only
  /// while the completed ride is inside the 24h post-trip contact window.
  /// Null otherwise (cancelled, window expired, or backend omitted it).
  final String? driverPhone;

  // Trip
  final int durationMins;
  final double distanceKm;

  // Fare
  final int baseFarePesewas;
  final int distanceFarePesewas;
  final int bookingFeePesewas;
  final int totalFarePesewas;
  final String paymentMethod;

  const RideDetailData({
    required this.rideId,
    required this.title,
    required this.dateTimeLabel,
    required this.status,
    required this.pickupAddress,
    required this.dropoffAddress,
    this.pickupTime,
    this.dropoffTime,
    required this.driverName,
    required this.vehicleDisplay,
    required this.driverRating,
    this.driverPhotoUrl,
    this.driverPhone,
    required this.durationMins,
    required this.distanceKm,
    required this.baseFarePesewas,
    required this.distanceFarePesewas,
    required this.bookingFeePesewas,
    required this.totalFarePesewas,
    required this.paymentMethod,
  });

  String get baseFareDisplay => _fmt(baseFarePesewas);
  String get distanceFareDisplay => _fmt(distanceFarePesewas);
  String get bookingFeeDisplay => _fmt(bookingFeePesewas);
  String get totalFareDisplay => _fmt(totalFarePesewas);
  String get distanceDisplay => '${distanceKm.toStringAsFixed(1)} km';
  String get durationDisplay => '$durationMins min';

  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
}

String _fmt(int pesewas) {
  final ghs = pesewas / 100;
  if (ghs == ghs.truncateToDouble() && ghs >= 1) {
    return 'GHS ${ghs.toStringAsFixed(0)}';
  }
  return 'GHS ${ghs.toStringAsFixed(2)}';
}

// ── Provider ──────────────────────────────────────────────────────────────────

final rideDetailByIdProvider = AsyncNotifierProvider.autoDispose
    .family<_RideDetailNotifier, RideDetailData, String>(
  _RideDetailNotifier.new,
);

class _RideDetailNotifier
    extends AutoDisposeFamilyAsyncNotifier<RideDetailData, String> {
  @override
  Future<RideDetailData> build(String rideId) async {
    final rideService = ref.watch(rideServiceProvider);

    try {
      final ride = await rideService.getRide(rideId);
      return _parseRide(rideId, ride);
    } on ApiException catch (e) {
      developer.log(
        'getRide detail failed (${e.statusCode}): ${e.message}',
        name: 'RideDetailProvider',
      );
      rethrow;
    }
  }

  RideDetailData _parseRide(String rideId, Map<String, dynamic> ride) {
    final driver =
        ride['driver'] as Map<String, dynamic>? ?? <String, dynamic>{};

    final pickupAddr = ride['pickupAddress'] as String? ?? '';
    final dropoffAddr = ride['destinationAddress'] as String? ??
        ride['dropoffAddress'] as String? ??
        '';

    // Build title from addresses
    final title = pickupAddr.isNotEmpty && dropoffAddr.isNotEmpty
        ? '$pickupAddr → $dropoffAddr'
        : 'Ride $rideId';

    // Format date/time
    final createdAt = ride['createdAt'] as String?;
    final completedAt = ride['completedAt'] as String?;
    final pickedUpAt = ride['pickedUpAt'] as String?;
    String dateTimeLabel = '';
    String? pickupTime;
    String? dropoffTime;
    DateTime? completedAtDt;

    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        dateTimeLabel = DateFormat('MMM d, yyyy · h:mm a').format(dt.toLocal());
      }
    }
    if (pickedUpAt != null) {
      final dt = DateTime.tryParse(pickedUpAt);
      if (dt != null) pickupTime = DateFormat.jm().format(dt.toLocal());
    }
    if (completedAt != null) {
      final dt = DateTime.tryParse(completedAt);
      if (dt != null) {
        completedAtDt = dt;
        dropoffTime = DateFormat.jm().format(dt.toLocal());
      }
    }

    final status = ride['status'] as String? ?? 'requested';

    // Only surface the driver's real number while the completed ride is
    // inside the 24h post-trip contact window. Read-only — history pages
    // never expose a call button.
    final rawDriverPhone =
        (driver['phone'] ?? driver['maskedPhone']) as String?;
    final driverPhone = status == 'completed' &&
            isWithinPostTripContactWindow(completedAtDt) &&
            (rawDriverPhone?.trim().isNotEmpty ?? false)
        ? rawDriverPhone
        : null;

    return RideDetailData(
      rideId: ride['id'] as String? ?? rideId,
      title: title,
      dateTimeLabel: dateTimeLabel,
      status: status,
      pickupAddress: pickupAddr,
      dropoffAddress: dropoffAddr,
      pickupTime: pickupTime,
      dropoffTime: dropoffTime,
      driverName: driver['name'] as String? ?? 'Driver',
      vehicleDisplay: '${driver['vehicleShortName'] ?? driver['vehicle'] ?? ''}'
          ' · ${driver['plateNumber'] ?? ''}',
      driverRating: (driver['rating'] as num?)?.toDouble() ?? 0.0,
      driverPhotoUrl: driver['photoUrl'] as String?,
      driverPhone: driverPhone,
      durationMins: (ride['actualDurationMins'] as num?)?.toInt() ??
          (ride['estimatedDurationMins'] as num?)?.toInt() ??
          0,
      distanceKm: (ride['actualDistanceKm'] as num?)?.toDouble() ??
          (ride['estimatedDistanceKm'] as num?)?.toDouble() ??
          (ride['distanceKm'] as num?)?.toDouble() ??
          0,
      baseFarePesewas: (ride['baseFare'] as num?)?.toInt() ?? 0,
      distanceFarePesewas: (ride['distanceFare'] as num?)?.toInt() ?? 0,
      bookingFeePesewas: (ride['bookingFee'] as num?)?.toInt() ?? 0,
      totalFarePesewas: (ride['totalFare'] as num?)?.toInt() ??
          (ride['finalFarePesewas'] as num?)?.toInt() ??
          (ride['estimatedFarePesewas'] as num?)?.toInt() ??
          0,
      paymentMethod: ride['paymentMethod'] as String? ?? 'Cash',
    );
  }
}

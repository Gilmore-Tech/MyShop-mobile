/// Ride model representing a ride-hailing trip.
/// Money stored as int in pesewas (100 pesewas = GH₵1).
class Ride {
  const Ride({
    required this.id,
    required this.clientId,
    this.driverId,
    required this.status,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.estimatedFarePesewas,
    this.finalFarePesewas,
    required this.estimatedDistanceKm,
    required this.estimatedDurationMins,
    this.actualDistanceKm,
    this.actualDurationMins,
    this.surgeMultiplier = 1.0,
    required this.paymentMethod,
    required this.createdAt,
    this.acceptedAt,
    this.pickedUpAt,
    this.completedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.clientName,
    this.clientPhotoUrl,
    this.clientRating,
    this.clientTripCount,
    this.stops = const [],
  });

  factory Ride.fromJson(Map<String, dynamic> json) {
    return Ride(
      id: json['id'] as String,
      clientId: json['clientId'] as String,
      driverId: json['driverId'] as String?,
      status: RideStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => RideStatus.requested,
      ),
      pickupAddress: json['pickupAddress'] as String,
      dropoffAddress: json['dropoffAddress'] as String,
      pickupLat: (json['pickupLat'] as num).toDouble(),
      pickupLng: (json['pickupLng'] as num).toDouble(),
      dropoffLat: (json['dropoffLat'] as num).toDouble(),
      dropoffLng: (json['dropoffLng'] as num).toDouble(),
      estimatedFarePesewas: json['estimatedFarePesewas'] as int,
      finalFarePesewas: json['finalFarePesewas'] as int?,
      estimatedDistanceKm: (json['estimatedDistanceKm'] as num).toDouble(),
      estimatedDurationMins: json['estimatedDurationMins'] as int,
      actualDistanceKm: (json['actualDistanceKm'] as num?)?.toDouble(),
      actualDurationMins: json['actualDurationMins'] as int?,
      surgeMultiplier: (json['surgeMultiplier'] as num?)?.toDouble() ?? 1.0,
      paymentMethod: json['paymentMethod'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      acceptedAt: json['acceptedAt'] != null
          ? DateTime.parse(json['acceptedAt'] as String)
          : null,
      pickedUpAt: json['pickedUpAt'] != null
          ? DateTime.parse(json['pickedUpAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      cancelledAt: json['cancelledAt'] != null
          ? DateTime.parse(json['cancelledAt'] as String)
          : null,
      cancellationReason: json['cancellationReason'] as String?,
      clientName: json['clientName'] as String?,
      clientPhotoUrl: json['clientPhotoUrl'] as String?,
      clientRating: (json['clientRating'] as num?)?.toDouble(),
      clientTripCount: json['clientTripCount'] as int?,
      stops: (json['stops'] as List<dynamic>?)
              ?.map((s) => RideStop.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  final String id;
  final String clientId;
  final String? driverId;
  final RideStatus status;
  final String pickupAddress;
  final String dropoffAddress;
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final int estimatedFarePesewas;
  final int? finalFarePesewas;
  final double estimatedDistanceKm;
  final int estimatedDurationMins;
  final double? actualDistanceKm;
  final int? actualDurationMins;
  final double surgeMultiplier;
  final String paymentMethod;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? pickedUpAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final String? clientName;
  final String? clientPhotoUrl;
  final double? clientRating;
  final int? clientTripCount;
  final List<RideStop> stops;

  /// Display fare in GHS format
  String get estimatedFareDisplay => _formatGhs(estimatedFarePesewas);
  String get finalFareDisplay =>
      finalFarePesewas != null ? _formatGhs(finalFarePesewas!) : estimatedFareDisplay;

  String get distanceDisplay => '${estimatedDistanceKm.toStringAsFixed(1)} km';
  String get durationDisplay => '$estimatedDurationMins mins';

  bool get hasSurge => surgeMultiplier > 1.0;
  String get surgeDisplay => '${surgeMultiplier.toStringAsFixed(1)}x';

  Ride copyWith({RideStatus? status}) {
    return Ride(
      id: id,
      clientId: clientId,
      driverId: driverId,
      status: status ?? this.status,
      pickupAddress: pickupAddress,
      dropoffAddress: dropoffAddress,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat,
      dropoffLng: dropoffLng,
      estimatedFarePesewas: estimatedFarePesewas,
      finalFarePesewas: finalFarePesewas,
      estimatedDistanceKm: estimatedDistanceKm,
      estimatedDurationMins: estimatedDurationMins,
      actualDistanceKm: actualDistanceKm,
      actualDurationMins: actualDurationMins,
      surgeMultiplier: surgeMultiplier,
      paymentMethod: paymentMethod,
      createdAt: createdAt,
      acceptedAt: acceptedAt,
      pickedUpAt: pickedUpAt,
      completedAt: completedAt,
      cancelledAt: cancelledAt,
      cancellationReason: cancellationReason,
      clientName: clientName,
      clientPhotoUrl: clientPhotoUrl,
      clientRating: clientRating,
      clientTripCount: clientTripCount,
      stops: stops,
    );
  }
}

/// A stop on a multi-stop ride.
class RideStop {
  const RideStop({
    required this.address,
    required this.lat,
    required this.lng,
    this.arrivedAt,
  });

  factory RideStop.fromJson(Map<String, dynamic> json) {
    return RideStop(
      address: json['address'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      arrivedAt: json['arrivedAt'] != null
          ? DateTime.parse(json['arrivedAt'] as String)
          : null,
    );
  }

  final String address;
  final double lat;
  final double lng;
  final DateTime? arrivedAt;
}

/// Ride lifecycle status
enum RideStatus {
  requested,
  accepted,
  driverEnRoute,
  arrived,
  inProgress,
  completed,
  cancelled;

  bool get isActive =>
      this == accepted || this == driverEnRoute || this == arrived || this == inProgress;
}

/// Trip summary with fare breakdown (displayed after ride completion).
class TripSummary {
  const TripSummary({
    required this.rideId,
    required this.clientName,
    this.clientPhotoUrl,
    required this.clientRating,
    required this.paymentMethod,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.distanceKm,
    required this.durationMins,
    required this.baseFarePesewas,
    required this.distanceFarePesewas,
    required this.timeFarePesewas,
    this.surgeFarePesewas = 0,
    this.taxesPesewas = 0,
    this.promoPesewas = 0,
    required this.totalFarePesewas,
    required this.commissionPesewas,
    required this.netEarningsPesewas,
    required this.payoutMethod,
    required this.payoutStatus,
  });

  final String rideId;
  final String clientName;
  final String? clientPhotoUrl;
  final double clientRating;
  final String paymentMethod;
  final String pickupAddress;
  final String dropoffAddress;
  final double distanceKm;
  final int durationMins;
  final int baseFarePesewas;
  final int distanceFarePesewas;
  final int timeFarePesewas;
  final int surgeFarePesewas;
  final int taxesPesewas;
  final int promoPesewas;
  final int totalFarePesewas;
  final int commissionPesewas;
  final int netEarningsPesewas;
  final String payoutMethod;
  final String payoutStatus;

  String get totalFareDisplay => _formatGhs(totalFarePesewas);
  String get commissionDisplay => _formatGhs(commissionPesewas);
  String get netEarningsDisplay => _formatGhs(netEarningsPesewas);
}

/// Payout record for the earnings dashboard.
class PayoutRecord {
  const PayoutRecord({
    required this.id,
    required this.method,
    required this.amountPesewas,
    required this.status,
    required this.createdAt,
    this.reference,
  });

  final String id;
  final String method;
  final int amountPesewas;
  final String status;
  final DateTime createdAt;
  final String? reference;

  String get amountDisplay => _formatGhs(amountPesewas);
}

String _formatGhs(int pesewas) {
  final ghs = pesewas / 100;
  if (ghs == ghs.truncateToDouble() && ghs >= 1) {
    return 'GHS ${ghs.toStringAsFixed(0)}';
  }
  return 'GHS ${ghs.toStringAsFixed(2)}';
}

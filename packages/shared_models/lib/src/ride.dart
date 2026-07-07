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
    this.totalPaidPesewas,
    required this.estimatedDistanceKm,
    required this.estimatedDurationMins,
    this.actualDistanceKm,
    this.actualDurationMins,
    this.surgeMultiplier = 1.0,
    required this.paymentMethod,
    required this.createdAt,
    this.acceptedAt,
    this.arrivedAtPickupAt,
    this.pickedUpAt,
    this.completedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.clientName,
    this.clientPhone,
    this.clientPhotoUrl,
    this.clientRating,
    this.clientTripCount,
    this.driverName,
    this.driverPhone,
    this.stops = const [],
  });

  /// Parses a Ride from any of the three shapes the backend serves:
  ///   - the full persisted Ride (`GET /rides/:id`, status PATCH responses)
  ///   - the legacy slim `ride:request` socket broadcast (`{rideId, lat, lng, ...}`)
  ///   - the new `ride:new` socket broadcast (`{id, pickupLatitude, ...}`)
  ///
  /// The slim broadcasts intentionally omit fields the driver doesn't need
  /// to decide whether to accept (clientId, dropoff coords, paymentMethod,
  /// createdAt). Those become safe defaults here so the request modal can
  /// still render — full data arrives in the PATCH response after accept.
  factory Ride.fromJson(Map<String, dynamic> json) {
    double? _optionalNum(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return num.tryParse(v)?.toDouble();
      return null;
    }

    double _num(dynamic v, [double fallback = 0]) =>
        _optionalNum(v) ?? fallback;
    int _int(dynamic v, [int fallback = 0]) =>
        _optionalNum(v)?.toInt() ?? fallback;
    int? _optionalInt(dynamic v) => _optionalNum(v)?.toInt();
    DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v) : null;
    double _distanceKm() {
      final km = _optionalNum(
        json['estimatedDistanceKm'] ??
            json['distanceKm'] ??
            json['actualDistanceKm'],
      );
      if (km != null) return km;

      final meters = _optionalNum(
        json['estimatedDistanceMeters'] ??
            json['distanceMeters'] ??
            json['actualDistanceMeters'],
      );
      if (meters != null) return meters / 1000;

      return 0;
    }

    int _durationMins() {
      final minutes = _optionalNum(
        json['estimatedDurationMins'] ??
            json['durationMins'] ??
            json['actualDurationMins'],
      );
      if (minutes != null) return minutes.toInt();

      final seconds = _optionalNum(
        json['estimatedDurationSeconds'] ??
            json['durationSeconds'] ??
            json['actualDurationSeconds'],
      );
      if (seconds != null) return (seconds / 60).round();

      return 0;
    }

    // Backend serves the full ride entity with client info under a nested
    // `client` object (REST `GET /rides/:id`, `PATCH /rides/:id/status`),
    // while the slim `ride:new` socket broadcast inlines the same data at
    // top level. Read from whichever is populated so a single Ride model
    // works for both wire shapes.
    final clientObj = json['client'] is Map<String, dynamic>
        ? json['client'] as Map<String, dynamic>
        : const <String, dynamic>{};
    String? _clientStr(String topKey, [List<String> nestedKeys = const []]) {
      final top = json[topKey];
      if (top is String && top.isNotEmpty) return top;
      for (final k in nestedKeys) {
        final v = clientObj[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    final clientFirstName = clientObj['firstName'] as String?;
    final clientLastName = clientObj['lastName'] as String?;
    final assembledName = (clientFirstName != null || clientLastName != null)
        ? [clientFirstName, clientLastName].whereType<String>().join(' ').trim()
        : null;

    // Driver identity may arrive nested under `driver: {...}` (full REST
    // snapshot) or flattened at the top level. Mirror the client-side
    // resolution so the rider-facing history can render the driver's real
    // name + number.
    final driverObj = json['driver'] is Map<String, dynamic>
        ? json['driver'] as Map<String, dynamic>
        : const <String, dynamic>{};
    String? _driverStr(String topKey, [List<String> nestedKeys = const []]) {
      final top = json[topKey];
      if (top is String && top.isNotEmpty) return top;
      for (final k in nestedKeys) {
        final v = driverObj[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    final driverFirstName = driverObj['firstName'] as String?;
    final driverLastName = driverObj['lastName'] as String?;
    final assembledDriverName = (driverFirstName != null ||
            driverLastName != null)
        ? [driverFirstName, driverLastName].whereType<String>().join(' ').trim()
        : null;
    final status =
        RideStatus.fromString(json['status'] as String? ?? 'requested');
    final actualDistanceMeters = _optionalNum(json['actualDistanceMeters']);
    final actualDurationSeconds = _optionalNum(json['actualDurationSeconds']);

    return Ride(
      id: (json['id'] ?? json['rideId']) as String,
      clientId: json['clientId'] as String? ?? clientObj['id'] as String? ?? '',
      driverId: json['driverId'] as String?,
      status: status,
      pickupAddress: json['pickupAddress'] as String? ?? '',
      dropoffAddress: json['dropoffAddress'] as String? ?? '',
      pickupLat: _num(
        json['pickupLat'] ?? json['pickupLatitude'] ?? json['lat'],
      ),
      pickupLng: _num(
        json['pickupLng'] ?? json['pickupLongitude'] ?? json['lng'],
      ),
      dropoffLat: _num(json['dropoffLat'] ?? json['dropoffLatitude']),
      dropoffLng: _num(json['dropoffLng'] ?? json['dropoffLongitude']),
      estimatedFarePesewas: _int(
        json['estimatedFarePesewas'] ?? json['totalFare'],
      ),
      finalFarePesewas: _optionalInt(
        json['finalFarePesewas'] ??
            (status == RideStatus.completed ? json['totalFare'] : null),
      ),
      totalPaidPesewas: _optionalInt(
        json['totalPaidPesewas'] ?? json['amountPaidPesewas'],
      ),
      estimatedDistanceKm: _distanceKm(),
      estimatedDurationMins: _durationMins(),
      actualDistanceKm: _optionalNum(json['actualDistanceKm']) ??
          (actualDistanceMeters != null ? actualDistanceMeters / 1000 : null),
      actualDurationMins: _optionalInt(json['actualDurationMins']) ??
          (actualDurationSeconds != null
              ? (actualDurationSeconds / 60).round()
              : null),
      surgeMultiplier: _num(json['surgeMultiplier'], 1.0),
      paymentMethod: json['paymentMethod'] as String? ?? 'cash',
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      acceptedAt: _date(json['acceptedAt']),
      arrivedAtPickupAt: _date(json['arrivedAtPickupAt']),
      pickedUpAt: _date(json['pickedUpAt']),
      completedAt: _date(json['completedAt']),
      cancelledAt: _date(json['cancelledAt']),
      cancellationReason: json['cancellationReason'] as String?,
      clientName:
          _clientStr('clientName', ['name', 'fullName']) ?? assembledName,
      clientPhone: _clientStr('clientPhone', ['phone', 'maskedPhone']),
      clientPhotoUrl: _clientStr(
        'clientPhotoUrl',
        ['photoUrl', 'profilePhotoUrl', 'avatarUrl'],
      ),
      clientRating: (json['clientRating'] as num?)?.toDouble() ??
          (clientObj['rating'] as num?)?.toDouble(),
      clientTripCount: json['clientTripCount'] as int? ??
          (clientObj['tripCount'] as num?)?.toInt() ??
          (clientObj['totalRides'] as num?)?.toInt(),
      driverName:
          _driverStr('driverName', ['name', 'fullName']) ?? assembledDriverName,
      driverPhone: _driverStr('driverPhone', ['phone', 'maskedPhone']),
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
  final int? totalPaidPesewas;
  final double estimatedDistanceKm;
  final int estimatedDurationMins;
  final double? actualDistanceKm;
  final int? actualDurationMins;
  final double surgeMultiplier;
  final String paymentMethod;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAtPickupAt;
  final DateTime? pickedUpAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final String? clientName;

  /// Counterparty's real, dialable phone number. During the pilot the platform
  /// no longer masks these — the backend serves the live number on active
  /// rides and (for a limited window) on completed-ride snapshots so the two
  /// sides can reconnect. Null when the backend omits it / the window closed.
  final String? clientPhone;
  final String? clientPhotoUrl;
  final double? clientRating;
  final int? clientTripCount;
  final String? driverName;

  /// Driver's real, dialable phone number (see [clientPhone]).
  final String? driverPhone;
  final List<RideStop> stops;

  /// Display fare in GHS format
  String get estimatedFareDisplay => _formatGhs(estimatedFarePesewas);
  String get finalFareDisplay => finalFarePesewas != null
      ? _formatGhs(finalFarePesewas!)
      : estimatedFareDisplay;
  String get paidFareDisplay => totalPaidPesewas != null
      ? _formatGhs(totalPaidPesewas!)
      : finalFareDisplay;

  String get distanceDisplay => '${estimatedDistanceKm.toStringAsFixed(1)} km';
  String get durationDisplay => '$estimatedDurationMins mins';

  bool get hasSurge => surgeMultiplier > 1.0;
  String get surgeDisplay => '${surgeMultiplier.toStringAsFixed(1)}x';

  Ride copyWith({RideStatus? status, List<RideStop>? stops}) {
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
      totalPaidPesewas: totalPaidPesewas,
      estimatedDistanceKm: estimatedDistanceKm,
      estimatedDurationMins: estimatedDurationMins,
      actualDistanceKm: actualDistanceKm,
      actualDurationMins: actualDurationMins,
      surgeMultiplier: surgeMultiplier,
      paymentMethod: paymentMethod,
      createdAt: createdAt,
      acceptedAt: acceptedAt,
      arrivedAtPickupAt: arrivedAtPickupAt,
      pickedUpAt: pickedUpAt,
      completedAt: completedAt,
      cancelledAt: cancelledAt,
      cancellationReason: cancellationReason,
      clientName: clientName,
      clientPhone: clientPhone,
      clientPhotoUrl: clientPhotoUrl,
      clientRating: clientRating,
      clientTripCount: clientTripCount,
      driverName: driverName,
      driverPhone: driverPhone,
      stops: stops ?? this.stops,
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
      this == accepted ||
      this == driverEnRoute ||
      this == arrived ||
      this == inProgress;

  /// Parse a snake_case status string from the backend.
  /// `arrived` is accepted as an alias for `arrived_at_pickup` in case
  /// older payloads or other clients emit the short form.
  static RideStatus fromString(String value) {
    switch (value) {
      case 'requested':
        return RideStatus.requested;
      case 'accepted':
        return RideStatus.accepted;
      case 'driver_en_route':
        return RideStatus.driverEnRoute;
      case 'arrived_at_pickup':
      case 'arrived':
        return RideStatus.arrived;
      case 'in_progress':
        return RideStatus.inProgress;
      case 'completed':
        return RideStatus.completed;
      case 'cancelled':
        return RideStatus.cancelled;
      default:
        return RideStatus.requested;
    }
  }

  /// Convert to the snake_case string the backend expects on
  /// `PATCH /rides/:id/status`. Backend's `UpdatableRideStatus` enum is
  /// `driver_en_route | arrived_at_pickup | in_progress | completed`.
  String toJson() {
    switch (this) {
      case RideStatus.driverEnRoute:
        return 'driver_en_route';
      case RideStatus.arrived:
        return 'arrived_at_pickup';
      case RideStatus.inProgress:
        return 'in_progress';
      default:
        return name;
    }
  }
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

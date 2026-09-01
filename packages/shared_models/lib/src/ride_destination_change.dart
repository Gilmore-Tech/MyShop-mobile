import 'ride.dart';

/// One exact endpoint on a ride route.
///
/// Destination-change payloads use the nested `{address, lat, lng}` shape.
/// [fromJson] also accepts the persisted ride's `dropoff*` aliases so a REST
/// ride snapshot can be fed through the same route-update code during rollout.
class RideDestinationPoint {
  const RideDestinationPoint({
    required this.address,
    required this.lat,
    required this.lng,
  });

  factory RideDestinationPoint.fromJson(Map<String, dynamic> json) {
    final lat = _finiteDouble(
      json['lat'] ?? json['latitude'] ?? json['dropoffLat'],
    );
    final lng = _finiteDouble(
      json['lng'] ?? json['longitude'] ?? json['dropoffLng'],
    );
    if (lat == null || lat < -90 || lat > 90) {
      throw const FormatException('Destination latitude is invalid');
    }
    if (lng == null || lng < -180 || lng > 180) {
      throw const FormatException('Destination longitude is invalid');
    }
    return RideDestinationPoint(
      address: _requiredText(
        json['address'] ?? json['addressText'] ?? json['dropoffAddress'],
        'Destination address',
      ),
      lat: lat,
      lng: lng,
    );
  }

  final String address;
  final double lat;
  final double lng;

  Map<String, dynamic> toDropoffJson() => {
        'dropoffLat': lat,
        'dropoffLng': lng,
        'dropoffAddress': address,
      };
}

/// Optional platform-funded discount retained in a destination reprice.
class RideDestinationPromo {
  const RideDestinationPromo({
    required this.discountPesewas,
    this.code,
    this.label,
  });

  factory RideDestinationPromo.fromJson(Map<String, dynamic> json) {
    return RideDestinationPromo(
      discountPesewas: _nonNegativeInt(
        json['discountPesewas'] ?? json['promoDiscountPesewas'],
        'Promo discount',
      ),
      code: _optionalText(json['code'] ?? json['promoCode']),
      label: _optionalText(json['label']),
    );
  }

  final int discountPesewas;
  final String? code;
  final String? label;

  bool get applies => discountPesewas > 0;
}

/// Server-authored quote which must be explicitly confirmed before the route
/// changes. The token is opaque, short-lived and bound to [routeRevision].
class RideDestinationChangePreview {
  const RideDestinationChangePreview({
    required this.rideId,
    required this.routeRevision,
    required this.confirmationToken,
    required this.oldDestination,
    required this.newDestination,
    required this.oldFarePesewas,
    required this.newFarePesewas,
    required this.projectedDistanceMeters,
    required this.projectedDurationSeconds,
    this.tokenExpiresAt,
    this.promo,
    this.toll,
  });

  factory RideDestinationChangePreview.fromJson(Map<String, dynamic> json) {
    final pricing = _map(json['pricing']);
    final route = _map(json['route']);
    final oldDestination = _map(
      json['oldDestination'] ?? json['previousDestination'],
    );
    final newDestination = _map(json['newDestination'] ?? json['destination']);
    final preview = RideDestinationChangePreview(
      rideId: _requiredText(json['rideId'] ?? json['id'], 'Ride id'),
      routeRevision: _nonNegativeInt(
        json['routeRevision'] ?? json['route_revision'] ?? json['revision'],
        'Route revision',
      ),
      confirmationToken: _requiredText(
        json['confirmationToken'] ?? json['previewToken'] ?? json['token'],
        'Confirmation token',
      ),
      tokenExpiresAt: _optionalDate(
        json['tokenExpiresAt'] ?? json['expiresAt'],
      ),
      oldDestination: RideDestinationPoint.fromJson(oldDestination),
      newDestination: RideDestinationPoint.fromJson(newDestination),
      oldFarePesewas: _nonNegativeInt(
        json['oldFarePesewas'] ??
            json['previousFarePesewas'] ??
            json['currentFarePesewas'] ??
            pricing['oldFarePesewas'],
        'Old fare',
      ),
      newFarePesewas: _nonNegativeInt(
        json['newFarePesewas'] ??
            json['projectedFarePesewas'] ??
            json['quotedFarePesewas'] ??
            pricing['newFarePesewas'] ??
            pricing['clientPayableEstimatePesewas'],
        'New fare',
      ),
      projectedDistanceMeters: _nonNegativeInt(
        json['projectedDistanceMeters'] ??
            json['distanceMeters'] ??
            route['distanceMeters'] ??
            _kilometresToMetres(json['projectedDistanceKm']),
        'Projected distance',
      ),
      projectedDurationSeconds: _nonNegativeInt(
        json['projectedDurationSeconds'] ??
            json['durationSeconds'] ??
            route['durationSeconds'] ??
            _minutesToSeconds(json['projectedDurationMins']),
        'Projected duration',
      ),
      promo: _promoFrom(json, pricing),
      toll: RideToll.fromRideJson({...pricing, ...json}),
    );

    final suppliedDelta = _optionalInt(
      json['fareDeltaPesewas'] ?? pricing['fareDeltaPesewas'],
    );
    if (suppliedDelta != null && suppliedDelta != preview.fareDeltaPesewas) {
      throw const FormatException('Fare delta does not match quoted fares');
    }
    return preview;
  }

  final String rideId;
  final int routeRevision;
  final String confirmationToken;
  final DateTime? tokenExpiresAt;
  final RideDestinationPoint oldDestination;
  final RideDestinationPoint newDestination;
  final int oldFarePesewas;
  final int newFarePesewas;
  final int projectedDistanceMeters;
  final int projectedDurationSeconds;
  final RideDestinationPromo? promo;
  final RideToll? toll;

  int get fareDeltaPesewas => newFarePesewas - oldFarePesewas;
  double get projectedDistanceKm => projectedDistanceMeters / 1000;
  int get projectedDurationMins => (projectedDurationSeconds / 60).ceil();

  bool get tokenIsExpired =>
      tokenExpiresAt != null &&
      !tokenExpiresAt!.isAfter(DateTime.now().toUtc());
}

/// Authoritative route projection returned after confirmation and emitted to
/// both ride participants. A thin event containing only ride id + revision is
/// valid; callers should refetch the ride before applying it.
class RideRouteUpdate {
  const RideRouteUpdate({
    required this.rideId,
    required this.routeRevision,
    this.destination,
    this.previousDestination,
    this.estimatedFarePesewas,
    this.clientPayableEstimatePesewas,
    this.projectedDistanceMeters,
    this.projectedDurationSeconds,
    this.promo,
    this.toll,
    this.changedAt,
  });

  factory RideRouteUpdate.fromJson(Map<String, dynamic> json) {
    final pricing = _map(json['pricing']);
    final route = _map(json['route']);
    final destinationRaw = json['destination'] ?? json['newDestination'];
    final previousRaw = json['previousDestination'] ?? json['oldDestination'];
    final routeRevision = _optionalNonNegativeInt(
      json['routeRevision'] ?? json['route_revision'] ?? json['revision'],
    );
    return RideRouteUpdate(
      rideId: _requiredText(json['rideId'] ?? json['id'], 'Ride id'),
      // Legacy ride snapshots and the legacy `ride:route_updated` envelope did
      // not carry a revision. Treat those as revision zero so the new clients
      // can still hydrate them without inventing a newer route state.
      routeRevision: routeRevision ?? 0,
      destination: destinationRaw is Map
          ? RideDestinationPoint.fromJson(_map(destinationRaw))
          : _destinationFromFlatRide(json),
      previousDestination: previousRaw is Map
          ? RideDestinationPoint.fromJson(_map(previousRaw))
          : null,
      estimatedFarePesewas: _optionalNonNegativeInt(
        json['estimatedFarePesewas'] ?? pricing['estimatedFarePesewas'],
      ),
      clientPayableEstimatePesewas: _optionalNonNegativeInt(
        json['clientPayableEstimatePesewas'] ??
            pricing['clientPayableEstimatePesewas'] ??
            json['newFarePesewas'] ??
            json['quotedFarePesewas'],
      ),
      projectedDistanceMeters: _optionalNonNegativeInt(
        json['projectedDistanceMeters'] ??
            json['distanceMeters'] ??
            json['estimatedDistanceMeters'] ??
            route['distanceMeters'] ??
            _kilometresToMetres(
              json['projectedDistanceKm'] ?? json['estimatedDistanceKm'],
            ),
      ),
      projectedDurationSeconds: _optionalNonNegativeInt(
        json['projectedDurationSeconds'] ??
            json['durationSeconds'] ??
            json['estimatedDurationSeconds'] ??
            route['durationSeconds'] ??
            _minutesToSeconds(
              json['projectedDurationMins'] ?? json['estimatedDurationMins'],
            ),
      ),
      promo: _promoFrom(json, pricing),
      toll: RideToll.fromRideJson({...pricing, ...json}),
      changedAt: _optionalDate(json['changedAt'] ?? json['updatedAt']),
    );
  }

  final String rideId;
  final int routeRevision;
  final RideDestinationPoint? destination;
  final RideDestinationPoint? previousDestination;
  final int? estimatedFarePesewas;
  final int? clientPayableEstimatePesewas;
  final int? projectedDistanceMeters;
  final int? projectedDurationSeconds;
  final RideDestinationPromo? promo;
  final RideToll? toll;
  final DateTime? changedAt;

  bool get hasRouteProjection => destination != null;

  /// True when this object is safe to use as the post-confirmation source of
  /// truth without a REST refetch. Destination-only socket envelopes remain
  /// useful as invalidation signals, but must not leave stale fare or route
  /// metrics on screen.
  bool get hasCompleteRouteProjection =>
      destination != null &&
      (clientPayableEstimatePesewas != null || estimatedFarePesewas != null) &&
      projectedDistanceMeters != null &&
      projectedDurationSeconds != null;

  /// Builds the same projection from `GET /rides/:id` for missed/thin events.
  static RideRouteUpdate fromRideJson(Map<String, dynamic> json) {
    return RideRouteUpdate.fromJson({
      ...json,
      'destination': {
        'address': json['dropoffAddress'],
        'lat': json['dropoffLat'] ?? json['dropoffLatitude'],
        'lng': json['dropoffLng'] ?? json['dropoffLongitude'],
      },
    });
  }
}

RideDestinationPoint? _destinationFromFlatRide(Map<String, dynamic> json) {
  if (json['dropoffLat'] == null && json['dropoffLatitude'] == null) {
    return null;
  }
  return RideDestinationPoint.fromJson(json);
}

RideDestinationPromo? _promoFrom(
  Map<String, dynamic> json,
  Map<String, dynamic> pricing,
) {
  final nested = json['promo'] ?? pricing['promo'];
  if (nested is Map) {
    return RideDestinationPromo.fromJson(_map(nested));
  }
  final discount = _optionalNonNegativeInt(
    json['promoDiscountPesewas'] ?? pricing['promoDiscountPesewas'],
  );
  if (discount == null || discount == 0) return null;
  return RideDestinationPromo(
    discountPesewas: discount,
    code: _optionalText(json['promoCode'] ?? pricing['promoCode']),
  );
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) return const {};
  return {for (final entry in value.entries) entry.key.toString(): entry.value};
}

String _requiredText(Object? value, String label) {
  final text = _optionalText(value);
  if (text == null) throw FormatException('$label is missing');
  return text;
}

String? _optionalText(Object? value) {
  if (value is! String) return null;
  final text = value.trim();
  return text.isEmpty ? null : text;
}

double? _finiteDouble(Object? value) {
  final number = switch (value) {
    final num value => value.toDouble(),
    final String value => double.tryParse(value),
    _ => null,
  };
  return number != null && number.isFinite ? number : null;
}

int _nonNegativeInt(Object? value, String label) {
  final parsed = _optionalNonNegativeInt(value);
  if (parsed == null) throw FormatException('$label is invalid');
  return parsed;
}

int? _optionalNonNegativeInt(Object? value) {
  final parsed = _optionalInt(value);
  return parsed != null && parsed >= 0 ? parsed : null;
}

int? _optionalInt(Object? value) {
  final number = switch (value) {
    final num value => value,
    final String value => num.tryParse(value),
    _ => null,
  };
  if (number == null ||
      !number.isFinite ||
      number != number.truncateToDouble() ||
      number.abs() > 9007199254740991) {
    return null;
  }
  return number.toInt();
}

Object? _kilometresToMetres(Object? value) {
  final km = _finiteDouble(value);
  return km == null ? null : (km * 1000).round();
}

Object? _minutesToSeconds(Object? value) {
  final mins = _finiteDouble(value);
  return mins == null ? null : (mins * 60).round();
}

DateTime? _optionalDate(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value)?.toUtc();
}

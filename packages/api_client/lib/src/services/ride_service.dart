import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../models/api_exception.dart';

/// Service for ride-hailing API endpoints.
/// EDD § 5.2 — Rides (8 endpoints)
class RideService {
  RideService(this._dio);
  final Dio _dio;

  dynamic _unwrap(Response response) {
    final body = response.data as Map<String, dynamic>;
    if (body['success'] == true) return body['data'];
    throw ApiException.fromDioException(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      ),
    );
  }

  /// POST /rides/estimate — Fare estimation (origin, destination, stops).
  Future<Map<String, dynamic>> estimate({
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    List<Map<String, double>>? stops,
  }) async {
    try {
      final response = await _dio.post(
        '/rides/estimate',
        data: {
          'pickupLat': pickupLat,
          'pickupLng': pickupLng,
          'dropoffLat': destinationLat,
          'dropoffLng': destinationLng,
          if (stops != null) 'stops': stops,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /rides — Create ride booking.
  ///
  /// Wire format uses `dropoff*` (not `destination*`) per the backend
  /// schema. `paymentMethod` is required by the backend; valid values are
  /// `cash`, `card`, `momo_mtn`, `momo_telecel`, `momo_airteltigo`.
  /// Defaults to `cash` when the caller doesn't specify one.
  Future<Map<String, dynamic>> createRide({
    required String bookingKey,
    required double pickupLat,
    required double pickupLng,
    required double destinationLat,
    required double destinationLng,
    String? pickupAddress,
    String? destinationAddress,
    List<Map<String, dynamic>>? stops,
    String? paymentMethod,
    String? promoCode,
    String? rideCategory,
  }) async {
    try {
      final response = await _dio.post(
        '/rides',
        options: Options(headers: {'Idempotency-Key': bookingKey}),
        data: {
          'pickupLat': pickupLat,
          'pickupLng': pickupLng,
          'dropoffLat': destinationLat,
          'dropoffLng': destinationLng,
          if (pickupAddress != null) 'pickupAddress': pickupAddress,
          if (destinationAddress != null) 'dropoffAddress': destinationAddress,
          if (stops != null) 'stops': stops,
          'paymentMethod': paymentMethod ?? 'cash',
          if (promoCode != null) 'promoCode': promoCode,
          // Slug of the chosen ride category (e.g. 'regular', 'comfort').
          // Drives pricing + which drivers are matched. Backend defaults to
          // 'regular' when omitted.
          if (rideCategory != null) 'rideCategory': rideCategory,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /rides/booking-attempts/:key — resolve an ambiguous create result.
  ///
  /// Returns the live create-response projection when this key created a ride,
  /// or null only for the backend's definitive BOOKING_ATTEMPT_NOT_FOUND 404.
  /// Network errors, 5xx responses, and unrelated 404s remain errors so a
  /// caller cannot mistake an uncertain lookup for permission to create again.
  Future<Map<String, dynamic>?> lookupBookingAttempt(String bookingKey) async {
    try {
      final response = await _dio.get('/rides/booking-attempts/$bookingKey');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 &&
          _responseErrorCode(e.response?.data) == 'BOOKING_ATTEMPT_NOT_FOUND') {
        return null;
      }
      throw ApiException.fromDioException(e);
    }
  }

  String? _responseErrorCode(Object? data) {
    if (data is! Map) return null;
    final error = data['error'];
    if (error is String) return error;
    if (error is Map) {
      final code = error['code'];
      if (code is String) return code;
    }
    final code = data['errorCode'] ?? data['code'];
    return code is String ? code : null;
  }

  /// GET /ride-categories — Public list of active ride categories (tiers).
  /// Used by the booking sheet and driver signup. Returns an empty list if the
  /// endpoint is unavailable so older backends degrade gracefully.
  Future<List<Map<String, dynamic>>> listRideCategories() async {
    try {
      final response = await _dio.get('/ride-categories');
      final data = _unwrap(response);
      if (data is List) return data.cast<Map<String, dynamic>>();
      return [];
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return [];
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /rides — List client's rides with optional filters.
  /// Returns empty list if the endpoint is not yet available (404).
  Future<List<dynamic>> listRides({
    int page = 1,
    int limit = 50,
    String? status,
  }) async {
    try {
      final response = await _dio.get(
        '/rides',
        queryParameters: {
          'page': page,
          'limit': limit,
          if (status != null) 'status': status,
        },
      );
      final body = response.data;
      // Handle various response shapes from the backend.
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        // { success: true, data: [...] }
        if (data is List) return data;
        // { success: true, data: { items: [...] } }
        if (data is Map<String, dynamic>) {
          if (data['items'] is List) return data['items'] as List<dynamic>;
          if (data['rides'] is List) return data['rides'] as List<dynamic>;
        }
        // { success: true, data: { data: [...] } } (nested pagination)
        if (data is Map<String, dynamic> && data['data'] is List) {
          return data['data'] as List<dynamic>;
        }
      }
      return [];
    } on DioException catch (e) {
      // Return empty list if endpoint not implemented yet.
      if (e.response?.statusCode == 404) return [];
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /rides/:id — Get ride details with live status.
  Future<Map<String, dynamic>> getRide(String rideId) async {
    try {
      final response = await _dio.get('/rides/$rideId');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /rides/:id/accept — accept the currently assigned ride offer.
  ///
  /// This REST path mirrors the `ride:accept` socket acknowledgement and is
  /// intentionally used by notification/overlay actions, where the socket may
  /// not be connected yet after a cold start.
  Future<Map<String, dynamic>> acknowledgeRideOffer(
    String rideId,
    String offerId,
  ) async {
    try {
      final response = await _dio.post(
        '/rides/$rideId/offers/$offerId/received',
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<Map<String, dynamic>> acceptRideRequest(
    String rideId, {
    required String offerId,
  }) async {
    try {
      final response = await _dio.post(
        '/rides/$rideId/accept',
        data: {'offerId': offerId},
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /rides/:id/decline — skip the current ride offer.
  ///
  /// The operation is idempotent on the backend. Sending it immediately lets
  /// the matcher advance instead of waiting for the offer deadline.
  Future<void> declineRideRequest(
    String rideId, {
    required String offerId,
    String? reason,
  }) async {
    try {
      await _dio.post(
        '/rides/$rideId/decline',
        data: {
          'offerId': offerId,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /drivers/me/active-ride — Driver: fetch the ride this driver is
  /// currently assigned to (status in `accepted | driver_en_route |
  /// arrived_at_pickup | in_progress`), or null if none. Replaces the
  /// SharedPreferences-based recovery flow with an authoritative
  /// server-side lookup that survives reinstalls and device changes.
  ///
  /// The wire shape is double-wrapped: the controller returns
  /// `{ data: ride | null }` and the global `TransformInterceptor` wraps
  /// it again as `{ success, data: { data: ride | null } }`. After
  /// stripping both envelopes we hand `Ride.fromJson` the bare ride map,
  /// or null when there's no active ride.
  Future<Map<String, dynamic>?> getMyActiveRide() async {
    try {
      final response = await _dio.get('/drivers/me/active-ride');
      final outer = _unwrap(response);
      if (outer is! Map<String, dynamic>) return null;
      // Peel the controller's `{ data: ride }` wrapper. Older builds of
      // the backend returned the bare ride here, so accept that shape too
      // by checking for a top-level `id` before stripping.
      if (outer.containsKey('id') && outer['id'] is String) return outer;
      final inner = outer['data'];
      if (inner is Map<String, dynamic>) return inner;
      return null;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /rides/:id/status — Driver: advance the ride lifecycle.
  ///
  /// Valid transitions (and their required predecessors):
  ///   requested        → accepted          (driver accepts)
  ///   accepted         → driver_en_route   (driver heads to pickup)
  ///   driver_en_route  → arrived           (driver at pickup pin)
  ///   arrived          → in_progress       (passenger boarded; trip starts)
  ///   in_progress      → completed         (trip finished)
  ///
  /// Backend rejects invalid transitions with `INVALID_STATUS_TRANSITION`
  /// (400) and non-assigned drivers with `NOT_ASSIGNED_DRIVER` (403).
  Future<Map<String, dynamic>> updateRideStatus(
    String rideId, {
    required String status,
    double? currentLat,
    double? currentLng,
    double? accuracyMeters,
    DateTime? capturedAt,
  }) async {
    const locationStatuses = {
      'arrived_at_pickup',
      'in_progress',
      'completed',
    };
    if (locationStatuses.contains(status) &&
        (currentLat == null ||
            currentLng == null ||
            accuracyMeters == null ||
            capturedAt == null)) {
      throw ArgumentError(
        'A lifecycle GPS fix is required for arrival, trip start, and trip end.',
      );
    }
    try {
      final response = await _dio.patch(
        '/rides/$rideId/status',
        data: {
          'status': status,
          if (currentLat != null && currentLng != null) ...{
            'currentLat': currentLat,
            'currentLng': currentLng,
          },
          if (accuracyMeters != null) 'accuracyMeters': accuracyMeters,
          if (capturedAt != null)
            'capturedAt': capturedAt.toUtc().toIso8601String(),
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /rides/:id/cancel — Cancel ride (enforces 3-min free window).
  Future<Map<String, dynamic>> cancelRide(
    String rideId, {
    String? reason,
  }) async {
    try {
      final response = await _dio.patch(
        '/rides/$rideId/cancel',
        data: {
          if (reason != null) 'reason': reason,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /rides/:id/stops — Add mid-ride stop.
  Future<Map<String, dynamic>> addStop(
    String rideId, {
    required double lat,
    required double lng,
    String? address,
  }) async {
    try {
      final response = await _dio.patch(
        '/rides/$rideId/stops',
        data: {
          'latitude': lat,
          'longitude': lng,
          if (address != null) 'addressText': address,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /rides/:id/destination-change/preview — quote an exact destination
  /// replacement without mutating the ride.
  ///
  /// [expectedRouteRevision] is the last authoritative revision displayed by
  /// the client. The backend rejects a stale revision instead of quoting or
  /// committing against a route which changed in another session.
  Future<RideDestinationChangePreview> previewDestinationChange(
    String rideId, {
    required RideDestinationPoint destination,
    required int expectedRouteRevision,
  }) async {
    try {
      final response = await _dio.post(
        '/rides/$rideId/destination-change/preview',
        data: {
          ...destination.toDropoffJson(),
          'expectedRouteRevision': expectedRouteRevision,
        },
      );
      return RideDestinationChangePreview.fromJson(
        _unwrap(response) as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /rides/:id/destination — consume one server preview and atomically
  /// commit its exact route/fare projection.
  Future<RideRouteUpdate> confirmDestinationChange(
    String rideId, {
    required String confirmationToken,
    required int expectedRouteRevision,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _dio.patch(
        '/rides/$rideId/destination',
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        data: {
          'confirmationToken': confirmationToken,
          'expectedRouteRevision': expectedRouteRevision,
        },
      );
      return RideRouteUpdate.fromJson(
        _unwrap(response) as Map<String, dynamic>,
      );
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /rides/:id/dispute — Client: dispute ride fare (2-hour window).
  Future<Map<String, dynamic>> disputeRide(
    String rideId, {
    required String reason,
    String? details,
  }) async {
    try {
      final response = await _dio.post(
        '/rides/$rideId/dispute',
        data: {
          'reason': reason,
          if (details != null) 'details': details,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /rides/:id/share — Get shareable tracking link.
  Future<Map<String, dynamic>> getShareLink(String rideId) async {
    try {
      final response = await _dio.get('/rides/$rideId/share');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}

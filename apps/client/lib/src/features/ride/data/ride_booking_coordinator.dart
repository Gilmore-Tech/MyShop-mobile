import 'package:api_client/api_client.dart';

import 'ride_booking_attempt_store.dart';

typedef BookingAttemptLookup = Future<Map<String, dynamic>?> Function(
  String bookingKey,
);
typedef RideCreateWithKey = Future<Map<String, dynamic>> Function(
  String bookingKey,
);

class RideBookingResolution {
  const RideBookingResolution({
    required this.response,
    required this.recovered,
  });

  final Map<String, dynamic> response;
  final bool recovered;
}

/// Raised when the lookup result is not authoritative enough to permit a new
/// POST. The original server/network message is intentionally not retained.
class RideBookingLookupUncertainException implements Exception {
  const RideBookingLookupUncertainException({
    this.statusCode,
    this.errorCode,
  });

  final int? statusCode;
  final String? errorCode;
}

/// Resolves an existing durable booking key before creating a ride.
///
/// A 404 is represented by [_lookup] returning null. Every thrown lookup error
/// blocks creation. This fail-closed boundary is what prevents a changed ride
/// request from creating a second ride while the first POST outcome is unknown.
class RideBookingCoordinator {
  RideBookingCoordinator({
    required RideBookingAttemptStore store,
    required BookingAttemptLookup lookup,
  })  : _store = store,
        _lookup = lookup;

  final RideBookingAttemptStore _store;
  final BookingAttemptLookup _lookup;
  Future<RideBookingResolution>? _inFlight;

  Future<RideBookingResolution> resolveOrCreate({
    required String requestFingerprint,
    required RideCreateWithKey create,
  }) {
    final running = _inFlight;
    if (running != null) return running;

    late final Future<RideBookingResolution> operation;
    operation = _resolveOrCreate(
      requestFingerprint: requestFingerprint,
      create: create,
    ).whenComplete(() {
      if (identical(_inFlight, operation)) _inFlight = null;
    });
    _inFlight = operation;
    return operation;
  }

  Future<RideBookingResolution> _resolveOrCreate({
    required String requestFingerprint,
    required RideCreateWithKey create,
  }) async {
    final pending = await _store.read();
    if (pending != null) {
      Map<String, dynamic>? existing;
      try {
        existing = await _lookup(pending.bookingKey);
      } on ApiException catch (error) {
        throw RideBookingLookupUncertainException(
          statusCode: error.statusCode,
          errorCode: error.errorCode,
        );
      } catch (_) {
        throw const RideBookingLookupUncertainException();
      }

      if (existing != null) {
        final status = _statusOf(existing);
        if (!_isTerminal(status)) {
          return RideBookingResolution(response: existing, recovered: true);
        }
        await _store.clear(bookingKey: pending.bookingKey);
      } else if (pending.requestFingerprint != requestFingerprint) {
        // The old key is definitively unused, so a changed request may safely
        // receive a new key. An identical retry deliberately keeps its key.
        await _store.clear(bookingKey: pending.bookingKey);
      }
    }

    final attempt = await _store.getOrCreate(requestFingerprint);
    try {
      final response = await create(attempt.bookingKey);
      if (_isTerminal(_statusOf(response))) {
        await _store.clear(bookingKey: attempt.bookingKey);
      }
      return RideBookingResolution(response: response, recovered: false);
    } on ApiException catch (error) {
      if (_isDefinitivePreCreateFailure(error.statusCode)) {
        await _store.clear(bookingKey: attempt.bookingKey);
      }
      rethrow;
    }
  }
}

String _statusOf(Map<String, dynamic> response) =>
    (response['status'] as String? ?? '').toLowerCase();

bool _isTerminal(String status) =>
    status == 'cancelled' || status == 'completed';

bool _isDefinitivePreCreateFailure(int? statusCode) {
  if (statusCode == null || statusCode < 400 || statusCode >= 500) {
    return false;
  }
  // These responses do not prove the server rejected the request before a
  // ride commit. 409 is explicitly replayable; timeout/too-early/rate-limit
  // responses can race work that is still completing.
  return statusCode != 408 &&
      statusCode != 409 &&
      statusCode != 425 &&
      statusCode != 429;
}

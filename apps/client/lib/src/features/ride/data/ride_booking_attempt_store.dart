import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Privacy-minimal local handle for one unresolved ride-create attempt.
///
/// Coordinates, addresses, stops, payment details, and server responses are
/// deliberately never persisted. [requestFingerprint] is a one-way SHA-256 of
/// the canonical request and exists only to decide whether a retry represents
/// the same request.
class RideBookingAttempt {
  const RideBookingAttempt({
    required this.bookingKey,
    required this.requestFingerprint,
    required this.createdAt,
  });

  final String bookingKey;
  final String requestFingerprint;
  final DateTime createdAt;

  Map<String, String> toJson() => {
        'bookingKey': bookingKey,
        'requestFingerprint': requestFingerprint,
        'createdAt': createdAt.toUtc().toIso8601String(),
      };

  static RideBookingAttempt? fromJson(Object? value) {
    if (value is! Map) return null;
    final bookingKey = value['bookingKey'];
    final requestFingerprint = value['requestFingerprint'];
    final createdAtRaw = value['createdAt'];
    if (bookingKey is! String ||
        !Uuid.isValidUUID(fromString: bookingKey) ||
        requestFingerprint is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(requestFingerprint) ||
        createdAtRaw is! String) {
      return null;
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null) return null;
    return RideBookingAttempt(
      bookingKey: bookingKey,
      requestFingerprint: requestFingerprint,
      createdAt: createdAt.toUtc(),
    );
  }
}

/// Returns a deterministic SHA-256 for JSON-compatible ride request data.
///
/// Map keys are sorted recursively; list order remains significant because the
/// order of pre-trip stops changes the trip. The canonical JSON exists only in
/// memory and only its digest is passed to [RideBookingAttemptStore].
String rideBookingRequestFingerprint(Map<String, Object?> request) {
  final canonical = _canonicalJson(request);
  return sha256.convert(utf8.encode(canonical)).toString();
}

String _canonicalJson(Object? value) {
  if (value is Map) {
    final entries = value.entries.map((entry) {
      final key = entry.key;
      if (key is! String) {
        throw ArgumentError.value(key, 'request', 'JSON keys must be strings');
      }
      return MapEntry(key, entry.value);
    }).toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return '{${entries.map((entry) => '${jsonEncode(entry.key)}:'
        '${_canonicalJson(entry.value)}').join(',')}}';
  }
  if (value is Iterable) {
    return '[${value.map(_canonicalJson).join(',')}]';
  }
  if (value == null || value is bool || value is num || value is String) {
    return jsonEncode(value);
  }
  throw ArgumentError.value(
    value.runtimeType,
    'request',
    'Ride booking request contains a non-JSON value',
  );
}

/// SharedPreferences-backed store for the single unresolved ride attempt.
///
/// All mutations are serialized so a double-tap cannot generate two UUIDs in
/// the same process. The server remains the authority for whether the key was
/// consumed and whether its ride is terminal.
class RideBookingAttemptStore {
  RideBookingAttemptStore({
    Future<SharedPreferences> Function()? preferences,
    String Function()? bookingKeyFactory,
    DateTime Function()? clock,
  })  : _preferences = preferences ?? SharedPreferences.getInstance,
        _bookingKeyFactory = bookingKeyFactory ?? const Uuid().v4,
        _clock = clock ?? DateTime.now;

  static const storageKey = 'myshop.ride_booking_attempt.v1';

  final Future<SharedPreferences> Function() _preferences;
  final String Function() _bookingKeyFactory;
  final DateTime Function() _clock;
  Future<void> _operationTail = Future<void>.value();

  Future<RideBookingAttempt?> read() => _serialized(() async {
        final preferences = await _preferences();
        return _readUnsafe(preferences);
      });

  /// Reuses the UUID for an identical request; otherwise persists a new UUID.
  /// Callers must reconcile a different pending fingerprint with the server
  /// before invoking this method.
  Future<RideBookingAttempt> getOrCreate(String requestFingerprint) =>
      _serialized(() async {
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(requestFingerprint)) {
          throw ArgumentError.value(
            requestFingerprint,
            'requestFingerprint',
            'Expected a lowercase SHA-256 digest',
          );
        }
        final preferences = await _preferences();
        final existing = _readUnsafe(preferences);
        if (existing?.requestFingerprint == requestFingerprint) {
          return existing!;
        }

        final created = RideBookingAttempt(
          bookingKey: _bookingKeyFactory(),
          requestFingerprint: requestFingerprint,
          createdAt: _clock().toUtc(),
        );
        if (!Uuid.isValidUUID(fromString: created.bookingKey)) {
          throw StateError('The booking key factory returned an invalid UUID');
        }
        await preferences.setString(storageKey, jsonEncode(created.toJson()));
        return created;
      });

  /// Clears the pending attempt. When [bookingKey] is supplied, a newer key
  /// created by another in-process operation is left untouched.
  Future<void> clear({String? bookingKey}) => _serialized(() async {
        final preferences = await _preferences();
        if (bookingKey != null) {
          final current = _readUnsafe(preferences);
          if (current == null || current.bookingKey != bookingKey) return;
        }
        await preferences.remove(storageKey);
      });

  /// Logout boundary: a second user on this install must never inherit the
  /// previous user's unresolved booking key.
  Future<void> clearAll() => clear();

  RideBookingAttempt? _readUnsafe(SharedPreferences preferences) {
    final raw = preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final attempt = RideBookingAttempt.fromJson(jsonDecode(raw));
      if (attempt != null) return attempt;
    } catch (_) {
      // Corrupt local state is not authority and must never be logged because
      // older app versions may have written more than the minimal schema.
    }
    return null;
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Cached last-known device GPS fix. Populated by [CurrentLocationService.ensure]
/// (which runs at app start and on demand). Stays null when location services
/// are off or permission is denied — callers must fall back themselves
/// (typically to the pilot-city centre).
final currentDevicePositionProvider = StateProvider<Position?>((_) => null);

/// Resolves and caches the device's current location. Use this instead of
/// calling Geolocator directly so every screen shares the same cached fix
/// and the user only sees the permission prompt once per session.
class CurrentLocationService {
  CurrentLocationService(this._ref);

  final Ref _ref;

  /// Serialises concurrent ensure() calls. Geolocator throws
  /// PermissionRequestInProgressException if requestPermission() is
  /// invoked while another request is still pending, which happens on
  /// first launch when several providers/widgets fire location reads
  /// during the initial build. Sharing a single in-flight Future across
  /// callers collapses the parallel requests into one.
  Future<Position?>? _inFlight;

  /// Returns the cached fix if we already have one, otherwise requests
  /// permission (if needed), reads the GPS, caches it, and returns the
  /// new fix. Returns `null` when the user denies permission or location
  /// services are off — the caller decides the fallback.
  ///
  /// Strategy: yield the OS-cached fix first (fast, <100ms) so map screens
  /// open at the right place, then refresh with a fresh GPS read on a short
  /// timeout. Without the timeout, iOS can hang 30s–2min waiting for the
  /// sensor to settle (kCLErrorDomain 0).
  Future<Position?> ensure({bool forceRefresh = false}) {
    if (!forceRefresh) {
      final cached = _ref.read(currentDevicePositionProvider);
      if (cached != null) return Future.value(cached);
      // Reuse an already-running ensure() instead of starting a parallel
      // permission request that the plugin would reject.
      final existing = _inFlight;
      if (existing != null) return existing;
    }

    final future = _ensureInternal(waitForFresh: forceRefresh);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<Position?> _ensureInternal({required bool waitForFresh}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      // Fast path: seed the cache from the OS last-known position. Normal
      // callers return it immediately while a fresh fix updates the shared
      // cache in the background; map pickers can request forceRefresh=true.
      Position? bestSoFar;
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          bestSoFar = last;
          _ref.read(currentDevicePositionProvider.notifier).state = last;
        }
      } catch (error) {
        debugPrint('[LOC] getLastKnownPosition failed: $error');
      }

      if (bestSoFar != null && !waitForFresh) {
        unawaited(_refreshCurrentPosition(bestSoFar));
        return bestSoFar;
      }

      return _refreshCurrentPosition(bestSoFar);
    } catch (error) {
      debugPrint('[LOC] location permission/service check failed: $error');
      return _ref.read(currentDevicePositionProvider);
    }
  }

  Future<Position?> _refreshCurrentPosition(Position? fallback) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );
      _ref.read(currentDevicePositionProvider.notifier).state = position;
      return position;
    } catch (error) {
      debugPrint('[LOC] getCurrentPosition failed: $error — '
          'using ${fallback == null ? 'no fallback' : 'last-known'}');
      return fallback;
    }
  }
}

final currentLocationServiceProvider = Provider<CurrentLocationService>((ref) {
  return CurrentLocationService(ref);
});

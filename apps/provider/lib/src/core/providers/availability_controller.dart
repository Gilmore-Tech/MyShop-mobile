import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/profile/providers/provider_type_provider.dart';
import '../di/providers.dart';
import 'provider_status_provider.dart';

/// Last known GPS fix — populated by the location bridge whenever a fix
/// arrives. Used so the offline-toggle POST can include coordinates even
/// after the location stream has been torn down.
///
/// TODO(backend-B1): once POST /providers/availability ships, coords are
/// no longer required and this cache can be retired.
final lastKnownPositionProvider = StateProvider<Position?>((_) => null);

/// Orchestrates the online/offline transition for the provider:
///
///   - goOnline(): flip local state → location stream starts →
///     `POST /location/{driver,artisan}/update` fires from the bridge with
///     status:'online'. This controller just owns the local flip; the bridge
///     in `socket_provider.dart` does the rest.
///   - goOffline(): POST `status:'offline'` with last-known coords, then
///     flip local state so the UI reflects the intent immediately. Even if
///     the POST fails, local state still flips — otherwise the user is
///     stuck online on flaky networks.
///
/// Rationale: previously the app only signalled "offline" via the socket
/// disconnect, leaving the backend to infer offline via a location TTL.
/// That meant a freshly-toggled-off driver/artisan could still receive
/// dispatches for minutes. Explicit offline POST closes that window.
class AvailabilityController {
  AvailabilityController(this._ref);

  final Ref _ref;

  /// Flip to online. Verifies location services + permission first because
  /// an online provider without a GPS fix is invisible to the matcher
  /// (the backend requires `current_location IS NOT NULL`).
  ///
  /// Returns `null` on success, or a user-facing error message on failure.
  Future<String?> goOnline() async {
    final gate = await _checkLocationReady();
    if (gate != null) return gate;
    _ref.read(providerStatusProvider.notifier).goOnline();
    return null;
  }

  /// Verify location services are on and permission is granted. Requests
  /// permission if it hasn't been asked yet. Returns a user-facing error
  /// message if location can't be used, `null` if all good.
  Future<String?> _checkLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return 'Turn on Location Services to go online.';
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return 'Location permission is required to go online. '
          'Grant it in Settings and try again.';
    }
    return null;
  }

  /// Force the provider offline without a user gesture — used by the
  /// location-permission watcher when the OS revokes permission or
  /// services are disabled mid-session.
  Future<void> forceOfflineDueToLocationLost() async {
    if (_ref.read(providerStatusProvider).isOffline) return;
    debugPrint('[Availability] forcing offline: location unavailable');
    await goOffline();
  }

  /// Flip to offline and inform the backend so the matcher stops
  /// dispatching. Local state flips immediately; the backend call is
  /// best-effort.
  Future<void> goOffline() async {
    _ref.read(providerStatusProvider.notifier).goOffline();
    await _postOffline();
  }

  Future<void> _postOffline() async {
    final pos = _ref.read(lastKnownPositionProvider);
    if (pos == null) {
      // No cached fix — can't satisfy the current endpoint's required
      // lat/lng. Safe to skip: the device never successfully went online
      // from the backend's perspective either.
      debugPrint('[Availability] no cached position — skipping offline POST');
      return;
    }

    final isArtisan = _ref.read(providerTypeProvider).isArtisan;
    final locationService = _ref.read(locationServiceProvider);
    try {
      if (isArtisan) {
        await locationService.updateArtisanLocation(
          latitude: pos.latitude,
          longitude: pos.longitude,
          status: 'offline',
        );
      } else {
        await locationService.updateDriverLocation(
          latitude: pos.latitude,
          longitude: pos.longitude,
          status: 'offline',
        );
      }
      debugPrint('[Availability] offline POST sent');
    } on ApiException catch (e) {
      debugPrint('[Availability] offline POST failed: $e');
    } catch (e) {
      debugPrint('[Availability] offline POST error: $e');
    }
  }
}

final availabilityControllerProvider = Provider<AvailabilityController>((ref) {
  return AvailabilityController(ref);
});
